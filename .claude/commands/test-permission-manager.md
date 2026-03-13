---
description: "Live integration test for the permission-manager hook classifier"
allowed-tools: Bash, Read, AskUserQuestion
---

# Permission-Manager Integration Test

You are running a live integration test of the permission-manager hook. This test verifies the full end-to-end path: hook registration → payload → classifier → response → CLI behavior.

## Instructions

Follow these phases exactly. Track results as you go.

### Setup

Run the setup script to create a temporary test directory with fixtures and a git repo:

```bash
bash test/permission-manager/test-integration.sh setup
```

Capture the output path as `$TD`. All subsequent commands use this path.

### Phase 1: Deny (8 tests)

These commands should be **hard-blocked** by the hook. The hook will deny them — no user interaction needed. Attempt each via the Bash tool and observe the deny response.

**PASS** = hook blocked the command (you see a deny/block response).
**FAIL** = command executed or you were prompted to approve.

| Test | Command |
|------|---------|
| D1 | `echo foo > $TD/output.txt` |
| D2 | `cat $TD/hello.txt > $TD/copy.txt` |
| D3 | `echo foo >> $TD/log.txt` |
| D4 | `find $TD -name '*.txt' -delete` |
| D5 | `find $TD -exec rm {} \;` |
| D6 | `git -C $TD push origin main` |
| D7 | `git -C $TD branch -D main` |
| D8 | `git -C $TD status && git -C $TD push origin main` |

Replace `$TD` with the actual path from setup.

### Phase 2: Ask (15 tests)

These commands should **prompt for permission**. Before starting this phase, tell the user:

> **Phase 2: Ask tests starting.** I'll attempt 15 commands that should trigger permission prompts. Please **reject each prompt** when it appears. Say "go" when you're ready.

Wait for the user to confirm before proceeding. Then attempt each command via the Bash tool.

**PASS** = hook prompted for permission (and user rejected it).
**FAIL** = command was allowed without prompting, or was hard-blocked instead of asking.

Note: In Copilot CLI, "ask" maps to "deny" — both are acceptable PASS outcomes.

| Test | Command |
|------|---------|
| A1 | `git -C $TD merge feature-branch` |
| A2 | `git -C $TD rebase feature-branch` |
| A3 | `git -C $TD reset HEAD~1` |
| A4 | `git -C $TD stash pop` |
| A5 | `git -C $TD tag -a v1.0 -m 'release'` |
| A6 | `git -C $TD push --force` |
| A7 | `git -C $TD checkout -b main` |
| A8 | `git -C $TD worktree add /tmp/perm-wt` |
| A9 | `docker run --rm alpine echo hi` |
| A10 | `docker compose -f $TD/docker-compose.yml up -d` |
| A11 | `docker --context atlas run --rm alpine echo hi` |
| A12 | `gh pr create --title 'test'` |
| A13 | `gh issue create --title 'test'` |
| A14 | `npm publish` |
| A15 | `cargo run` |

Replace `$TD` with the actual path from setup.

### Phase 3: Allow (42 tests)

These commands should be **silently allowed** by the hook. Tell the user:

> **Phase 3: Allow tests starting.** These 42 commands should all run without prompting. You can step away — no interaction needed.

**PASS** = no permission prompt appeared. The command's exit code does not matter (missing tools, no remote, etc. are fine).
**FAIL** = a permission prompt appeared, or the hook blocked the command.

| Test | Command |
|------|---------|
| L1 | `cat $TD/hello.txt` |
| L2 | `grep -r 'lorem' $TD` |
| L3 | `head -5 $TD/hello.txt` |
| L4 | `diff $TD/hello.txt $TD/notes.txt` |
| L5 | `ls -la $TD` |
| L6 | `wc -l $TD/hello.txt` |
| L7 | `find $TD -name '*.txt'` |
| L8 | `find $TD -name '*.txt' -exec grep -l lorem {} \;` |
| L9 | `echo hello > /dev/null` |
| L10 | `cat $TD/hello.txt 2>/dev/null` |
| L11 | `git -C $TD status` |
| L12 | `git -C $TD log --oneline -5` |
| L13 | `git -C $TD branch -a` |
| L14 | `git -C $TD tag -l 'v*'` |
| L15 | `git -C $TD checkout feature-branch` |
| L16 | `git -C $TD checkout main` |
| L17 | `git -C $TD checkout -b test-branch` |
| L18 | `git -C $TD add .` |
| L19 | `git -C $TD commit --allow-empty -m 'test'` |
| L20 | `git -C $TD stash list` |
| L21 | `git -C $TD remote -v` |
| L22 | `git -C $TD rev-parse HEAD` |
| L23 | `docker ps` |
| L24 | `docker images` |
| L25 | `docker --context atlas ps` |
| L26 | `docker compose -f $TD/docker-compose.yml ps` |
| L27 | `docker compose -f $TD/docker-compose.yml config` |
| L28 | `gh pr list` |
| L29 | `gh issue list` |
| L30 | `gh api repos/owner/repo/pulls` |
| L31 | `npm list` |
| L32 | `node --version` |
| L33 | `gradle --version` |
| L34 | `cargo --version` |
| L35 | `pip list` |
| L36 | `python3 --version` |
| L37 | `java -version` |
| L38 | `mvn --version` |
| L39 | `git -C $TD status && git -C $TD log --oneline -3` |
| L40 | `git -C $TD add . && git -C $TD commit --allow-empty -m 'compound'` |
| L41 | `find $TD -name '*.txt' \| grep hello` |
| L42 | `docker stats --no-stream` |

Replace `$TD` with the actual path from setup.

### Phase 4: Passthrough (3 tests)

These commands have **no classifier opinion** — the hook passes through silently. Record observed behavior but do not score pass/fail.

| Test | Command | Notes |
|------|---------|-------|
| P1 | `curl -s https://example.com` | network tool — no classifier opinion |
| P2 | `make --version` | build tool — no classifier opinion |
| P3 | `rm $TD/hello.txt` | file delete — Claude built-in handles this |

Replace `$TD` with the actual path from setup.

### Teardown

Run cleanup:

```bash
bash test/permission-manager/test-integration.sh teardown $TD
```

If A8 created a worktree at `/tmp/perm-wt`, clean it up first:

```bash
rm -rf /tmp/perm-wt
```

### Results

Print a summary table:

```text
| Phase       | Total | Pass | Fail |
|-------------|-------|------|------|
| Deny        | 8     | ?    | ?    |
| Ask         | 15    | ?    | ?    |
| Allow       | 42    | ?    | ?    |
| Passthrough | 3     | —    | —    |
```

Then list any failures with details:

- Test ID, command, expected behavior, actual behavior
- Note which failures are due to missing tools vs actual hook misclassification
