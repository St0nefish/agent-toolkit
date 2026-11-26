# permission-manager

A deterministic `PreToolUse` hook for the Bash tool. It decides the cases it can
prove before Claude Code's normal permission flow (including the auto-mode
classifier) and stays silent for everything else.

| Outcome | When | Hook output |
|---|---|---|
| allow | every executed command is provably read-only | `permissionDecision: "allow"` |
| ask | any command matches a danger rule, the command is too large to analyse (`oversize`), or the jq engine failed (`engine-error`) | `permissionDecision: "ask"` with the reason |
| passthrough | anything else, including a missing dependency or a command shfmt cannot parse | nothing on stdout, exit 0 |

Precedence over all commands in one Bash call: any danger hit asks; otherwise any
command that is not provably safe, or any syntax the engine cannot resolve, passes
through; otherwise the call is allowed. A wrong allow is a bypass and a wrong
passthrough is only slower, so every uncertainty passes through. The hook never
exits non-zero and never prints partial JSON. In `bypassPermissions` mode it
prints nothing.

## Requirements

- `bash` 4.4+, `jq` 1.6+, `shfmt` 3.x (the operator encoding change in shfmt 3.14
  is handled; see below).
- GNU `realpath` (coreutils, for `-m -z`) and `git`. Without them the hook still
  runs, but an allow that needs them (a path operand, a git command) passes
  through instead.
- `timeout` and `head` (coreutils) bound the parse; without them an oversize
  command can still run into the hook timeout (see "Oversize commands ask").
- If `jq` or `shfmt` is missing, every call passes through and one note is written
  to stderr per session.

## How it works

`scripts/gate.sh` reads the hook payload with one `jq` call, then parses the
command with one `shfmt --tojson` run and classifies it with one `jq` run of
`scripts/engine.jq` over the rule tables in `scripts/rules/`. The lexical path
classes and the output protocol live in the `scripts/pathclass.jq` module,
shared with `scripts/check.jq` (see "Symlinks" below).

- **Full recursive descent.** Every `CallExpr` anywhere in the AST becomes a unit:
  pipelines, `&&`/`||`/`;` lists, subshells, blocks, `if`/`while`/`for`/`case`,
  function bodies, `time`, `coproc`, and command/process substitutions and
  backticks inside any word, redirect target, assignment or heredoc body.
- **Words** are resolved to literals (quotes and backslashes removed, `~` and
  `$HOME` expanded) or marked unresolved with a reason (variable, command
  substitution, extended glob, ...). An unresolved command name
  or argument is never allowed, and a glob in a path operand or input redirect
  is never allowed (a wildcard such as `*_rsa` or `/etc/shado?` can match a
  secret that a lexical check cannot rule out).
- **ANSI-C quotes** (`$'...'`) are decoded exactly as bash does: `\xHH`,
  `\NNN` (octal), `\uHHHH`, `\UHHHHHHHH`, `\a \b \e \E \f \n \r \t \v \\ \' \" \?`
  and `\cX`; the value ends at the first NUL, and any other escape (`\q`, `\x`
  with no digits) stays literally as backslash plus character, as in bash. So
  `$'\x67it' push -f` is `git push -f` to every rule. `\c` before a backslash
  or the end, or a decoded byte/code point outside ASCII (its rendering
  depends on the locale), leaves the word unresolved. `$"..."` locale quotes
  are plain double-quoted words.
- **Brace expansion.** A word of several parts with an unquoted `{` (as in
  `{a,~/.ssh/con'f'ig}`) may expand across its quoted parts and is unresolved.
- **Wrappers** (`sudo`, `doas`, `env`, `command`, `builtin`, `exec`, `nice`,
  `ionice`, `timeout`, `time`, `nohup`, `stdbuf`, `setsid`, `xargs`, `watch`,
  `busybox`, `sshpass`, `nsenter`, `chroot`, `runuser -u`) are stripped and the
  inner command is classified. Only `env` (without
  `-C`/`--chdir`/`-P`), `command`, `builtin`, `exec`, `nice`, `ionice`, `timeout`, `time` (without
  `-o`), `stdbuf` and `setsid` are transparent for allow; the others make the
  unit non-safe while danger rules still apply to the inner command. `nsenter`
  and `chroot` with no command run an interactive shell, so they count as a
  shell reading stdin (`curl ... | chroot /mnt` asks).
- **Container and cluster exec.** `docker`/`podman exec`, `docker container
  exec`, `docker compose exec`, `docker-compose exec`, `kubectl`/`oc exec`,
  `incus`/`lxc exec` (inner argv after the container/pod, after `--` when
  given) are wrappers too: the inner argv is classified like any command, at
  any depth, and is never allowed.
