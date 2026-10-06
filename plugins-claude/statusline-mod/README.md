# statusline-mod

A status band for Claude Code, built as a **mod** (a hooks module that draws
inside Claude Code) rather than a `statusLine` shell command. It replaces the
`statusline` plugin's bash script: there is no process per redraw, no `curl`
polling, and no install step that edits `settings.json`.

## Installation

```text
/plugin install statusline-mod --marketplace St0nefish/agent-toolkit
```

It is active immediately and in every session after that. Run
`/statusline:statusline-teardown` first if you still have the older `statusline`
plugin's status line installed, so you do not see two.

## What it shows

One row above the prompt: where you are on the left, how the session is going
on the right.

```text
stonefish │ ⌂ agent-toolkit   master +1 !2 ?3        Sonnet 5.5  ▰▰▰▱▱▱▱▱▱▱ 11%  ◷ 85% 3h03m  ▦ 78% 1d19h
```

| Segment | Shows |
|---------|-------|
| user | Username, `user@host` over SSH, red as root |
| project | Project name (the main repo's name inside a linked worktree, marked `⧉`) |
| branch | Branch with the powerline branch glyph, ellipsized in the middle when long; green when clean, yellow when dirty |
| git chips | `+` staged, `!` modified, `?` untracked, `⇡` ahead, `⇣` behind (as in Powerlevel10k) |
| model | Friendly name (`Sonnet 5.5`), not the model id |
| context | Fill bar and percentage |
| limits | 5h (`◷`) and 7d (`▦`) usage; reset countdown appears once a window passes 50% |
| cost | Session cost, only when no rate limits are reported |

The band sheds detail as the terminal narrows: below 110 columns it drops the
username and shortens the bar, below 80 it drops the bar and the weekly window.

## Data sources

Context, usage windows and cost come from the session itself
(`session.measure`), so nothing polls an API. Git status is read with
`git status --porcelain=v2` after each Bash call and each turn.

## Not yet included

- Monthly extra-credits segment
- User-configurable layout (the old `config.json`)
