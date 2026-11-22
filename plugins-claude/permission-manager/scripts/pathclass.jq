# pathclass.jq — lexical path classes and engine output, shared by engine.jq
# (main classifier) and check.jq (classifier of realpath-resolved paths).
#
# Reads the globals both callers pass: --arg cmd/cwd/home/rhome and
# --slurpfile paths/danger. Functions that need the compiled path classes take
# them as $P (built once per run by pc_paths).

def escre: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/])"; "\\\(.c)");
def homeify($h): map(if startswith("^~/") then "^" + ($h | escre) + .[2:] else . end);

# rules/paths.json with ~/ expanded to the hook's $HOME.
def pc_paths:
  $paths[0]
  | .secret_path_re += [.secret_prefixes[] | select(startswith("~/")) | "^/(root|home/[^/]+|Users/[^/]+)/" + (.[2:] | escre) + (if endswith("_") then "" else "(/|$)" end)]
  | .secret_prefixes |= map(if startswith("~/") then $home + .[1:] else . end)
  | .persist_path_re |= homeify($home)
  | .registry_path_re |= homeify($home);

def bname: split("/") | last // "";
def dname: (split("/") | .[:-1] | join("/")) | if . == "" then "/" else . end;
# Lexical canonicalisation: ~, .., . and // resolved without touching the
# filesystem; null for ~user and other unresolvable forms.
def canon_at($base):
  if . == null then null
  else (if test("^~(/|$)") then $home + .[1:] elif startswith("~") then null else . end)
    | if . == null then null
      else (if startswith("/") then . else $base + "/" + . end)
        | reduce (split("/")[]) as $c ([];
            if $c == "" or $c == "." then . elif $c == ".." then .[:-1] else . + [$c] end)
        | "/" + join("/")
      end
  end;
def canon: canon_at($cwd);
# Absolute but NOT normalised (for realpath, which must see `..` after symlinks).
def rawabs($base):
  if . == null then null
  elif test("^~(/|$)") then $home + .[1:]
  elif startswith("~") then null
  elif startswith("/") then .
  else $base + "/" + . end;
# Every absolute reading of a literal path word for realpath. A leading ~ that
# survived word resolution was quoted or follows "=", so bash passed it
# literally (a relative path); resolve both that and the $HOME reading.
def absforms($base):
  if startswith("~") then ((rawabs($base) // empty), ($base + "/" + .))
  elif startswith("/") then .
  else $base + "/" + . end;

def pc_is_secret($P):
  . as $c | ($c | bname) as $b
  | ($b | test($P.secret_exempt_basename_re)) as $ex
  | ((($ex | not) and any($P.secret_prefixes[]; . as $s | $c == $s or ($c | startswith($s + "/")) or (($s | endswith("_")) and ($c | startswith($s)))))
     or any($P.secret_path_re[]; . as $r | $c | test($r))
     or (($ex | not) and any($P.secret_basename_re[]; . as $r | $b | test($r))));
def pc_secret_ancestor($P): . as $c | $c == "/" or ($c | test("^/(root|home|Users)(/[^/]+)?$")) or any($P.secret_prefixes[]; startswith($c + "/"));
def pc_is_persist($P): . as $c | any($P.persist_path_re[]; . as $r | $c | test($r)) or ($c | bname | test($P.persist_basename_re));
def pc_is_registry($P): . as $c | any($P.registry_path_re[]; . as $r | $c | test($r)) or ($c | bname | test($P.registry_basename_re));
def pc_is_device($P): test($P.device_re);
def pc_is_kernel_trigger($P): test($P.kernel_trigger_re);

def dhit($id): ($danger[0][] | select(.id == $id)) as $e | {id: $e.id, reason: $e.reason, verdict: ($e.verdict // "ask")};

# Engine output protocol (NUL-terminated items): verdict, reason, hook JSON
# ("" unless ASK/DENY/ALLOW), audit JSON (same), tagged extras, "END".
def render($verdict; $reason; $extra):
  ($reason | gsub("[\\r\\n]+"; " ")) as $r
  | ($verdict, $r,
     (if $verdict == "PASS" or $verdict == "OK" then ""
      else {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: ($verdict | ascii_downcase),
                                 permissionDecisionReason: $r}} | tojson end),
     (if $verdict == "PASS" or $verdict == "OK" then ""
      else {ts: (now | todate), decision: ($verdict | ascii_downcase), reason: $r,
            command: ($cmd | .[:200]), cwd: $cwd} | tojson end),
     $extra[], "END")
  | . + "\u0000";