- **Payloads.** The program text given to `sh|bash|zsh|... -c`, `eval`, `su -c`,
  `runuser -c`, `watch`, `env -S`, `rsync -e`, `mosh --ssh`, or a literal
  heredoc/here-string/`echo` piped into a shell is re-parsed (up to depth 4,
  at most 16 payloads) for danger rules only; such a unit is never allowed.
- **ssh.** For `ssh [opts] host CMD...` (also `autossh`, `mosh`, and `sshpass`
  in front of them) the remote command words are joined with spaces, as ssh
  does, and re-parsed as shell text like a `bash -c` payload, so `ssh h "bash
  -c 'git push -f'"` asks while `ssh h bash -c 'git push -f'` (the remote runs
  `bash -c git`) does not. Options are re-scanned after the host, as OpenSSH
  does; `-o RemoteCommand=...` is re-parsed the same way. `ssh` is never
  allowed. An unresolved remote command passes through
  (danger rules still see its literal parts). `-o ProxyCommand=`,
  `LocalCommand=`, `KnownHostsCommand=` (not `none`) and
  `PermitLocalCommand=yes` on `ssh`/`autossh`/`scp`/`sftp` run a command on
  this host and ask (`ssh-local-command`). Write targets inside a remote
  payload are not resolved against the local filesystem.
- **git** is normalised as `git [-C d] [-c k=v] [--git-dir=..]... SUBCMD args`.
  `-C` dirs become the base for relative path checks; `-c`, `--config-env`,
  `--exec-path`, `--git-dir`, `--work-tree`, `--bare` (which reads `./config`
  instead of `.git/config`), `-p`, a `-C` starting with a quoted `~`, and
  unknown global options make it non-safe; `-c`/`--config-env` with an alias
  or command-executing key asks.
- **Paths** are canonicalised lexically (`..`, `.`, `//`, `~`, `$HOME`) for every
  rule. An unresolvable path is never treated as safe.
- **Symlinks.** Lexical checks cannot see a symlink such as `./notes ->
  ~/.ssh/id_rsa`, so before printing an allow, `gate.sh` resolves every literal
  path operand and input-redirect target of the allowed units (the same
  operands the secret-path check reads, input redirects on blocks and loops,
  and the directory of every git unit) with one batched `realpath -m -z --`
  call, plus `$HOME`. Relative operands of `git -C d` are joined to the raw
  `-C` path so `link/..` resolves physically, as git's chdir does; a quoted
  leading `~` is resolved both as `$HOME` and as a literal `./~` directory.
  `check.jq` then tests the results against the secret classes (and, for
  recursive readers, against ancestors of secret directories); any hit, a
  realpath failure, more than 128 paths or 32 KB of paths passes through. An
  operand of a recursive reader (`grep -r`, `rg`) that resolves to a directory
  must also lie inside the hook's working directory or `/tmp` (both resolved):
  `grep -r PASSWORD /npool/docker/data` would print every `.env` below it, so
  it passes through. A
  literal `/dev/fd/...`, `/dev/std*` or `/proc/*/fd/...` operand never
  resolves clean (it can name a directory opened by a redirect, as in `cat
  /dev/fd/3/.ssh/config 3<~`); only a bare process substitution is exempt.
  Recursive readers that follow symlinks below their operands (`grep -R`,
  `rg -L`/`--follow`, `diff -r`, `find -L`/`-follow`) are not allowed at all.
  When the verdict is passthrough and the command has local write targets
  (redirections, `tee`, `cp`, `mv`, ... in the main command and in local
  payloads), the same single call resolves them and a target that resolves to
  a persistence, package-registry config, block-device or sysrq path asks.
  `~` and `$HOME` expand only from the hook's own `HOME`; a symlinked `HOME` is
  mapped back so `~/` classes still match. Commands without path operands,
  git units or write targets fork nothing extra.
