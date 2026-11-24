# merge.jq — merge the shipped rule tables with the user's layer files.
#
# Input (slurped): an array of {layer, path, doc} (or {layer, path, bad: true}
# for a file that is not valid JSON), in load order: system, user, project.
# Globals: --slurpfile paths/danger/tools/allow/regex, the shipped tables.
#
# Output: {rules: {danger, allow, regex, tools, paths}, errors: [{path, msg}]}
#
# A file that fails validate.jq is skipped by itself. Ids that an override or
# disable names but that do not exist are warnings. Overrides keep the entry's
# position (allow is first-match, so order is meaning).

include "validate";

def apply($doc):
  . as $r
  | ($doc.override // {}) as $ov
  | ($doc.disable // []) as $off
  | def patch: if type == "object" and (.id | type) == "string" and (. as $e | $ov | has($e.id)) then . + $ov[.id] else . end;
    def keep: ((.id | type) != "string") or ((.id | IN($off[])) | not);
  .danger |= [.[] | patch | select(keep)]
  | .allow |= [.[] | patch | select(keep)]
  | .danger += ($doc.danger // [])
  | .allow += ($doc.allow // [])
  | .regex += ($doc.regex // {})
  | .tools.arg_specs += (($doc.tools // {}).arg_specs // {});

. as $files
| {danger: $danger[0], allow: $allow[0], regex: $regex[0], tools: $tools[0], paths: $paths[0]} as $base
| reduce $files[] as $f ({rules: $base, errors: []};
    if $f.bad then .errors += [{path: $f.path, msg: "not valid JSON"}]
    else
      file_errs($f.layer; .rules; $f.doc) as $e
      | if ($e.fatal | length) > 0 then .errors += [$e.fatal[] | {path: $f.path, msg: .}]
        else
          .rules |= apply($f.doc)
          | .errors += [$e.warn[] | {path: $f.path, msg: .}]
        end
    end)
