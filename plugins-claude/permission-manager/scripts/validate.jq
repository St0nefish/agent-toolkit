# validate.jq — validation of one user rule-layer file (see merge.jq).
#
# `engine.jq`'s clause() ends in `else false end`, so a misspelled clause key
# makes a danger rule silently never fire. Every layer file is therefore
# checked here before it can reach the engine.
#
# file_errs($layer; $rules; $doc) returns {fatal: [msg], warn: [msg]}:
#   fatal  the file is skipped as a whole
#   warn   the entry is ignored, the rest of the file applies
# $layer is "system", "user" or "project"; $rules is the merged table so far
# ({danger, allow, regex, tools, paths}); $doc is the parsed file.

def clause_keys: [
  "has", "no", "only", "only_re", "lead_only", "pos", "any_pos_in", "any_pos_re",
  "all_pos_re", "all_pos_not_re", "max_pos", "min_pos", "any_arg_re",
  "flag_value_re", "pattern_re", "pattern_not_re", "broad_target", "git_c_re",
  "not", "push_target_re", "flag_with_pos"
];
def pos_subs: ["in", "not_in", "in_or_absent", "re"];
def id_re: "^[a-z0-9][a-z0-9_-]*\\.[A-Za-z0-9_.-]+$";

# A regex value: "@name" must resolve in $rx, anything else must compile.
def regex_errs($rx; $where):
  . as $re
  | if type != "string" then ["\($where): regex must be a string"]
    elif startswith("@") then
      (if ($rx | has($re[1:])) then [] else ["\($where): unknown regex reference \($re)"] end)
    else [try ("" | test($re) | empty) catch "\($where): invalid regex"] end;

def list_errs($where): if type == "array" then [] else ["\($where): must be an array"] end;