- **Repo-local git config.** Read-only git commands run programs named in
  config (`core.fsmonitor` on `status`, `diff.*.textconv` on `log -p`, filter
  drivers, `core.pager`, `remote.*.uploadpack` on `ls-remote`, ...). Before
  allowing any git unit, `gate.sh` runs one
  `git -C <dir> config --local --includes --get-regexp` (with
  `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` set to `/dev/null`, so only the
  repository's own config is read) for `core.{fsmonitor,pager,editor,
  sshcommand,hookspath,askpass,gitproxy,attributesfile,worktree,
  alternaterefscommand}`, `sequence.editor`, `diff.external`,
  `diff.*.{textconv,command}`, `filter.*`, `merge.*.driver`,
  `credential.*helper`, `alias.*`, `pager.*`, `gpg.*program`,
  `uploadpack.packobjectshook`, `remote.*.{uploadpack,receivepack,proxy}`,
  `protocol.allow`, `protocol.ext.allow` (the `ext::` transport runs a
  command), `url.*.{insteadof,pushinsteadof}`, `submodule.*` (an initialised
  submodule has its own, unchecked config), `include.*`, `includeIf.*` and
  `extensions.worktreeConfig` (whose `config.worktree` the `--local` read
  would not see). A match, a directory that is not a repository, a
  non-literal `-C`, or git units in more than one directory passes through.
  Other `protocol.*.allow` keys are ignored. A repository that sets
  `core.hooksPath` therefore never gets git allows.
- **Operator probe.** shfmt encodes operators as integers before v3.14 and as
  strings since. `gate.sh` prepends a fixed five-statement preamble to every
  parse, and `engine.jq` reads the encoding from it, so there is no separate
  probe run and no hard-coded operator numbers.

## Rule tables

All rules are data in `scripts/rules/`:

| File | Contents |
|---|---|
| `allow.json` | allow entries (read-only commands and their argument predicates) |
| `danger.json` | danger entries (table rules and named built-in shape checks) |
| `paths.json` | secret, persistence, package-registry config, device and kernel-trigger path classes, safe redirect targets |
| `tools.json` | wrappers, container exec forms (`exec_wrappers`), ssh-like tools (`ssh_like`), interpreter families (`interp_families`), write verbs (`write_verbs`), named argument specs (`arg_specs`), network and upload tools, env whitelist, git globals, node types |
| `regex.json` | named regexes referenced as `"@name"` from rules (git exec keys, sed scripts, ssh local-exec options, inline-code keywords, infra unit names) |

### Entry fields

| Field | Meaning |
|---|---|
| `id` | stable rule id, reported in reasons and the audit log |
| `cmd` | normalised command names (basename; quotes and `\` removed) |
| `cmd_re` | danger only: regex on the command name instead of `cmd` |
| `sub` | git only: subcommand after global options |
| `args` | how to split arguments: `arg_flags` (`{"-o": 1}` = takes one value), `short_combine` (default true; false for single-dash long options such as `find -name`). `"@name"` (for `args` or `arg_flags`) refers to `tools.json` `arg_specs.name` |
| `when` | list of clauses, all of which must hold |
| `paths` | allow only: `check` (default, every non-pattern argument is checked against secret paths), `none`, or `find` (leading path operands only) |
| `pattern` | allow only: `{pos, flags}` names the pattern operand (grep/sed/jq), which is not a path |
| `recursive` / `recursive_flags` | allow only: recursive readers may not start at `/` or an ancestor of a secret directory, and a directory operand must be inside the working directory or `/tmp` |
| `check` | danger only: a named built-in shape check (see below) |
| `reason` | text shown in the permission prompt |
| `verdict` | danger only: `ask` (default) or `deny` |

### Clauses

| Clause | Holds when |
|---|---|
| `{"has": [flags]}` | one of the flags is present (combined short flags count; danger rules also accept unambiguous `--long` prefixes) |
| `{"no": [flags]}` | none present (prefix-tolerant) |
| `{"only": [flags]}` | every flag present is in the list (exact names, so an abbreviation is not allowed) |
| `{"only_re": re}` | every flag present matches the regex (`ro-find`'s predicate allowlist) |
| `{"lead_only": {"before": n, "flags": [...]}}` | flags before the n-th positional are all in the list |
| `{"pos": n, "in" / "not_in" / "in_or_absent": [...]}`, `{"pos": n, "re": re}` | the n-th positional |
| `{"any_pos_in": [...]}`, `{"any_pos_re": re}`, `{"all_pos_not_re": re}` | positional tests |
| `{"max_pos": n}`, `{"min_pos": n}` | positional count |
| `{"any_arg_re": re}` | any raw argument matches |
| `{"flag_value_re": {"flags": [...], "re": re}}` | a flag's value matches |
| `{"pattern_re": re}`, `{"pattern_not_re": re}` | the pattern operand(s) match / do not match |
| `{"broad_target": {"set": "rm" or "system", "from": n}}` | a positional from n is `/`, `~`, a top-level directory, a broad glob, an ancestor of the working directory (`rm` set), or unresolved (`rm` set) |
| `{"git_c_re": re}` | a `git -c`/`--config-env` key matches |
| `{"push_target_re": re}` | `git push` only: any refspec destination (the `dst` of `src:dst`, or the bare ref; a leading `+` is ignored; a glob destination always counts as a match) matches. With no refspec (or `HEAD`), the branch the push would update is tested: `@{push}` of the hook's working directory, else its current branch. That target is read only when the whole command is one plain `git push` (no `cd`, `-C`, branch switch, env prefix, quoting or compound command), and `--all`/`--mirror`/`--tags` pushes never use it; otherwise it is unresolved. When the target cannot be resolved the clause holds, so the rule asks. Not allowed in `allow` entries or under `not` |
| `{"flag_with_pos": {"flags": [...], "pos_re": re}}` | one of the flags is present and some positional matches (`git push --tags` with a tag-looking ref; `gh api -X POST` with a path containing `/releases`) |
| `{"not": [clauses]}` | not all of the clauses hold |

## Your own rules (layers)

The shipped tables cannot be edited in place (an update would overwrite them), so
rules are layered. Layers load in this order, and files within a layer in lexical
order:

| Layer | Location | May add | May override or disable ids |
|---|---|---|---|
| shipped | `scripts/rules/*.json` | allow, ask, deny | n/a |
| system | `/etc/claude-code/permission-manager.d/*.json` (macOS: `/Library/Application Support/ClaudeCode/permission-manager.d/*.json`) | allow, ask, deny | yes |
| user | `${XDG_CONFIG_HOME:-$HOME/.config}/permission-manager/rules.d/*.json` | allow, ask, deny | yes |
| project | `<git toplevel>/.claude/permission-manager/*.json`, only with `PERMISSION_MANAGER_PROJECT_RULES=1` | ask, deny only | no |

The location does not depend on `CLAUDE_CONFIG_DIR`, so one policy covers several
installs on a machine and headless containers. `PERMISSION_MANAGER_RULES_PATH`
(`:`-separated directories, loaded as user layers in order) replaces the system and
user layers, for tests and containers. A repository checkout can never widen
permissions: the project layer is off by default, and cannot add `allow` entries or
override or disable anything. A repository can also set hook environment variables
(`settings.json` `env`), so when `PERMISSION_MANAGER_RULES_PATH` or `XDG_CONFIG_HOME`
is set, a system or user layer directory inside the repository being worked in is
ignored (with a note).

A layer file:

```json
{
  "version": 1,
  "danger": [
    {"id": "user.tea-release-create", "cmd": ["tea"],
     "args": {"arg_flags": {"--login": 1, "-l": 1, "--repo": 1, "-r": 1, "--remote": 1, "-R": 1}},
     "when": [{"pos": 1, "in": ["releases", "release", "r"]}, {"pos": 2, "in": ["create", "c"]}],
     "reason": "creates a release"},
    {"id": "user.git-push-lease-default", "cmd": ["git"], "sub": ["push"],
     "when": [{"has": ["--force-with-lease", "--force-if-includes"]},
              {"push_target_re": "^(refs/heads/)?(main|master)$"}],
     "reason": "lease push to the default branch"}
  ],
  "allow": [],
  "regex": {"user.release_tag": "^(refs/tags/)?v?[0-9]+\\.[0-9]+"},
  "override": {"git-push-force": {"when": [{"has": ["--force", "-f"]}]}},
  "disable": []
}
```

- Entries use the same fields as the shipped tables. `"@name"` resolves against the
  merged `regex` and `tools.arg_specs`.
- Added ids, regex names and `tools.arg_specs` names must contain a `.`
  (`owner.name`), so they cannot shadow a shipped one. A duplicate id rejects the
  file. `check` is reserved for shipped rules, and a layer `verdict` is `ask` or
  `deny`.
- `override.<id>` merges fields into the existing entry in place (`when` is
  replaced, not appended; allow is first-match, so the position is kept).
  `disable` removes entries by id. An id that does not exist is ignored with a
  note, so an update that drops a shipped id does not take your file with it.
- Added allow entries still pass every existing check: resolved words, secret
  paths, redirects, `resolve_check` and `git_clean`.

Every file is validated (`scripts/validate.jq`): known keys and `version`, the
sections the layer allows, the id format, regexes that compile, and known clause
keys. The last matters because an unknown clause key would otherwise make a rule
never fire, silently. An invalid or unparsable file is skipped by itself, with one
stderr note and one `RULES_ERROR` audit line per session; the other files and the
shipped rules still apply, and a failed merge falls back to the shipped rules,
never an empty table.

`gate.sh` merges the layers once (`scripts/merge.jq`) and caches the result under
`${XDG_CACHE_HOME:-$HOME/.cache}/permission-manager/` (directory 700, files 600),
keyed on the path and content of every input (symlinked rule files included), so a changed file is picked up
on the next call and an unchanged set costs one hash of the rule files per call. With no layer files
nothing is merged, and behaviour and cost are unchanged.

Moving `permissions.ask` globs here: keep the globs until the matching cases pass
(`test-gate.sh --rules-dir DIR --cases DIR`). Pipe-to-shell globs
(`Bash(*| sh)`) can be deleted outright, since Claude Code splits compound commands
on `|` before matching and they never matched; the `pipe_interpreter` and
`subst_interpreter` checks already cover `curl … | sudo sh` and `bash <(curl …)`.
MCP tool rules stay in `settings.json`; layers are Bash-only.

## Rules shipped in v3.2.0

Danger (all ask; there is no deny rule):

- git: `git-push-force`, `git-push-plus-refspec`, `git-push-delete-refspec`,
  `git-push-mirror`, `git-push-prune`, `git-push-delete`, `git-reset-hard`,
  `git-clean-force`, `git-checkout-discard`, `git-checkout-force`,
  `git-restore-all`, `git-stash-drop`, `git-branch-force-delete`,
  `git-branch-delete-force`, `git-tag-delete`, `git-reflog-expire`,
  `git-gc-prune-now`, `git-prune`, `git-filter-history`,
  `git-update-ref-delete`, `git-worktree-remove-force`, `git-rebase-exec`,
  `git-config-exec-key`, `git-c-exec-key`. A plain `git push` to any branch,
  including `master`, is not dangerous.
- network/exec checks: `net-pipe-interpreter`, `net-subst-interpreter`,
  `net-download-exec`, `secret-upload`, `secret-pipe-upload`,
  `ssh-local-command`.
- inline interpreter code: `interp-inline-exec`, `interp-inline-persist`
  (see below).
- persistence: `persist-write`, `persist-crontab`, `persist-systemctl`,
  `persist-at`, `persist-launchctl`. `persist-write` covers redirections
  (`>`, `>>`, `>|`, `&>`, `: >`), `tee`, `cp`, `mv`, `install`, `ln`
  (incl. `ln -sf`), `sed -i`, `dd of=`, `truncate`, `sponge`, `patch` (its
  file operand and `-o`), `ed`/`red`/`ex`/`vi`/`vim`/`nvim` file operands,
  `perl -i`/`ruby -i` file operands, `chattr`, `setfacl`, downloads (`curl -o`,
  `wget -O`), and the destination of `rsync`/`scp`/`sftp` (a remote
  `host:path` is mapped onto `~/` on that host, so `scp k h:.ssh/authorized_keys`
  asks). `git config --global` of an exec-capable key is `git-config-exec-key`.
- package-registry redirection: `pkg-npm-registry` (`npm`/`pnpm config set
  registry`, `npm set registry`, scoped `@x:registry`), `pkg-pip-index` (`pip
  config set *.index-url` / `*.extra-index-url`), `pkg-registry-config-write`
  (writes to `.npmrc`, `pip.conf`/`pip.ini`, `uv.toml`, `.cargo/config[.toml]`;
  uv and cargo have no `config set` command, so their config files are the
  equivalent).
- destructive filesystem: `fs-rm-recursive-broad`, `fs-rm-no-preserve-root`,
  `fs-find-delete`, `fs-find-exec-rm`, `fs-dd-device`, `fs-mkfs`, `fs-shred`,
  `fs-chmod-recursive-broad`, `fs-redirect-device`. `rm -rf` of a specific
  relative path is not dangerous (it passes through).
- destructive infrastructure: `zfs-destroy`, `zfs-rollback`, `zfs-force`
  (`unmount`/`receive`/`rename` with `-f`/`-F`), `zpool-destroy`
  (`destroy`/`export`/`clear`/`detach`/`remove`/`offline`/`labelclear`),
  `zpool-force` (`create`/`add`/`replace`/`attach`/`import`/`split -f`),
  `docker-volume-rm`, `docker-system-prune`, `docker-prune-force` (image,
  container, network, builder prune with `-a`/`-f`), `docker-rm-force`,
  `docker-obj-rm-force`, `docker-compose-down-volumes`,
  `docker-compose-v1-down-volumes` (`-v`/`--volumes`/`--rmi all`),
  `kubectl-delete`, `systemctl-stop-infra` (`stop`/`disable`/`mask`/`kill`/
  `reset-failed` of a unit matching `docker`, `containerd`, `ssh`, `network`,
  `wireguard`, `wg-quick` or `tailscale`; the pattern is `infra_units` in
  `regex.json`), `systemctl-power`, `sys-power`, `sys-shutdown` (not
  `shutdown -c`), `sys-mount` (not the listing forms `mount`, `mount -l`,
  `mount -t TYPE`), `sys-umount`, `sys-exportfs-unexport`,
  `net-firewall-flush` (`iptables` family `-F`/`-X`), `net-nft-flush`,
  `net-nft-delete`, `net-ip-link-delete`, `sys-kernel-trigger` (writes to
  `/proc/sysrq-trigger` or `/proc/sys/kernel/sysrq`). `zfs list|get|snapshot|
  send`, `docker kill`/`stop` and plain `docker rm` are not dangerous.

All danger rules apply at every depth: inside wrappers, `bash -c`/`eval`
payloads, ssh remote commands and container exec argv.

### Inline interpreter code (coarse)

For `python*`/`pypy*`, `node`/`nodejs`/`bun`, `deno eval`, `perl`, `ruby`,
`php` and `lua`/`luajit`, the literal code given with `-c`/`-e`/`-E`/`-p`/
`--eval`/`--print`/`-r` (php), or fed on stdin (`-`, a heredoc or here-string,
or a literal `echo`/`printf`/`cat <<EOF` piped in), is searched for process
execution, deletion and network APIs (`os.system`, `subprocess`, `popen`,
`exec(`, `eval(`, `__import__`, `shutil.rmtree`, `os.remove`/`unlink`/`rmdir`,
`socket`, `urllib`, `requests`, `http.client`, `ftplib`, `smtplib`,
`child_process`, `fs.rm*`/`unlink*`, `curl`/`wget`, `system(`, backticks and
`qx` in perl/ruby, `File.delete`, `FileUtils.rm`, `os.execute`, `shell_exec`,
...), and for a file write (`writeFile`, `open(`, `file_put_contents`, ...)
next to a persistence path name. A match asks. This is a keyword heuristic
for **ask only**: it is trivially bypassable (string building, encodings,
`getattr`), it never allows, and no match means passthrough, i.e. the
classifier decides. Even provably trivial code (`python -c 'print(1)'`) passes
through.

Allow: `ro-basic`, `ro-noargs`, `ro-strings`, `ro-test`, `ro-printf`, `ro-file`,
`ro-date`, `ro-hostname`, `ro-command-v`, `ro-sort`, `ro-uniq`, `ro-grep`,
`ro-rg`, `ro-jq`, `ro-yq`, `ro-sed`, `ro-find`, `ro-diff`, `ro-ps`, `git-ro`, `git-ls-remote`,
`git-branch-list`, `git-branch-list-pattern`, `git-tag-list`,
`git-tag-list-pattern`, `git-remote-list`, `git-remote-get-url`,
`git-remote-show`, `git-config-read`, `git-config-get`, `git-worktree-list`,
`git-stash-list`, `git-reflog-show`, `git-reflog-show-explicit`, `docker-ro`,
`docker-stats`, `docker-compose-ro`, `systemctl-ro`, `journalctl-ro`,
`top-batch`, `ip-show`, `ip-route-get`, `ss-ro`, `ping-count`, `dns-lookup`,
`zfs-ro`, `zpool-ro`, `printenv-name`.

Every unit must also have resolved words, no output redirection other than
`/dev/null`, `/dev/stdout`, `/dev/stderr` or an fd duplication, no input from a
secret path or `/dev/tcp`, no secret path argument, no privileged wrapper, and
only whitelisted environment assignments (`LC_*`, `LANG`, `TZ`, `TERM`,
`NO_COLOR`, `COLUMNS`, `GIT_PAGER=cat`, `PAGER=cat`, ...).

### Considered, rejected (pass through in v1)

- `awk`: its language can run commands (`system()`, `|` pipes) and write files.
- bare `env` and bare `printenv`: they print every secret in the environment.
- `printenv` of any name outside a short whitelist (`PATH`, `HOME`, `USER`,
  `SHELL`, `PWD`, `LANG`, `LC_*`, `TERM`, `TZ`, `EDITOR`, `XDG_*`, ...).
- `ps` with a BSD `e` option or any `env` format (prints process environments).
- `docker -H`/`--host`/`--config` and `systemctl -H`/`-M` (remote or planted
  configuration; possible option injection into ssh).
- `zpool status -c` (runs scripts from `~/.zpool.d`), `date -f`, `find
  -files0-from`, recursive `grep`/`rg`/`diff` starting at `/`, a home directory or
  an ancestor of a secret directory, or at a directory outside the working
  directory and `/tmp`.
- list-of-files options, which open every name listed in a file:
  `sort`/`wc`/`du --files0-from`, `file -f`/`--files-from`.
- `find` with any predicate outside the read-only allowlist (`-exec*`, `-ok*`,
  `-delete`, `-fprint*`, `-fls`, bfs `-rm`, ...) or a `--` operand.
- `test`/`[` with `-v`/`-R` or an operand containing `[`, `$(` or a backtick
  (`test -v 'a[$(cmd)]'` runs `cmd` while expanding the subscript).
- `git ls-remote` with any option outside `--heads --branches --tags --refs
  -q --exit-code --get-url --symref --sort` (`--exec` is a hidden alias of
  `--upload-pack`; abbreviations such as `--upload-p` count as unknown) or a
  `transport::address` remote. Deny lists in the other git rules (`no`)
  match unambiguous `--long` prefixes, as git does.
- `docker inspect`, `docker compose config` (print interpolated secrets).
- `jq -f FILE` and filters using `env`, `ENV` (also `$ ENV`), `$__prog*`,
  `import` or `include`; `yq` expressions using `load`, `env`, `ENV`, `strenv`,
  `eval(` or `include`.
- `sed` scripts with anything beyond addresses plus `p d q Q = n N D P h H g G x
  l z`, `s///` with flags `g p i I m M` and digits, or `y///` (so `w`, `W`, `r`,
  `R`, `e`, `{}` and non-`/` delimiters pass through).
- `mkdir -p`, `touch`, `cd` and other write-ish or state-changing commands.
- `git grep` (has `-O`/`--open-files-in-pager`), `git branch`/`tag` with
  positionals outside `--list`, every git subcommand not listed above.
- `nohup` (may write `nohup.out`), `xargs` and `find -exec` (arguments unknown),
  `watch`, `sudo`/`doas`.
- `ssh`, `mosh`, `autossh`, `docker exec`, `kubectl exec` and the other exec
  wrappers, even with a read-only inner command.
- inline interpreter code of any kind (see above).

### Known gaps

- **Unresolved command names.** `$CMD args`, `"${x}" ...` or `$(...)` as the
  command word cannot be analysed; such a unit passes through (never allowed),
  but no danger rule can fire on it either.
- **Process-tree tricks.** Commands that start something that outlives or
  escapes the analysed text (a background job that later reads a file, a
  daemon or socket started in the same call, `trap`, `PROMPT_COMMAND`,
  `LD_PRELOAD`-style environment set by an earlier call) are judged only by
  the text of the current call.
- **Hardlinks.** realpath cannot reveal a hard link: `ln ~/.ssh/id_rsa x`
  then `cat x` reads the key through an innocent-looking name. Creating the
  link passes through; the later read is allowed.
- **Symlink races (TOCTOU).** Paths are resolved when the hook runs; a link
  created or retargeted later in the same command (`ln -sf ~/.ssh/id_rsa x;
  cat x`, where `ln` passes through anyway) or by a concurrent process is not
  seen.
- **git hooks in `.git/hooks`.** Only repo config is checked. A hook file
  such as `post-index-change` (which `git status` can trigger when it
  refreshes the index) is not inspected.
- **Inline-code heuristic** is bypassable by construction (see above), e.g.
  `getattr(os, 'sy' + 'stem')` or `require('child_' + 'process')`.
- **ssh configuration.** `ssh -F file`, `~/.ssh/config` `Match exec` or
  `ProxyCommand`, `scp -S` and `rsync -e` programs run locally but only the
  explicit `-o` forms above ask (`rsync -e` and `mosh --ssh` text is
  re-parsed for danger rules).
- **Write targets not modelled.** Whole-directory copies into a persistence
  location (`cp -r dotfiles/. ~`, `rsync -a payload/ ~/`), archive extraction
  (`tar -C ~ -x`, `unzip -d`), download directories (`curl --output-dir`,
  `wget -P`) and anything written by a program's own logic pass through
  without the persistence ask.
- **Submodules** are covered only through the `submodule.*` keys in the
  superproject's config; an absorbed `.git/modules/*` directory without them
  is not inspected.
- **Remote paths** are classified with the local `$HOME` layout and the local
  persistence classes; a remote `~` elsewhere is not modelled.
- **Package registries** set through the environment (`NPM_CONFIG_REGISTRY`,
  `PIP_INDEX_URL`, `UV_INDEX_URL`, `CARGO_REGISTRIES_*`), `python -m pip
  config` or CLI flags (`pip install -i`) are not flagged.
- **Payload limits.** Program text nested more than 4 levels deep, or beyond
  16 payloads per call, is not re-parsed (it can never be allowed, but its
  danger rules do not fire).
- **Oversize commands ask.** A command over 20000 characters, with more than
  1500 `|`/`&` characters, more than 200 commands, a syntax tree over 8 MB
  or nested more than 120 levels deep, a parse over 3 s, or nesting beyond
  shfmt's depth limit is answered with ask (`oversize`), never allow and
  never passthrough: shfmt's JSON is indented by nesting depth, so padding
  (`rm -rf ~;` plus a 3000-stage pipeline) would otherwise push the run past
  the 10 s hook timeout and lose the ask. A large legitimate command (say, a
  heredoc holding a big Markdown table) therefore gets a prompt instead of
  the classifier.
- **Syntax-tree depth limit.** jq 1.6 and Debian's jq 1.7 refuse to parse
  JSON nested deeper than about 128 objects, and shfmt nests its tree two
  levels per `|`, `&&`, `||` or `|&` stage (more for `$( )`, `{ }`, `if`,
  `$(( ))`). The gate therefore asks for any tree deeper than 120 levels
  before jq runs, so the result does not depend on the jq build: a pipeline
  of up to 56 stages is classified, a longer one asks. `;`-separated lists
  do not deepen the tree.
- **Engine failure asks.** If the jq engine exits non-zero (a crash, a
  parse-depth error, a 5 s timeout) or prints no valid verdict, the call asks
  (`engine-error` or `oversize`) instead of passing through, so a failure can
  never drop a danger ask. The exceptions are faults of shfmt rather than the
  engine, which pass through like a missing dependency: an operator encoding
  the engine cannot read (the operator probe fails) and shfmt output that is
  not valid JSON. A failed write-target check after a
  passthrough verdict asks too; a failed path check on an allow only loses
  the allow (passthrough).
- **Recursive readers inside the working directory** are allowed and read
  every file there, `.env` included (`grep -r KEY .`); `rg` skips hidden and
  ignored files unless `-u`/`--hidden`/`--no-ignore` is given.

### Assumptions about Claude's shell

- **Shims.** Claude Code's shell snapshot can alias `find` to `bfs`, `grep`
  to `ugrep` and `ls` to `eza`. The rules are written against the GNU tools
  but cover the shims where they differ: `ro-find` is an allowlist of
  read-only predicates and actions (any other `-word`, including bfs's `-rm`
  and `-f PATH`, is not allowed; `-rm` asks like `-delete`), and an unknown
  option is never allowed for any rule built on `only`. Options that exist
  only in a shim and are harmless there may pass through.
- **zsh globbing.** The Bash tool runs the user's shell, often zsh. With
  `EXTENDED_GLOB`, `#`, `^` and a non-leading `~` are glob operators (`cat
  .en#v` reads `.env`), so an unquoted path operand containing them is
  treated as a glob and not allowed; quote such words (`git show 'HEAD~1'`)
  to keep the allow. zsh's `(...)` qualifiers are a bash syntax error and
  never parse.
- **Secrets printed by read-only commands.** `docker inspect` and `docker
  compose config` print interpolated environment values and are not allowed
  (`docker ps`/`images`/`logs`/`stats`/`version`/`info` and `docker compose
  ps`/`logs` are). `docker logs` and `journalctl` can still print whatever a
  service logged.

## Audit log

ALLOW, ASK and DENY decisions (not passthroughs) are appended as JSON lines to
`${PERMISSION_AUDIT_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/permission-audit.jsonl}`
with `ts`, `decision`, `reason`, `command` (first 200 characters only, for
every decision) and `cwd`. The file is created with mode 600 (umask 077; a
missing directory is created 700), and an existing log that is a regular file
owned by the current user (not a symlink) is narrowed to 600 on every write.

## Debugging

`PM_GATE_DEBUG=1` prints the verdict and reason of every engine run to stderr,
including passthroughs.

Rule-layer problems (an unparsable or invalid file, a failed merge) print one
stderr note per session and append a `RULES_ERROR` line to the audit log. The
merged tables are in `${XDG_CACHE_HOME:-$HOME/.cache}/permission-manager/<key>/`
(`errors.json` lists what was skipped); deleting that directory is always safe.

## Tests

`bash tests/permission-manager/test-gate.sh [--rules-dir DIR] [--cases DIR] [filter]`
runs the case tables in `tests/permission-manager/cases/*.tsv`
(`EXPECTED<TAB>command`) plus protocol, audit-log, rule-layer, failure-mode and
latency checks. `--rules-dir DIR` loads DIR as a user rule layer for every case and
`--cases DIR` adds your own `*.tsv` tables, so you can test your rules with the
shipped harness. Command text is only ever data on the hook's stdin; canary cases
prove it is never executed.
