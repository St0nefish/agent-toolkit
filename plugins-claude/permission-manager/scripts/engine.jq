# engine.jq — permission-manager v3 classifier (one jq run per parsed command).
#
# Input (.):  the shfmt --tojson AST of one command string.
# Arguments:  --arg cmd/cwd/home/rhome/depth, --slurpfile tools/paths/allow/
#             danger/regex (the rules/*.json data files); -L scripts/ for the
#             pathclass module.
# Output (jq -j, NUL-terminated items; see render in pathclass.jq):
#   1. verdict: ALLOW | ASK | DENY | PASS
#   2. reason (single line, for logs and tests)
#   3. hook JSON for Claude Code ("" for PASS)
#   4. audit JSON line ("" for PASS)
#   5+. tagged extras "K<TAB>value": p/s = local/remote program text to
#       re-parse for danger rules; r/a = paths an ALLOW must resolve clean;
#       g = git dir whose repo config must be clean; w = write targets of a PASS.
#   last. END (lets the caller detect truncated output).
#
# Every CallExpr anywhere in the tree becomes a unit (full recursive descent via
# paths(), so no node type can hide a command). Precedence: any danger hit =>
# ASK/DENY; else any non-safe unit or structure => PASS; else ALLOW.
include "pathclass";

($tools[0]) as $T
| ($allow[0]) as $A
| ($danger[0]) as $D
| ($regex[0]) as $R
| pc_paths as $P
| (if $T.arg_specs then $T.arg_specs else {} end) as $AS
| def is_secret: pc_is_secret($P);
  def secret_ancestor: pc_secret_ancestor($P);
  def is_persist: pc_is_persist($P);
  def is_registry: pc_is_registry($P);
  def is_device: pc_is_device($P);
  def is_kernel_trigger: pc_is_kernel_trigger($P);