def clause_errs($rx):
  if type != "object" then ["when clause must be an object"]
  else
    . as $c
    | (keys - pos_subs) as $p
    | if ($p | length) != 1 then ["when clause needs exactly one clause key, got \($c | keys)"]
      elif ($p[0] | IN(clause_keys[])) | not then ["unknown when clause key \"\($p[0])\""]
      else
        $p[0] as $k
        | $c[$k] as $v
        | if $k == "not" then
            # push_target_re under not would turn "unresolved target holds" into "never fires".
            ($v | if type == "array" then
                (if any(.[]; type == "object" and has("push_target_re")) then ["push_target_re cannot be used under not"] else [] end)
                + ([.[] | clause_errs($rx)] | add // [])
              else ["not: must be an array"] end)
          elif $k == "pos" then
            ([$c | keys[] | select(IN(pos_subs[]))]) as $s
            | if ($v | type) != "number" or $v < 1 then ["pos must be a number >= 1"]
              elif ($s | length) != 1 then ["pos clause needs exactly one of \(pos_subs)"]
              elif $s[0] == "re" then ($c.re | regex_errs($rx; "pos.re"))
              else ($c[$s[0]] | list_errs("pos." + $s[0])) end
          elif $k | IN("only_re", "any_pos_re", "all_pos_re", "all_pos_not_re", "any_arg_re", "pattern_re", "pattern_not_re", "git_c_re", "push_target_re") then
            ($v | regex_errs($rx; $k))
          elif $k == "flag_value_re" then
            (if ($v | type) == "object" then (($v.flags | list_errs("flag_value_re.flags")) + ($v.re | regex_errs($rx; "flag_value_re.re"))) else ["flag_value_re: must be an object"] end)
          elif $k == "flag_with_pos" then
            (if ($v | type) == "object" then (($v.flags | list_errs("flag_with_pos.flags")) + ($v.pos_re | regex_errs($rx; "flag_with_pos.pos_re"))) else ["flag_with_pos: must be an object"] end)
          elif $k | IN("has", "no", "only", "any_pos_in") then ($v | list_errs($k))
          elif $k | IN("max_pos", "min_pos") then (if ($v | type) == "number" then [] else ["\($k): must be a number"] end)
          elif $k == "lead_only" then
            (if ($v | type) == "object" and ($v.before | type) == "number" then ($v.flags // [] | list_errs("lead_only.flags")) else ["lead_only: needs {before: number, flags: [...]}"] end)
          else # broad_target
            (if ($v | type) == "object" and ($v.from | type) == "number" and ($v.set | IN("rm", "system")) then [] else ["broad_target: needs {set: rm|system, from: number}"] end)
          end
      end
  end;

def when_errs($rx):
  if . == null then []
  elif type != "array" then ["when: must be an array"]
  else [.[] | clause_errs($rx)] | add // [] end;

def str_list: type == "array" and all(.[]; type == "string");

def args_errs($specs; $who):
  . as $a
  | if type == "string" then
    (if ($a | startswith("@")) and ($specs | has($a[1:])) then [] else ["\($who): unknown args reference \($a)"] end)
  elif type == "object" then
    (if (.arg_flags // {}) | type == "object" and all(.[]; type == "number") then [] else ["\($who): args.arg_flags must map flags to numbers"] end)
  else ["\($who): args must be an object or an \"@name\" reference"] end;

# Every field the engine dereferences: a value of the wrong shape makes jq
# throw inside engine.jq, which silences the whole gate (all asks lost), so
# each is checked here. Applies to added entries and to override values.
def field_errs($kind; $rx; $specs; $who):
  . as $e
  | (if has("cmd") then (if ($e.cmd | str_list) then [] else ["\($who): cmd must be an array of strings"] end) else [] end)
  + (if has("cmd_re") then ($e.cmd_re | regex_errs($rx; "\($who).cmd_re")) else [] end)
  + (if has("sub") then (if ($e.sub | str_list) then [] else ["\($who): sub must be an array of strings"] end) else [] end)
  + (if has("args") then ($e.args | args_errs($specs; $who)) else [] end)
  + (if has("verdict") and (($e.verdict | IN("ask", "deny")) | not) then ["\($who): verdict must be ask or deny"] else [] end)
  + (if has("reason") and ($e.reason | type) != "string" then ["\($who): reason must be a string"] else [] end)
  + (if has("paths") and (($e.paths | IN("check", "none", "find")) | not) then ["\($who): paths must be check, none or find"] else [] end)
  + (if has("pattern") then (if ($e.pattern | type) == "object" and ($e.pattern.pos | type) == "number" then [] else ["\($who): pattern needs {pos: number}"] end) else [] end)
  + (if $kind == "allow" and (($e.when // []) | tostring | contains("\"push_target_re\"")) then ["\($who): push_target_re is for danger rules only"] else [] end)
  + ($e.when | when_errs($rx));

def entry_errs($kind; $taken; $rx; $specs):
  . as $e
  | if type != "object" then ["\($kind) entry must be an object"]
    else
      (if ($e.id | type) != "string" then ["\($kind) entry needs a string id"]
       elif ($e.id | test(id_re)) | not then ["id \"\($e.id)\" must look like owner.name"]
       elif ($taken | index($e.id)) != null then ["duplicate id \"\($e.id)\""]
       else [] end)
      + (if $kind == "danger" then
           (if ($e.cmd | str_list) or ($e.cmd_re | type) == "string" then [] else ["\($e.id // "?"): needs cmd (array) or cmd_re"] end)
           + (if $e | has("check") then ["\($e.id // "?"): check is reserved for shipped rules"] else [] end)
           + (if ($e.reason | type) == "string" then [] else ["\($e.id // "?"): needs a reason"] end)
         else
           (if ($e.cmd | str_list) and ($e.cmd | length) > 0 then [] else ["\($e.id // "?"): needs a cmd array"] end)
         end)
      + ($e | field_errs($kind; $rx; $specs; $e.id // "?"))
    end;

def entries_errs($kind; $taken; $rx; $specs):
  if type != "array" then ["\($kind): must be an array"]
  else
    reduce .[] as $e ({taken: $taken, errs: []};
      ($e | entry_errs($kind; .taken; $rx; $specs)) as $x
      | .errs += $x
      | .taken += (if ($e | type) == "object" and ($e.id | type) == "string" then [$e.id] else [] end))
    | .errs
  end;

def file_errs($layer; $rules; $doc):
  ($rules.regex) as $rx0
  | (["version", "danger", "regex"]
     + (if $layer == "project" then [] else ["allow", "tools", "override", "disable"] end)) as $allowed
  | if ($doc | type) != "object" then {fatal: ["top level must be an object"], warn: []}
    else
      ([$doc | keys[] | select(IN($allowed[]) | not) | "section \"\(.)\" is not allowed in the \($layer) layer"]
       + (if $doc.version == 1 then [] else ["version must be 1"] end)) as $shape
      | ((($doc.regex // {}) | if type == "object" then
            ([to_entries[] | select((.key | test("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_.-]+$") | not) or (.key as $k | $rx0 | has($k)))
              | "regex name \"\(.key)\" must be new and look like owner.name"]
             + [to_entries[] | .value | regex_errs({}; "regex")[]])
          else ["regex: must be an object"] end)
         + (($doc.tools // {}) | if type == "object" then
              ([keys[] | select(. != "arg_specs") | "tools.\(.) cannot be extended"]
               + ((.arg_specs // {}) | [to_entries[] | select((.key | test("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_.-]+$") | not) or (.key as $k | ($rules.tools.arg_specs // {}) | has($k))) | "tools.arg_specs name \"\(.key)\" must be new and look like owner.name"]))
            else ["tools: must be an object"] end)) as $tables
      | ($rx0 + (if ($doc.regex | type) == "object" then $doc.regex else {} end)) as $rx
      | ([$rules.danger[]?.id, $rules.allow[]?.id] | map(select(. != null))) as $ids
      | (($rules.tools.arg_specs // {}) + (if ($doc.tools | type) == "object" and ($doc.tools.arg_specs | type) == "object" then $doc.tools.arg_specs else {} end)) as $specs
      | ([$rules.allow[]? | .id | strings]) as $allow_ids
      | (($doc.danger // []) | entries_errs("danger"; $ids; $rx; $specs)) as $de
      | (($doc.allow // []) | entries_errs("allow"; $ids + [($doc.danger // [])[]? | .id?]; $rx; $specs)) as $ae
      | (if $doc | has("override") then
           ($doc.override | if type == "object" then
              [to_entries[] | .key as $id | .value as $o
               | if ($o | type) != "object" then "override.\($id): must be an object"
                 elif ($o | (has("id") or has("check"))) then "override.\($id): id and check cannot be overridden"
                 else ($o | field_errs(if ($allow_ids | index($id)) != null then "allow" else "danger" end; $rx; $specs; "override." + $id))[] end]
            else ["override: must be an object"] end)
         else [] end) as $oe
      | (if ($doc | has("disable")) and (($doc.disable | type) != "array" or any($doc.disable[]; type != "string")) then ["disable: must be an array of ids"] else [] end) as $ds
      | {fatal: ($shape + $tables + $de + $ae + $oe + $ds),
         warn: ([($doc.override // {}) | if type == "object" then keys[] else empty end, (($doc.disable // []) | if type == "array" then .[] else empty end)]
                | map(select(type == "string" and (. as $id | ($ids | index($id)) == null)) | "unknown id \"\(.)\" in override/disable ignored"))}
    end;
