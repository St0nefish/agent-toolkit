# check.jq — classify realpath-resolved paths for gate.sh (run with jq -n).
#
# Positional args ($ARGS.positional) are "K<TAB>resolved", K = r (operand of
# an allowed unit), a (directory operand of a recursive reader) or w (write
# target of a passthrough). $rhome is the resolved $HOME, so a symlinked home
# still matches the ~/ path classes; $rcwd and $rtmp are the resolved cwd and
# /tmp, the only places a recursive reader may start. Output: render() with OK (clean), PASS (an allow must not
# stand) or ASK (a write target resolves to a persistence/registry/device path).
include "pathclass";

pc_paths as $P
| def unhome: if $rhome != "" and $rhome != $home and (. == $rhome or startswith($rhome + "/")) then $home + .[($rhome | length):] else . end;
  [$ARGS.positional[] | (index("\t")) as $k | {k: .[:$k], p: .[($k + 1):]} | .q = (.p | unhome)] as $items
| ([$items[] | select(.k == "w") | .p, .q] | unique) as $ws
| ([ (if any($ws[]; pc_is_persist($P)) then dhit("persist-write") else empty end),
     (if any($ws[]; pc_is_registry($P)) then dhit("pkg-registry-config-write") else empty end),
     (if any($ws[]; pc_is_device($P)) then dhit("fs-redirect-device") else empty end),
     (if any($ws[]; pc_is_kernel_trigger($P)) then dhit("sys-kernel-trigger") else empty end) ]) as $hits
  # A recursive reader would open every file below its operand (.env files
  # included), so it is allowed only inside the working directory or /tmp.
| def within($d): $d != "" and (. == $d or startswith(($d | rtrimstr("/")) + "/"));
  ([$items[] | select(.k == "a") | select((.p | within($rcwd) or within($rtmp)) | not) | .p][0]) as $wide
| ([$items[] | select(.k == "r" or .k == "a" or .k == "x")
    | select(.k == "x" or (.p | pc_is_secret($P)) or (.q | pc_is_secret($P))
             or (.k == "a" and ((.p | pc_secret_ancestor($P)) or (.q | pc_secret_ancestor($P)))))
    | .p][0]) as $bad
| if ($hits | length) > 0 then
    render("ASK"; "permission-manager: " + $hits[0].reason + " (after resolving symlinks) [" + ([$hits[].id] | join(", ")) + "]"; [])
  elif $bad != null then render("PASS"; "resolved path is secret: " + $bad; [])
  elif $wide != null then render("PASS"; "recursive read outside the working directory and /tmp: " + $wide; [])
  else render("OK"; "resolved paths clean"; []) end