# Operator probe. gate.sh prepends a fixed 5-statement preamble (see PROBE in
# gate.sh) to every parsed string, so the same shfmt run tells us how this shfmt
# version encodes operators (integers before v3.14, strings since). $OPS maps the
# raw encoding to the operator text; the probe statements are then dropped.
  (.Stmts // []) as $st
| ([$st[0].Redirs[]?.Op | tostring]) as $rops
| ([">", ">>", "&>", "&>>", ">|", "<>", ">&", "<&", "<", "<<<", "<<", "<<-"]) as $rnames
| ([$st[1:5][] | .Cmd.Op | tostring]) as $bops
| (if ($rops | length) == 12 and ($bops | length) == 4 and all($st[1:5][]; .Cmd.Type? == "BinaryCmd")
   then ([range(0; 12) as $i | {key: $rops[$i], value: $rnames[$i]}]
         + [range(0; 4) as $i | {key: $bops[$i], value: (["|", "|&", "&&", "||"][$i])}]) | from_entries
   else error("shfmt operator probe failed") end) as $OPS
| (.Stmts = $st[5:]) as $ast
| $ast
| 200 as $MAX_UNITS

| def PH: "__PM_UNRESOLVED__";
  def rx: if type == "string" and startswith("@") then $R[.[1:]] else . end;
  def litw($s): {s: $s, ph: $s, glob: false, why: null, node: null};
  def unw($why): {s: null, ph: PH, glob: false, why: $why, node: null};
  def inlist($l): . as $x | any($l[]; . == $x);

  # ---------- words ----------
  # Decode the body of a $'...' (ANSI-C) quote exactly as bash does: the value
  # ends at the first NUL (bash truncates there); an unknown escape such as \q
  # (or \x, \u without digits) stays literally as backslash + character, as in
  # bash. null ("unresolved") for \c followed by a backslash or nothing, or an
  # escape that yields a non-ASCII byte or code point (locale dependent).
  def numval($b):
    explode | reduce .[] as $c (0; . * $b + (if $c >= 97 then $c - 87 elif $c >= 65 then $c - 55 else $c - 48 end));
  def ansic:
    {"a": 7, "b": 8, "e": 27, "E": 27, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11, "\\": 92, "'": 39, "\"": 34, "?": 63} as $simple
    | [scan("\\\\(?:x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|[0-7]{1,3}|c[^\\\\])|\\\\[\\s\\S]?|[^\\\\]+")
     | if startswith("\\") | not then {t: .}
       else .[1:] as $e
         | if $e == "" or $e == "c" then null
           elif ($e | test("^x[0-9A-Fa-f]")) then {c: ($e[1:] | numval(16))}
           elif ($e | test("^[uU][0-9A-Fa-f]")) then {c: ($e[1:] | numval(16))}
           elif ($e | test("^[0-7]")) then {c: ($e | numval(8) | . % 256)}
           elif ($e | startswith("c")) and ($e | length) == 2 then
             ($e[1:] | explode[0]) as $x
             | if $x >= 128 then null elif $x == 63 then {c: 127} else {c: (($e[1:] | ascii_upcase | explode[0]) % 32)} end
           elif $simple[$e] != null then {c: $simple[$e]}
           else {t: ("\\" + $e)} end
       end] as $all
    | ((first(range(0; $all | length) as $i | select($all[$i] != null and $all[$i].c == 0) | $i)) // ($all | length)) as $z
    | $all[:$z] as $toks
    | if any($toks[]; . == null or (.c != null and .c >= 128)) then null
      else $toks | map(if .t != null then .t else ([.c] | implode) end) | join("") end;

  def homeparam:
    .Type == "ParamExp" and (.Param.Value? == "HOME")
    and ((keys - ["Type", "Pos", "End", "Dollar", "Rbrace", "Param", "Short"]) | length == 0);

  def part_res($i; $dq):
    . as $p
    | if $p.Type == "Lit" then
        if $dq then
          ($p.Value | gsub("\\\\\n"; "") | gsub("\\\\(?<c>[$`\"\\\\])"; .c)) as $u
          | {s: $u, ph: $u, glob: false}
        else
          ($p.Value) as $v
          | ($v | gsub("\\\\[\\s\\S]"; "")) as $bare
          | ($v | gsub("\\\\(?<c>[\\s\\S])"; .c)) as $u
          # zsh (Claude's Bash tool runs the user's shell) with EXTENDED_GLOB
          # also globs on # ^ and a non-leading ~ (.en#v matches .env).
          | (($bare | test("[*?#^]|\\[.*\\]|.~")) or ($i > 0 and ($bare | startswith("~")))
             or ($bare | test("\\{[^}]*(,|\\.\\.)[^}]*\\}"))) as $g
          | if $i == 0 and ($v | test("^~(/|$)")) then ($home + $u[1:]) as $x | {s: $x, ph: $x, glob: $g}
            elif $i == 0 and ($v | startswith("~")) then {s: null, ph: PH, glob: $g, why: "tilde"}
            else {s: $u, ph: $u, glob: $g} end
        end
      elif $p.Type == "SglQuoted" then
        if ($p.Dollar // false) then ($p.Value | ansic) as $d
          | if $d == null then {s: null, ph: PH, why: "ansi-c quote"} else {s: $d, ph: $d, glob: false} end
        else {s: $p.Value, ph: $p.Value, glob: false} end
      elif $p.Type == "DblQuoted" then
        [($p.Parts // [])[] | part_res(1; true)] as $rs
        | {s: (if all($rs[]; .s != null) then ($rs | map(.s) | join("")) else null end),
           ph: ($rs | map(.ph) | join("")), glob: false,
           why: ([$rs[] | select(.s == null) | .why][0])}
      elif ($p | homeparam) then {s: $home, ph: $home, glob: false}
      elif $p.Type == "ParamExp" then {s: null, ph: PH, why: "variable"}
      elif $p.Type == "CmdSubst" then {s: null, ph: PH, why: "command substitution"}
      elif $p.Type == "ProcSubst" then {s: "/dev/fd/63", ph: PH, glob: false}
      elif $p.Type == "ArithmExp" then {s: null, ph: PH, why: "arithmetic expansion"}
      elif $p.Type == "ExtGlob" then {s: null, ph: PH, why: "extended glob"}
      else {s: null, ph: PH, why: "unknown word part"} end;

  # A word of several parts with an unquoted "{" may brace-expand across the
  # quoted parts (cat {a,~/.ssh/con'f'ig}): unresolved. psub marks a bare
  # process substitution (its /dev/fd/63 stand-in is not a real operand).
  def wres:
    (.Parts // []) as $ps
    | [range(0; $ps | length) as $i | $ps[$i] | part_res($i; false)] as $rs
    | (($ps | length) > 1 and any($ps[]; .Type == "Lit" and (.Value | gsub("\\\\[\\s\\S]"; "") | contains("{")))) as $brace
    | {s: (if $brace then null elif all($rs[]; .s != null) then ($rs | map(.s) | join("")) else null end),
       ph: ($rs | map(.ph) | join("")),
       glob: any($rs[]; .glob // false),
       why: (if $brace then "brace expansion across quotes" else ([$rs[] | select(.s == null) | .why][0]) end),
       psub: (($ps | length) == 1 and $ps[0].Type == "ProcSubst"),
       node: .};

  # ---------- paths ----------
  def str_bad_at($wd): canon_at($wd) | (. == null) or is_secret;
  def str_bad: str_bad_at($cwd);
  def str_secret: canon | . != null and is_secret;
  # Any glob in a checked path operand is non-safe: a wildcard can match a
  # secret name (*_rsa, *env, /etc/shado?) that a lexical check cannot rule out.
  def w_bad_at($wd): if .s == null or .glob then true else (.s | str_bad_at($wd)) end;
  def w_bad: w_bad_at($cwd);
  def flagtok_bad_at($wd):
    (if contains("=") then (.[(index("=") + 1):] | str_bad_at($wd)) else false end)
    or (test("[/~]") and (.[([indices("/")[], indices("~")[]] | min):] | str_bad_at($wd)));

  # ---------- redirections ----------
  def redir_info:
    {op: ($OPS[.Op | tostring] // ("?" + (.Op | tostring))), n: (.N.Value? // null),
     w: (if .Word then (.Word | wres) else null end),
     hdoc: (if .Hdoc then (.Hdoc | wres) else null end)};
  def rclass:
    .op as $o
    | if ($o | inlist([">", ">>", "&>", "&>>", ">|", "<>"])) then "write"
      elif $o == ">&" or $o == "<&" then
        (if .w.s != null and (.w.s | test("^([0-9]+-?|-)$")) then "dup" elif $o == ">&" then "write" else "in" end)
      elif $o == "<" then "in"
      elif ($o | inlist(["<<", "<<-", "<<<"])) then "heredoc"
      else "unknown" end;
  def safe_write_target: .w.s != null and ((.w.s | canon) as $c | $c != null and ($c | inlist($P.safe_write_targets)));

  # ---------- generic argument parser used by rule predicates ----------
  # spec: {arg_flags: {flag: nargs}, short_combine: bool}
  def parse_args($spec0):
    . as $ws
    | ($spec0 | if type == "string" then {arg_flags: .} else . end
       | if (.arg_flags | type) == "string" then .arg_flags = ($AS[.arg_flags[1:]] // error("unknown arg spec")) else . end) as $spec
    | ($spec.arg_flags // {}) as $af
    | (if $spec.short_combine == false then false else true end) as $sc
    | reduce range(0; $ws | length) as $i ({skip: 0, dd: false, flags: [], pos: []};
        if .skip > 0 then .skip -= 1
        else ($ws[$i]) as $w | ($w.s) as $t
          | if .dd or $t == null or ($t | startswith("-") | not) or $t == "-" then .pos += [$w]
            elif $t == "--" then .dd = true
            elif ($t | startswith("--")) or ($sc | not) then
              if ($t | contains("=")) then ($t | index("=")) as $k | .flags += [{n: $t[:$k], v: $t[($k + 1):], vw: [litw($t[($k + 1):])], at: (.pos | length)}]
              elif ($af[$t] // 0) > 0 then .flags += [{n: $t, v: ($ws[$i + 1].s // null), vw: $ws[($i + 1):($i + 1 + $af[$t])], at: (.pos | length)}] | .skip = $af[$t]
              else .flags += [{n: $t, v: null, at: (.pos | length)}] end
            else
              ($t[1:] | split("")) as $cs
              | (reduce range(0; $cs | length) as $j ({done: false, fl: [], skip: 0};
                  if .done then .
                  else ("-" + $cs[$j]) as $f
                    | if ($af[$f] // 0) > 0 then
                        if $j < ($cs | length) - 1 then .fl += [{n: $f, v: ($cs[($j + 1):] | join("")), vw: [litw($cs[($j + 1):] | join(""))]}] | .done = true
                        else .fl += [{n: $f, v: ($ws[$i + 1].s // null), vw: $ws[($i + 1):($i + 1 + $af[$f])]}] | .skip = $af[$f] | .done = true end
                      else .fl += [{n: $f, v: null}] end
                  end)) as $r
              | (.pos | length) as $np | .flags += ($r.fl | map(. + {at: $np})) | .skip = $r.skip
            end
        end);

  def fmatch($rf; $abbrev):
    . as $n
    | $n == $rf
      or ($abbrev and ($rf | startswith("--")) and ($n | startswith("--")) and ($n | length) >= 3 and ($rf | startswith($n)));
  def has_flag($list; $abbrev): any(.flags[]; .n as $n | any($list[]; . as $rf | $n | fmatch($rf; $abbrev)));

  # ---------- command name / wrappers ----------
  def normname:
    if .s == null or .glob or .s == "" then {name: null, trusted: false}
    elif (.s | contains("/")) then {name: (.s | bname), trusted: ((.s | dname) as $d | $d | inlist($T.trusted_dirs))}
    else {name: .s, trusted: true} end;

  def mkassign:
    if .s == null then {name: null, v: unw("variable")}
    else (.s | index("=")) as $k | {name: .s[:$k], v: litw(.s[($k + 1):])} end;

  def wparse($spec):
    . as $ws
    | ($spec.flags // []) as $fl | ($spec.arg_opts // []) as $ao | ($spec.long_arg_opts // []) as $lao
    | ($spec.stop_opts // []) as $so | ($spec.split_opts // []) as $sp | ($spec.unsafe_opts // []) as $uo
    | reduce range(0; $ws | length) as $i (
        {skip: 0, done: false, start: null, stop: false, unknown: false, unsafe: false, assigns: [], split: null,
         posskip: ($spec.skip_positionals // 0)};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($ws[$i].s) as $t
          | if $t == null then .done = true | .start = $i
            elif $t == "--" then .done = true | .start = ($i + 1)
            elif ($t | inlist($fl)) then (if ($t | inlist($uo)) then .unsafe = true else . end)
            elif ($t | startswith("--")) then
              ($t | split("=")[0]) as $nm
              | if ($nm | inlist($so)) then .stop = true | .done = true
                elif ($nm | inlist($sp)) then
                  (if ($t | contains("=")) then .split = litw($t[(($t | index("=")) + 1):]) | .start = ($i + 1)
                   else .split = ($ws[$i + 1] // unw("missing")) | .start = ($i + 2) end) | .done = true
                else (if ($nm | inlist($uo)) then .unsafe = true else . end)
                  | if ($t | contains("=")) then (if ($nm | inlist($lao)) then . else .unknown = true end)
                    elif ($t | inlist($lao)) then .skip = 1
                    else .unknown = true end
                end
            elif ($t | startswith("-")) and ($t | length) > 1 then
              if ($spec.numeric_ok // false) and ($t | test("^-[0-9]+$")) then .
              else ($t[1:] | split("")) as $cs
                | reduce range(0; $cs | length) as $j (. + {cdone: false};
                    if .cdone then .
                    else ("-" + $cs[$j]) as $f
                      | if ($f | inlist($so)) then .stop = true | .done = true | .cdone = true
                        elif ($f | inlist($sp)) then
                          (if $j < ($cs | length) - 1 then .split = litw($cs[($j + 1):] | join("")) | .start = ($i + 1)
                           else .split = ($ws[$i + 1] // unw("missing")) | .start = ($i + 2) end)
                          | .done = true | .cdone = true
                        elif ($f | inlist($ao)) then
                          (if ($f | inlist($uo)) then .unsafe = true else . end)
                          | (if $j < ($cs | length) - 1 then . else .skip = 1 end) | .cdone = true
                        elif ($f | inlist($fl)) then (if ($f | inlist($uo)) then .unsafe = true else . end)
                        else .unknown = true end
                    end)
                | del(.cdone)
              end
            elif ($spec.assigns // false) and ($t | test("^[A-Za-z_][A-Za-z0-9_]*=")) then .assigns += [$ws[$i]]
            elif .posskip > 0 then .posskip -= 1
            else .done = true | .start = $i end
        end);

  # Container/cluster exec forms (docker exec, kubectl exec --, incus exec --):
  # index into the full word list where the executed argv starts, or null.
  def exec_start($spec):
    . as $ws
    | ($spec.arg_flags | if type == "string" then $AS[.[1:]] else (. // {}) end) as $af
    | first(foreach range(1; ($ws | length) + 1) as $i (
        {skip: 0, pos: [], matched: false, tgt: 0, out: null, stop: false};
        if .out != null or .stop then .
        elif $i == ($ws | length) then .stop = true
        elif .skip > 0 then .skip -= 1
        else ($ws[$i].s) as $t
          | if $t == null then (if .matched and .tgt >= $spec.target then .out = $i else .stop = true end)
            elif $t == "--" then (if .matched and .tgt >= $spec.target then .out = ($i + 1) else .stop = true end)
            elif ($t | startswith("-")) and ($t | length) > 1 then
              (if .matched and .tgt >= $spec.target and $spec.mode == "after_target" then .out = $i
               elif ($t | contains("=")) then .
               elif ($af[$t] // 0) > 0 then .skip = $af[$t]
               elif ($t | test("^-[A-Za-z0-9]{2,}$")) then
                 ($t[1:] | split("")) as $cs
                 | (first(range(0; $cs | length) as $j | select(($af["-" + $cs[$j]] // 0) > 0) | $j) // null) as $j
                 | if $j != null and $j == ($cs | length) - 1 then .skip = 1 else . end
               else . end)
            elif .matched then
              (if .tgt < $spec.target then .tgt += 1 else .out = $i end)
            else .pos += [$t]
              | . as $st
              | if any($spec.routes[]; . == $st.pos) then .matched = true
                elif any($spec.routes[]; .[:($st.pos | length)] == $st.pos) then .
                else .stop = true end
            end
        end;
        select(.out != null or .stop) | .out)) // null;

  def unwrap($n):
    if $n > 8 then .unsafe += ["wrapper nesting too deep"]
    elif (.words | length) == 0 then .
    else (.words[0] | normname) as $nn
      | .name = $nn.name | .trusted = (.trusted and $nn.trusted)
      | if $nn.name != null and ($T.exec_wrappers[$nn.name] != null)
           and ((.words | exec_start($T.exec_wrappers[$nn.name])) as $k | $k != null and $k < (.words | length)) then
          (.words | exec_start($T.exec_wrappers[$nn.name])) as $k
          | .wrappers += [$nn.name] | .unsafe += ["command run inside a container/cluster via " + $nn.name]
          | .words = .words[$k:]
          | unwrap($n + 1)
        elif $nn.name != null and ($T.wrappers[$nn.name] != null)
           and (($T.wrappers[$nn.name].require_opt // null) as $ro
                | $ro == null or any(.words[1:][]; .s != null and ((.s | split("=")[0]) | inlist($ro)))) then
          $T.wrappers[$nn.name] as $spec
          | (.words[1:] | wparse($spec)) as $r
          | .assigns += ($r.assigns | map(mkassign))
          | (if $r.split != null then
               .payloads += [([$r.split.ph] + (.words[1:][($r.start // 0):] | map(.ph))) | join(" ")]
               | .unsafe += ["env -S split string"]
             else . end)
          | if $r.stop or $r.split != null or $r.start == null or ($r.start >= ((.words | length) - 1)) then
              .wstop = $r.stop
              | (if ($spec.priv // false) and any(.words[1:][]; .s != null and (.s | test("^(--shell|--login|-[A-Za-z]*[si][A-Za-z]*)$"))) then .shell_like = true | .stdin_prog = true else . end)
              | (if ($spec.shell_if_empty // false) and ($r.stop | not) and $r.split == null then .shell_like = true | .stdin_prog = true | .unsafe += ["wrapper " + $nn.name] else . end)
              | (if $r.unknown then .unsafe += ["unknown option for " + $nn.name] else . end)
            else
              .wrappers += [$nn.name]
              | (if ($spec.transparent // false) | not then .unsafe += ["wrapper " + $nn.name] else . end)
              | (if $r.unknown then .unsafe += ["unknown option for " + $nn.name] else . end)
              | (if $r.unsafe then .unsafe += ["unsafe option for " + $nn.name] else . end)
              | (if $spec.priv // false then .priv = true else . end)
              | (if $spec.xargs // false then .xargs = true else . end)
              | (.words[1:][$r.start:]) as $inner
              | (if $spec.payload_join // false then .payloads += [$inner | map(.ph) | join(" ")] else . end)
              | .words = $inner
              | unwrap($n + 1)
            end
        else . end
    end;

  def gitnorm:
    (.words[1:]) as $ws
    | (reduce range(0; $ws | length) as $i ({skip: 0, done: false, sub: null, start: null, c: [], unsafe: false, wd: $cwd, wdraw: $cwd};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($ws[$i].s) as $t
          | if $t == null then .done = true | .unsafe = true | .start = $i
            elif ($t | startswith("-") | not) then .done = true | .sub = $t | .start = ($i + 1)
            else ($t | split("=")[0]) as $nm
              | (if ($nm | inlist($T.git.safe_globals)) then . else .unsafe = true end)
              | if $t == "-C" then
                  (.wd) as $w | ($ws[$i + 1].s) as $v
                  | .wd = (if $w == null or $v == null or ($v | startswith("~")) then null else ($v | canon_at($w)) end)
                  | .wdraw = (if .wd == null then null elif ($v | startswith("/")) then $v else .wdraw + "/" + $v end) | .skip = 1
                elif $t == "-c" then .c += [(($ws[$i + 1].s // "") | split("=")[0] | ascii_downcase)] | .skip = 1
                elif ($t | startswith("--config-env")) then
                  (if ($t | contains("=")) then $t[(($t | index("=")) + 1):] else ($ws[$i + 1].s // "") end) as $kv
                  | .c += [($kv | split("=")[0] | ascii_downcase)]
                  | (if ($t | contains("=")) then . else .skip = 1 end)
                elif ($t | test("^-c.")) then .c += [($t[2:] | split("=")[0] | ascii_downcase)]
                elif ($t | contains("=")) then .
                elif ($t | inlist($T.git.arg_globals)) and $t != "--exec-path" then .skip = 1
                else . end
            end
        end)) as $g
    | .sub = $g.sub | .gitc = $g.c | .git_unsafe = ($g.unsafe or $g.wd == null) | .wd = $g.wd | .wdraw = $g.wdraw
    | .args = (if $g.start == null then [] else $ws[$g.start:] end);

  # ---------- interpreters ----------
  def is_shell: .name != null and (.name | inlist($T.shells));
  def is_interp: (.shell_like // false) or is_shell or (.name != null and (.name | test($T.interp_re)));

  def shell_scan:
    . as $a
    | reduce range(0; $a | length) as $i ({skip: 0, done: false, hasc: false, sflag: false, dash: false, first: null};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($a[$i].s) as $t
          | if $t == null then .done = true | .first = $i
            elif $t == "--" then .done = true | .first = ($i + 1)
            elif $t == "-" then .done = true | .first = ($i + 1) | .dash = true
            elif ($t | inlist($T.shell_arg_opts)) then .skip = 1
            elif ($t | test("^[-+][A-Za-z]+$")) then
              (if ($t | startswith("-")) and ($t | contains("c")) then .hasc = true else . end)
              | (if ($t | startswith("-")) and ($t | contains("s")) then .sflag = true else . end)
            elif ($t | startswith("--")) then .
            else .done = true | .first = $i end
        end);

  def interp_scan:
    . as $a
    | reduce range(0; $a | length) as $i ({skip: 0, done: false, prog: false, dash: false, first: null};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($a[$i].s) as $t
          | if $t == null then .done = true | .first = $i
            elif $t == "-" then .done = true | .dash = true
            elif $t == "--" then .done = true | .first = ($i + 1)
            elif ($t | inlist($T.interp_program_flags)) or ($t | test("^-[A-Za-z]*[cem]$")) then .prog = true | .done = true
            elif ($t | inlist($T.interp_arg_opts)) then .skip = 1
            elif ($t | startswith("-")) then .
            else .done = true | .first = $i end
        end);

  def su_payload:
    . as $a
    | [range(0; $a | length) as $i | ($a[$i].s) as $t
       | if $t == "-c" or $t == "--command" or ($t != null and ($t | test("^-[a-z]*c$"))) then ($a[$i + 1].ph // empty)
         elif $t != null and ($t | startswith("--command=")) then $t[10:]
         else empty end];

  # ssh-style argv: options (letters in $argl take a value, attached or next),
  # the host, more options, then the remote command (ssh re-scans options after
  # the host). Returns the -o values and the index where the command starts.
  def ssh_parse($argl; $long):
    . as $a
    | reduce range(0; $a | length) as $i ({skip: 0, done: false, host: null, cmd: null, o: [], dd: false, lo: []};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($a[$i].s) as $t
          | if .dd or $t == null or ($t | startswith("-") | not) or $t == "-" then
              (if .host == null then .host = $i else .cmd = $i | .done = true end)
            elif $t == "--" then (if .host == null then .dd = true else .cmd = ($i + 1) | .done = true end)
            elif ($t | startswith("--")) then
              .lo += [$t] | (if ($t | contains("=") | not) and ($t | inlist($long)) then .skip = 1 else . end)
            else ($t[1:] | split("")) as $cs
              | (first(range(0; $cs | length) as $j | select($argl | contains($cs[$j])) | $j) // null) as $j
              | if $j == null then .
                else ($cs[$j]) as $f | ($t[($j + 2):]) as $rest
                  | if $rest != "" then (if $f == "o" then .o += [$rest] else . end)
                    else (if $f == "o" then .o += [($a[$i + 1].s // "")] else . end) | .skip = 1 end
                end
            end
        end);

  # Interpreter argv scan (python -c, perl -e/-i, node -e/-p, php -r, ...):
  # literal code strings (.ph, so literal portions of partly unresolved words
  # still count), perl/ruby -i, and the operands after the code/script.
  def iscan($f):
    . as $a
    | reduce range(0; $a | length) as $i (
        {skip: 0, skipcode: false, codes: [], inplace: false, files: [], script: false, opts: true};
        if .skip > 0 then (if .skipcode then .codes += [$a[$i].ph] | .skipcode = false else . end) | .skip -= 1
        else ($a[$i].s) as $t
          | if (.opts | not) or $t == null then
              .opts = false | (if (.codes | length) == 0 and (.script | not) then .script = true else .files += [$a[$i]] end)
            elif $t == "--" then .opts = false
            elif $t == "-" then .opts = false | .script = true
            elif ($t | startswith("--")) then
              ($t | split("=")[0]) as $nm
              | if ($nm | inlist($f.code_long // [])) then
                  (if ($t | contains("=")) then .codes += [$t[(($t | index("=")) + 1):]] else .skip = 1 | .skipcode = true end)
                elif ($t | contains("=") | not) and ($nm | inlist($f.long_args // [])) then .skip = 1
                else . end
            elif ($t | startswith("-")) and ($t | length) > 1 then
              ($t[1:] | split("")) as $cs
              | reduce range(0; $cs | length) as $j (. + {cd: false};
                  if .cd then .
                  else $cs[$j] as $c | ($cs[($j + 1):] | join("")) as $rest
                    | if (($f.code_chars // "") | contains($c)) then
                        .cd = true
                        | (if $rest != "" and (if $f | has("attached_code") then $f.attached_code else true end) then .codes += [$rest] else .skip = 1 | .skipcode = true end)
                      elif ($f.inplace_char // "") == $c then .inplace = true | .cd = true
                      elif (($f.stop_chars // "") | contains($c)) then .cd = true | .opts = false | .script = true
                      elif (($f.arg_chars // "") | contains($c)) then .cd = true | (if $rest == "" then .skip = 1 else . end)
                      elif (($f.attached_chars // "") | contains($c)) then .cd = true
                      else . end
                  end)
              | del(.cd)
            else .opts = false | (if (.codes | length) == 0 then .script = true else .files += [$a[$i]] end)
            end
        end);

  def finalize:
    (if .name != null and $T.ssh_like[.name] != null then
       $T.ssh_like[.name] as $ss
       | (.args | ssh_parse($ss.arg_letters; $ss.long_arg_opts // [])) as $p
       | .ssh_o = $p.o
       | (if $p.cmd != null and $p.cmd < (.args | length) then .rpayloads += [.args[$p.cmd:] | map(.ph) | join(" ")] else . end)
       | .rpayloads += [$p.o[] | capture("(?i)^\\s*remotecommand\\s*(=|\\s)\\s*(?<c>[\\s\\S]*)$") | .c]
       | (if .name == "mosh" then
            .payloads += [.args as $a | range(0; $a | length) as $i | ($a[$i].s // "") as $t
                          | if ($t | startswith("--ssh=")) then $t[6:] elif $t == "--ssh" then ($a[$i + 1].ph // empty) else empty end]
          else . end)
     elif .name != null and (.name | inlist(["scp", "sftp"])) then
       .ssh_o = [($T.upload_tools[.name].arg_flags // {}) as $uaf | .args | parse_args({arg_flags: $uaf}) | .flags[] | select(.n == "-o") | .v // ""]
     else . end)
    | (if (.shell_like // false) then .
     elif is_shell then
       (.args | shell_scan) as $s
       | (.args | length) as $len
       | if $s.hasc then
           .payloads += [(if $s.first != null and $s.first < $len then .args[$s.first].ph else empty end)]
           | .stdin_prog = false | .script = null
         else
           .stdin_prog = ($s.first == null or $s.first >= $len or $s.sflag or $s.dash)
           | .script = (if $s.first != null and $s.first < $len and ($s.sflag | not) then .args[$s.first] else null end)
         end
     elif is_interp then
       (.args | interp_scan) as $s
       | .stdin_prog = (($s.prog | not) and ($s.first == null or $s.dash))
       | .script = (if ($s.prog | not) and $s.first != null and $s.first < (.args | length) then .args[$s.first] else null end)
     elif .name == "eval" then .payloads += [.args | map(.ph) | join(" ")]
     elif .name == "su" or .name == "runuser" then .payloads += (.args | su_payload)
     elif .name == "rsync" then
       .payloads += [.args | parse_args({arg_flags: $T.upload_tools.rsync.arg_flags}) | .flags[] | select(.n == "-e" or .n == "--rsh") | .v // empty]
     elif .name == "source" or .name == "." then .script = (.args[0] // null)
     else . end)
    | (if is_shell and .stdin_prog then
         .payloads += [.redirs[] | select(.op == "<<" or .op == "<<-") | .hdoc.ph // empty]
         | .payloads += [.redirs[] | select(.op == "<<<") | .w.ph // empty]
       else . end)
    | (if .name != null and (is_shell | not) then
         .name as $n
         | (first($T.interp_families | to_entries[] | select(.value.re as $r | $n | test($r)) | .key) // null) as $fam
         | if $fam == null then .
           else .ifam = $fam
             | (if $fam == "deno" then
                  {codes: (if (.args[0].s // "") == "eval" then [.args[1:][] | select(.s == null or (.s | startswith("-") | not)) | .ph] else [] end),
                   inplace: false, files: []}
                else .args | iscan($T.interp_families[$fam]) end) as $s
             | .icodes = $s.codes
             | .inplace_files = (if $s.inplace then $s.files else [] end)
             | (if .stdin_prog then
                  .icodes += [.redirs[] | select(.op == "<<" or .op == "<<-") | .hdoc.ph // empty]
                  | .icodes += [.redirs[] | select(.op == "<<<") | .w.ph // empty]
                else . end)
           end
       else . end);

  def find_execs:
    .args as $a
    | (reduce range(0; $a | length) as $i ({cur: null, out: []};
        ($a[$i].s) as $t
        | if .cur == null then (if ($t | inlist(["-exec", "-execdir", "-ok", "-okdir"])) then .cur = [] else . end)
          elif $t == ";" or $t == "+" then .out += [.cur] | .cur = null
          else .cur += [if $t == "{}" then unw("find placeholder") else $a[$i] end] end)) as $r
    | $r.out + (if $r.cur != null and ($r.cur | length) > 0 then [$r.cur] else [] end);

  def expand_unit($d):
    unwrap(0)
    | (if .name == "git" then gitnorm else .args = (.words[1:]) end)
    | finalize
    | . as $u
    | [$u] + (if $u.name == "find" and $d < 3 then
               [($u | find_execs)[] as $ws
                | ($u | .words = $ws | .redirs = [] | .assigns = [] | .wrappers = [] | .unsafe = []
                   | .payloads = [] | .via = "find-exec" | .xargs = true | .name = null
                   | .sub = null | .gitc = [] | .git_unsafe = false | .stdin_prog = false | .script = null
                   | .rpayloads = [] | .ssh_o = [] | .icodes = [] | .inplace_files = [] | .ifam = null)
                | expand_unit($d + 1)[]]
             else [] end);

  def build_unit($p):
    ($ast | getpath($p)) as $call
    | (if ($p | last) == "Cmd" then ($ast | getpath($p[:-1])) else {} end) as $stmt
    | {path: $p,
       redirs: (($stmt.Redirs // []) | map(redir_info)),
       words: (($call.Args // []) | map(wres)),
       assigns: (($call.Assigns // []) | map({name: (.Name.Value? // null),
                  v: (if .Value then (.Value | wres) elif .Array then unw("array") else litw("") end)})),
       name: null, trusted: true, wrappers: [], unsafe: [], priv: false, xargs: false, payloads: [],
       sub: null, args: [], gitc: [], git_unsafe: false, via: "call", wstop: false,
       stdin_prog: false, script: null, rpayloads: [], ssh_o: [], icodes: [], inplace_files: [], ifam: null}
    | expand_unit(0)[];

  # ---------- rule predicates ----------
  def with_patterns($e):
    if $e.pattern then
      (($e.pattern.flags // []) + ($e.pattern.file_flags // [])) as $all
      | ($e.pattern.flags // []) as $pf
      | (any(.flags[]; .n as $n | any($all[]; . as $rf | $n | fmatch($rf; true)))) as $hasf
      | .patpos = (if $hasf then -1 else ($e.pattern.pos - 1) end)
      | .patterns = (if $hasf then [.flags[] | select(.n as $n | any($pf[]; . as $rf | $n | fmatch($rf; true))) | .v]
                     else [.pos[$e.pattern.pos - 1].s? // empty] end)
      | .patflags = $pf
    else .patpos = -1 | .patterns = [] | .patflags = [] end;

  def broad($set):
    . as $w
    | if $w.s == null then ($set == "rm")
      else
        (if $w.glob then ($w.s | if contains("/") then (split("/") | .[:-1] | join("/") | if . == "" then "/" else . end) else "." end)
         else $w.s end | canon) as $c
        | if $c == null then ($set == "rm")
          else $c == "/" or $c == $home or ($c | test("^/[^/]+$"))
               or ($set == "rm" and ($c == $cwd or ($cwd | startswith($c + "/")) or ($home | startswith($c + "/"))))
          end
      end;

  def clause($c; $danger; $u):
    . as $pa
    | if $c | has("has") then has_flag($c.has; $danger)
      elif $c | has("no") then has_flag($c.no; true) | not
      elif $c | has("only") then all($pa.flags[]; .n | inlist($c.only))
      elif $c | has("only_re") then ($c.only_re | rx) as $r | all($pa.flags[]; .n | test($r))
      elif $c | has("lead_only") then
        all($pa.flags[] | select(.at < $c.lead_only.before); .n | inlist($c.lead_only.flags // []))
      elif $c | has("pos") then
        ($pa.pos[$c.pos - 1].s? // null) as $v
        | if $c | has("in") then $v != null and ($v | inlist($c.in))
          elif $c | has("not_in") then $v == null or ($v | inlist($c.not_in) | not)
          elif $c | has("in_or_absent") then ($pa.pos | length) < $c.pos or ($v != null and ($v | inlist($c.in_or_absent)))
          elif $c | has("re") then ($c.re | rx) as $r | $v != null and ($v | test($r))
          else false end
      elif $c | has("any_pos_in") then any($pa.pos[]; .s != null and (.s | inlist($c.any_pos_in)))
      elif $c | has("any_pos_re") then ($c.any_pos_re | rx) as $r | any($pa.pos[]; .s != null and (.s | test($r)))
      elif $c | has("all_pos_re") then ($c.all_pos_re | rx) as $r | all($pa.pos[]; .s != null and (.s | test($r)))
      elif $c | has("all_pos_not_re") then ($c.all_pos_not_re | rx) as $r | all($pa.pos[]; .s != null and (.s | test($r) | not))
      elif $c | has("max_pos") then ($pa.pos | length) <= $c.max_pos
      elif $c | has("min_pos") then ($pa.pos | length) >= $c.min_pos
      elif $c | has("any_arg_re") then ($c.any_arg_re | rx) as $r | any($u.args[]; .s != null and (.s | test($r)))
      elif $c | has("flag_value_re") then
        ($c.flag_value_re.re | rx) as $r
        | any($pa.flags[]; .n as $n | .v != null and any($c.flag_value_re.flags[]; . as $rf | $n | fmatch($rf; $danger)) and (.v | test($r)))
      elif $c | has("pattern_re") then ($c.pattern_re | rx) as $r | all($pa.patterns[]; . != null and test($r))
      elif $c | has("pattern_not_re") then ($c.pattern_not_re | rx) as $r | all($pa.patterns[]; . != null and (test($r) | not))
      elif $c | has("broad_target") then ($u.xargs and $c.broad_target.set == "rm") or any($pa.pos[($c.broad_target.from - 1):][]; broad($c.broad_target.set))
      elif $c | has("git_c_re") then ($c.git_c_re | rx) as $r | any($u.gitc[]; test($r))
      elif $c | has("not") then (all($c.not[]; . as $cc | $pa | clause($cc; $danger; $u)) | not)
      else false end;

  # ---------- allow side ----------
  def env_ok:
    all(.assigns[]; .name != null and .v.s != null
        and ((.name | test($T.env_whitelist_re))
             or (.v.s as $vs | ($T.env_whitelist_pairs[.name] // []) | any(.[]; . == $vs))));

  def unit_nonsafe:
    [ (if (.words | length) == 0 then "bare assignment" else empty end),
      (if (.words | length) > 0 and .name == null then "unresolved command name" else empty end),
      (if .trusted | not then "command path outside trusted dirs" else empty end),
      (.unsafe[]),
      (if .priv then "privileged wrapper (sudo/doas)" else empty end),
      (if .xargs then "arguments supplied by xargs/find" else empty end),
      (if any(.words[]; .s == null) then "unresolved argument (" + ([.words[] | select(.s == null) | .why][0] // "?") + ")" else empty end),
      (if env_ok | not then "environment assignment" else empty end),
      (if .git_unsafe then "git global option" else empty end) ];

  def find_leading:
    . as $a
    | (reduce range(0; $a | length) as $i ({skip: 0, done: false, out: []};
        if .done then .
        elif .skip > 0 then .skip -= 1
        else ($a[$i].s) as $t
          | if $t == "-H" or $t == "-L" or $t == "-P" then .
            elif $t == "-D" then .skip = 1
            elif $t != null and ($t | test("^-O[0-9]*$")) then .
            elif $t != null and (($t | startswith("-")) or ($t | inlist(["(", "!", ")", ","]))) then .done = true
            else .out += [$a[$i]] end
        end)) | .out;

  def path_bad($e; $u):
    . as $pa
    | ($u.wd // $cwd) as $wd
    | if ($e.paths // "check") == "none" then false
      elif $e.paths == "find" then any(($u.args | find_leading)[]; w_bad_at($wd))
      else
        any($pa.pos | to_entries[] | select(.key != $pa.patpos) | .value; w_bad_at($wd))
        or any($pa.flags[]; (.n | inlist($pa.patflags) | not) and any((.vw // [])[]; w_bad_at($wd)))
        or any($u.args[]; .s != null and (.s | startswith("-")) and ((.s | split("=")[0]) | inlist($pa.patflags) | not) and (.s | flagtok_bad_at($wd)))
      end;

  def recursive_bad($e; $u):
    . as $pa
    | ($u.wd // $cwd) as $wd
    | if ($e.recursive // "") == "always" or has_flag($e.recursive_flags // []; true)
         or any($pa.flags[]; .n as $n | .v as $v | $v != null and $v != ""
                and any(($e.recursive_values // [])[]; . as $rv | ($n | fmatch($rv.flag; true)) and ($rv.value | startswith($v))))
      then
        ([$pa.pos | to_entries[] | select(.key != $pa.patpos) | .value.s]) as $ps
        | (if ($ps | length) == 0 then [$wd] else $ps end)
        | any(.[]; . == null or (canon_at($wd) | . == null or secret_ancestor))
      else false end;

  def entry_matches($e):
    (.name != null and (.name | inlist($e.cmd)))
    and (if $e.sub then (.sub != null and (.sub | inlist($e.sub))) else true end);

  def entry_ok($e):
    . as $u
    | ($u.args | parse_args($e.args // {}) | with_patterns($e)) as $pa
    | all(($e.when // [])[]; . as $c | $pa | clause($c; false; $u))
      and ($pa | path_bad($e; $u) | not)
      and ($pa | recursive_bad($e; $u) | not);

  # Paths an allowed unit will open, for gate.sh to resolve with realpath (the
  # lexical checks above cannot see symlinks). Same operand selection as
  # path_bad; k = "a" for operands of a recursive reader. Raw absolute paths.
  # A literal /dev/fd/..., /dev/std* or /proc/*/fd/... operand can name a
  # directory opened by a redirect (cat /dev/fd/3/.ssh/config 3<~): k = "x",
  # which never resolves clean. Only a bare process substitution (whose
  # /dev/fd/63 stand-in is not a real path) is skipped.
  def fd_alias: canon | . != null and test("^/dev/(fd(/|$)|std(in|out|err)$)|^/proc/[^/]+/fd(/|$)");
  def cand($k; $wd): select(. != null and . != "") | absforms($wd) | {k: (if fd_alias then "x" else $k end), p: .};
  def allow_cands($e; $u):
    ($u.wdraw // $cwd) as $wd0
    | ($u.args | parse_args($e.args // {}) | with_patterns($e)) as $pa
    | (($e.recursive // "") == "always" or ($pa | has_flag($e.recursive_flags // []; true))
       or any($pa.flags[]; .n as $n | .v as $v | $v != null and $v != ""
              and any(($e.recursive_values // [])[]; . as $rv | ($n | fmatch($rv.flag; true)) and ($rv.value | startswith($v))))) as $rec
    | (if $rec then "a" else "r" end) as $k
    | (if ($e.paths // "check") == "none" then []
       elif $e.paths == "find" then [($u.args | find_leading)[] | select(.psub | not) | .s | cand("r"; $wd0)]
       else
         ([$pa.pos | to_entries[] | select(.key != $pa.patpos) | .value | select(.psub | not) | .s]) as $ps
         | [ ($ps[] | cand($k; $wd0)),
             ($pa.flags[] | select(.n | inlist($pa.patflags) | not) | (.vw // [])[] | select(.psub | not) | .s | cand($k; $wd0)),
             ($u.args[] | select(.psub | not) | .s | select(. != null and startswith("-")) | select((split("=")[0]) | inlist($pa.patflags) | not)
              | ((if contains("=") then .[(index("=") + 1):] else empty end),
                 (if test("[/~]") then .[([indices("/")[], indices("~")[]] | min):] else empty end)) | cand($k; $wd0)) ]
           | . + (if $rec and ($ps | length) == 0 then [{k: "a", p: $wd0}] else [] end)
       end)
      + [$u.redirs[] | select(rclass == "in") | .w | select(.psub | not) | .s | cand("r"; $cwd)]
      + (if $u.name == "git" then [{k: "r", p: $wd0}] else [] end);

  def unit_allow:
    . as $u
    | unit_nonsafe as $ns
    | if ($ns | length) > 0 then {ok: false, why: $ns[0]}
      else ([$A[] | . as $e | select($u | entry_matches($e)) | select($u | entry_ok($e))][0]) as $e
        | if $e != null then
            {ok: true, why: $e.id, cands: allow_cands($e; $u),
             git: (if $u.name == "git" then ($u.wdraw // $cwd) else null end)}
          else {ok: false, why: ("no allow rule matches " + ($u.name // "?") + (if $u.sub then " " + $u.sub else "" end))} end
      end;

  # ---------- danger side ----------
  def danger_hits:
    . as $u
    | $D[] | select(.check == null) | . as $e
    | select(($e.cmd != null and $u.name != null and ($u.name | inlist($e.cmd)))
             or ($e.cmd_re != null and $u.name != null and ($u.name | test($e.cmd_re))))
    | select($e.sub == null or ($u.sub != null and ($u.sub | inlist($e.sub))))
    | select(($u.args | parse_args($e.args // {})) as $pa | all(($e.when // [])[]; . as $c | $pa | clause($c; true; $u)))
    | {id: $e.id, reason: $e.reason, verdict: ($e.verdict // "ask")};

  def under($pre): (.path | length) >= ($pre | length) and .path[:($pre | length)] == $pre;
  def is_net_source: ((.words | length) > 0 and .name == null) or (.name != null and (.name | inlist($T.net_sources)));
  def is_upload_tool: .name != null and ($T.upload_tools[.name] != null);
  def is_env_dump:
    (.name == "env" and (.args | all(.[]; .s != null and (.s | startswith("-")))))
    or (.name == "printenv" and ((.args | length) == 0 or any(.args[]; .s == null or (.s | test($R.secret_env)))))
    or (.name == "set" and (.args | length) == 0);
  def has_secret_arg:
    any(.args[]; .s != null and (((.s | startswith("-")) | not) and (.s | str_secret)
                                 or ((.s | startswith("-")) and ((.s | contains("=")) and (.s[((.s | index("=")) + 1):] | str_secret)))));
  def has_net_subst:
    .node != null
    and any(.node | .. | objects | select(.Type? == "CallExpr") | select((.Args // []) | length > 0);
            ((.Args[0] | wres | normname | .name) as $n0 | $n0 == null or ($n0 | inlist($T.net_sources)))
            or any(.Args[1:][] | wres | .s; . != null and (bname | inlist($T.net_sources))));

  def downloads:
    if .name == "curl" then
      (.args | parse_args({arg_flags: $T.upload_tools.curl.arg_flags})) as $pa
      | [$pa.flags[] | select(.n | inlist(["-o", "--output"])) | .v | select(. != null and . != "-")]
        + (if ($pa | has_flag(["-O", "--remote-name", "--remote-name-all"]; true)) then
             [$pa.pos[] | .s | select(. != null and contains("://")) | split("?")[0] | bname | select(. != "")]
           else [] end)
    elif .name == "wget" then
      (.args | parse_args({arg_flags: $T.upload_tools.wget.arg_flags})) as $pa
      | [$pa.flags[] | select(.n | inlist(["-O", "--output-document"])) | .v | select(. != null and . != "-")] as $o
      | if ($o | length) > 0 then $o
        else [$pa.pos[] | .s | select(. != null and contains("://")) | split("?")[0] | bname | select(. != "")] end
    else [] end
    | . as $d
    | $d;

  def write_targets:
    . as $u
    | if .name == "tee" then [(.args | parse_args({}) | .pos[] | .s)]
      elif .name != null and (.name | inlist(["cp", "mv", "install", "ln"])) then
        (.args | parse_args({arg_flags: {"-t": 1, "--target-directory": 1, "-S": 1, "--suffix": 1, "-m": 1, "--mode": 1, "-o": 1, "--owner": 1, "-g": 1, "--group": 1}})) as $pa
        | ([$pa.flags[] | select(.n == "-t" or .n == "--target-directory") | .v][0]) as $td
        | [$pa.pos[] | .s] as $ps
        | if $td != null then [$td] + [$ps[] | select(. != null) | $td + "/" + bname]
          elif ($ps | length) == 0 then []
          else ($ps | last) as $last | [$last] + (if $last == null then [] else [$ps[:-1][] | select(. != null) | $last + "/" + bname] end) end
      elif .name == "sed" then
        (.args | parse_args({arg_flags: {"-e": 1, "--expression": 1, "-f": 1, "--file": 1, "-l": 1}})) as $pa
        | if ($pa | has_flag(["-i", "--in-place"]; true)) then
            (if ($pa | has_flag(["-e", "--expression", "-f", "--file"]; false)) then $pa.pos else $pa.pos[1:] end) | map(.s)
          else [] end
      elif .name == "dd" then [.args[] | .s | select(. != null and startswith("of=")) | .[3:]]
      elif .name != null and $T.write_verbs[.name] != null then
        $T.write_verbs[.name] as $wv
        | (.args | parse_args({arg_flags: ($wv.arg_flags // {})})) as $pa
        | ([$pa.flags[] | select(.n | inlist($wv.out_flags // [])) | .v]) as $outs
        | ([$pa.flags[] | select(.n | inlist($wv.dir_flags // [])) | .v][0]) as $dir
        | [$pa.pos[] | .s | select(. == null or (startswith("+") | not))] as $ps
        | (if $wv.pos == "first" then $ps[:1] elif $wv.pos == "none" then [] else $ps end) as $tp
        | $outs + [$tp[] | if . != null and $dir != null and (startswith("/") | not) then $dir + "/" + . else . end]
      elif .name == "chattr" then
        .args as $a
        | [range(0; $a | length) as $i | ($a[$i].s) as $t
           | select($i == 0 or (($a[$i - 1].s // "") | test("^-[vp]$") | not))
           | select($t == null or ($t | test("^[-+=][A-Za-z]*$") | not))
           | $t]
      elif .name != null and (.name | inlist(["rsync", "scp", "sftp"])) then
        (($T.upload_tools[.name].arg_flags // {}) as $uaf | .args | parse_args({arg_flags: $uaf})) as $pa
        | [$pa.flags[] | select(.n | inlist(["--log-file", "--write-batch", "--only-write-batch"])) | .v]
          + ([$pa.pos[] | .s] as $ps
             | if ($ps | length) < 2 or ($ps | last) == null or ($ps | last | test("^[^/]*:")) then []
               else ($ps | last) as $last | [$last] + [$ps[:-1][] | select(. != null) | $last + "/" + bname] end)
      else [] end
    + ($u.inplace_files | map(.s))
    + downloads;

  # Remote destinations (scp/rsync/sftp host:path), mapped onto ~/ so the
  # persistence classes (authorized_keys, shell rc, cron, ...) match them.
  # Never resolved with realpath: the path lives on another host.
  def remote_writes:
    if .name != null and (.name | inlist(["rsync", "scp", "sftp"])) then
      (($T.upload_tools[.name].arg_flags // {}) as $uaf | .args | parse_args({arg_flags: $uaf})) as $pa
      | [$pa.pos[] | .s] as $ps
      | ($ps | last) as $last
      | if ($ps | length) < 2 or $last == null or ($last | test("^[^/]*:") | not)
           or ($last | test("^[a-z]+://|^[^/:]*::")) then []
        else ($last[(($last | index(":")) + 1):]) as $p
          | (if $p == "" then "~" elif ($p | startswith("/")) or ($p | startswith("~")) then $p else "~/" + $p end) as $d
          | [$d] + [$ps[:-1][] | select(. != null) | $d + "/" + bname]
        end
    else [] end;

  # ---------- assemble ----------
  ([paths(type == "object" and .Type? == "CallExpr")] ) as $cps
  # Oversize: padding (a long pipeline after the dangerous part) must not push
  # the run past the hook timeout and so lose the ask. Never an allow.
  | if ($cps | length) > $MAX_UNITS then
      render("ASK"; "permission-manager: command too large to analyse (\($cps | length) commands > \($MAX_UNITS)) [oversize]"; [])
    else
    [$cps[] as $p | build_unit($p)] as $units
  # Units by path (several per path for find -exec): O(1) lookups below.
  | (reduce $units[] as $u ({}; .[$u.path | tojson] += [$u])) as $byp
  | def at($p): $byp[$p | tojson][]?;
    [paths(type == "object" and .Type? == "BinaryCmd" and (($OPS[.Op | tostring] // "") | inlist(["|", "|&"])))] as $pipes
  | [.. | objects | select(has("Redirs")) | .Redirs[]? | redir_info] as $allredirs
  | ([.. | objects | .Type? // empty | strings] | unique) as $types

  # structural / redirect non-safety
  | ([ (($types - $T.known_node_types)[] | "unknown shell syntax node " + .),
     ($types[] | select($T.nonsafe_node_types[.] != null) | $T.nonsafe_node_types[.]),
     ([.. | objects | select(has("Cmd")) | select((.Background // false) or (.Coprocess // false))] | if length > 0 then "background job" else empty end),
     ($allredirs[] | rclass as $k
      | if $k == "write" then (if safe_write_target then empty else "output redirection to " + (.w.s // "an unresolved target") end)
        elif $k == "in" then (if .w.s == null or .w.glob then "input redirection from an unresolved or glob path"
                              elif (.w.s | str_bad) then "input redirection from a secret path"
                              elif (.w.s | canon | test("^/dev/(tcp|udp)/")) then "network redirection" else empty end)
        elif $k == "unknown" then "unknown redirection operator " + (.op | tostring)
        else empty end)
    ]) as $struct

  # danger: table rules on every unit
  | [$units[] | danger_hits] as $tablehits

  # danger: builtin shape checks
  | ([$units[] | downloads[] | canon | select(. != null)]
     + [$units[] | select(.name == "curl" or .name == "wget") | .redirs[] | select(rclass == "write") | .w.s | select(. != null) | canon | select(. != null)]) as $downloaded
  | ([$allredirs[] | select(rclass == "write") | .w.s | select(. != null)]
     + [$units[] | write_targets[] | select(. != null)]) as $lwrites
  | ($lwrites + [$units[] | remote_writes[] | select(. != null)]) as $writes
  | ($D | map(select(.check != null)) | map({key: .check, value: .}) | from_entries) as $checks
  | def hit($k): {id: $checks[$k].id, reason: $checks[$k].reason, verdict: ($checks[$k].verdict // "ask")};
    # Literal program text on the left of a pipe (echo/printf args, cat heredoc).
    def piped_text($b):
      ($ast | getpath($b + ["X"])) as $xs
      | select($xs.Cmd.Type? == "CallExpr")
      | at($b + ["X", "Cmd"]) | select(.via == "call")
      | if .name == "echo" or .name == "printf" then (.args | map(.ph) | join(" "))
        elif .name == "cat" and (.args | length) == 0 then (.redirs[] | if .op == "<<<" then .w.ph elif (.op == "<<" or .op == "<<-") then .hdoc.ph else empty end)
        else empty end;
    ([$pipes[] as $b
      | [at($b + ["Y", "Cmd"]) | select(.ifam != null and .stdin_prog)] as $ip
      | select(($ip | length) > 0)
      | {path: $ip[0].path, t: piped_text($b)}]) as $piped_code
  # Only the few units with a pipe-relevant property are tested against each
  # pipe side (not every unit against every pipe, which is quadratic).
  | [$units[] | select(is_interp and .stdin_prog)] as $u_istdin
  | [$units[] | select(is_net_source)] as $u_net
  | [$units[] | select(is_upload_tool)] as $u_up
  | [$units[] | select(has_secret_arg or is_env_dump)] as $u_sec
  | [
      # pipe-to-interpreter and secret pipe upload
      (if ($u_istdin | length) > 0 and ($u_net | length) > 0 or ($u_up | length) > 0 then
       $pipes[] as $b
       | (if any($u_istdin[]; under($b + ["Y"])) and any($u_net[]; under($b + ["X"])) then hit("pipe_interpreter") else empty end),
         (if any($u_up[]; under($b + ["Y"]))
             and (any($u_sec[]; under($b + ["X"]))
                  or any($ast | getpath($b + ["X"]) | .. | objects | select(has("Redirs")) | .Redirs[]? | redir_info;
                         rclass == "in" and .w.s != null and (.w.s | str_secret)))
          then hit("secret_pipe_upload") else empty end)
       else empty end),
      # program text from a network substitution
      ($units[] | select(is_interp or (.name != null and (.name | inlist($T.program_consumers))) or (.name == null and (.words | length) > 0))
       | select(any(.words[]; has_net_subst) or any(.redirs[] | (.w // empty), (.hdoc // empty); has_net_subst))
       | hit("subst_interpreter")),
      # download then execute
      (if ($downloaded | length) > 0 then
         $units[]
         | select(
             ((is_interp or (.name != null and (.name | inlist($T.program_consumers))))
              and any(.args[]; .s != null and ((.s | canon) as $c | $c != null and ($c | inlist($downloaded)))))
             or (.words[0].s? != null and (.words[0].s | contains("/")) and ((.words[0].s | canon) | inlist($downloaded)))
             or (is_interp and any(.redirs[]; rclass == "in" and .w.s != null and ((.w.s | canon) | inlist($downloaded)))))
         | hit("download_exec")
       else empty end),
      # secret upload by argument or input redirect
      ($units[] | select(is_upload_tool) | . as $u | $T.upload_tools[$u.name] as $spec
       | select(
           any($u.redirs[]; rclass == "in" and .w.s != null and (.w.s | str_secret))
           or ($spec.mode == "at" and (
                 any($u.args[] | .s | select(. != null)
                     | (capture("^@(?<p>.+)$"), capture("^-[A-Za-z]+@(?<p>.+)$"), capture("^[^@<]*=[@<](?<p>.+)$"), capture("^[A-Za-z0-9_.-]+@(?<p>[^@]+)$")) | .p;
                     str_secret)
                 or (($u.args | parse_args({arg_flags: ($spec.arg_flags // {})})) as $pa
                     | any($pa.flags[]; (.n | inlist($spec.upload_flags // [])) and .v != null and (.v | str_secret)))))
           or ($spec.mode == "positional" and (
                 ($u.args | parse_args({arg_flags: ($spec.arg_flags // {})})) as $pa
                 | any($pa.pos[]; .s != null and ((.s | test("^[^/]*:")) | not) and (.s | str_secret))))
           or ($spec.mode == "socat" and any($u.args[] | .s | select(. != null) | sub("^[A-Za-z0-9_-]+:"; "") | split(",")[0]; str_secret)))
       | hit("secret_upload")),
      # ssh/scp/sftp options that run a command on THIS host
      ($units[] | select(any(.ssh_o[]; test($R.ssh_local_exec))) | hit("ssh_local_exec")),
      # inline interpreter code (coarse keyword heuristic; ASK only)
      ($units[] | select(.ifam != null) | . as $u
       | ($u.icodes + [$piped_code[] | select(.path == $u.path) | .t]) as $codes
       | if any($codes[]; test($R.interp_exec)) then hit("interp_inline")
         elif ($u.ifam | inlist(["perl", "ruby", "php"])) and any($codes[]; test($R.interp_exec_backtick)) then hit("interp_inline")
         elif any($codes[]; test($R.interp_write) and test($R.interp_persist_hint)) then hit("interp_inline_persist")
         else empty end),
      # persistence writes and device redirects
      (if any($writes[]; canon | . != null and is_persist) then hit("persist_write") else empty end),
      (if any($writes[]; canon | . != null and is_registry) then hit("registry_write") else empty end),
      (if any($writes[]; (canon) as $c | $c != null and ($c | is_device)) then hit("redirect_device") else empty end),
      (if any($writes[]; (canon) as $c | $c != null and ($c | is_kernel_trigger)) then hit("kernel_trigger") else empty end)
    ] as $shapehits

  | ($tablehits + $shapehits | unique_by(.id)) as $hits
  | [$units[] | unit_allow] as $verdicts
  | ([$units[] | .payloads[]]
     + [$pipes[] as $b
        | select(any(at($b + ["Y", "Cmd"]); is_shell and .stdin_prog))
        | piped_text($b)]
    | map(select(. != null and . != "")) | unique) as $payloads
  | ([$units[] | .rpayloads[]] | map(select(. != null and . != "")) | unique) as $rpayloads

  | (if any($hits[]; .verdict == "deny") then "DENY"
     elif ($hits | length) > 0 then "ASK"
     elif ($units | length) == 0 then "PASS"
     elif ($struct | length) > 0 or any($verdicts[]; .ok | not) then "PASS"
     else "ALLOW" end) as $verdict
  | (if $depth != "0" then "nested payload: " else "" end) as $pre
  | (if $verdict == "ASK" or $verdict == "DENY" then
       "permission-manager: " + $pre + ([$hits[] | select(($verdict == "DENY") == (.verdict == "deny"))][0].reason)
       + " [" + ([$hits[].id] | join(", ")) + "]"
     elif $verdict == "ALLOW" then "permission-manager: read-only [" + ([$verdicts[].why] | unique | join(", ")) + "]"
     elif ($units | length) == 0 then "no commands"
     else ($struct + [$verdicts[] | select(.ok | not) | .why])[0] end) as $reason
  # Tagged extras for gate.sh: p/s = local/remote program text to re-parse;
  # r/a = paths an ALLOW must resolve clean; g = git dir whose repo config must
  # be clean; w = local write targets of a PASS to resolve for persistence.
  | ([$payloads[] | "p\t" + .] + [$rpayloads[] | "s\t" + .]
     + (if $verdict == "ALLOW" then
          # Input redirects on blocks/loops/subshells belong to no unit: take
          # every one in the tree.
          ([($verdicts[] | .cands[]? | .k + "\t" + .p),
            ($allredirs[] | select(rclass == "in") | .w | select(.psub | not) | .s | select(. != null) | absforms($cwd)
             | (if fd_alias then "x" else "r" end) + "\t" + .)] | unique)
          + ([$verdicts[] | .git | select(. != null) | "g\t" + .] | unique)
        elif $verdict == "PASS" then
          [$lwrites[] | absforms($cwd)
           | select(canon as $c | $c != null and ($c | inlist($P.safe_write_targets) | not))
           | "w\t" + .] | unique
        else [] end)) as $extra
  | render($verdict; $reason; $extra)
    end
