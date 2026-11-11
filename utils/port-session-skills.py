#!/usr/bin/env python3
"""One-time port of the Claude session skills to plugins-opencode.

Applies utils/opencode-port.py (the shared harness mapping), drops Claude-only
frontmatter, and rewrites the $ARGUMENTS sentences (OpenCode skills receive no
slash arguments; the registered command doors pass invocation text through
the prompt instead). Re-run after editing a Claude original, then review the
diff — tests/opencode/test-session-port.sh guards the result.
"""

import re
import sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

_here = Path(__file__).parent
_spec = spec_from_file_location("opencode_port", _here / "opencode-port.py")
_mod = module_from_spec(_spec)
_spec.loader.exec_module(_mod)
render = _mod.render

SRC = Path(__file__).parent.parent / "plugins-claude/session/skills"
DST = Path(__file__).parent.parent / "plugins-opencode/session/skills"

SKILLS = [
    "session-start",
    "session-issue",
    "session-end",
    "session-orchestrate",
    "session-summarize",
]

# $ARGUMENTS rewrites per skill (exact strings; OpenCode doors pass arguments
# through the invoking prompt, so skills speak of "the invocation arguments").
ARG_REWRITES = {
    "session-start": [
        (
            "1. The work comes from `$ARGUMENTS` (your description). If this skill was invoked by\n   the model rather than a slash command, `$ARGUMENTS` is empty: use the work the user\n   already described in the conversation as the description and do not re-ask. If\n   `$ARGUMENTS` is empty and nothing was described, ask",
            "1. The work comes from the arguments provided with the invocation (the `/session-start`\n   command passes them through; your description). If this skill was invoked by\n   the model rather than the command, no arguments were provided: use the work the user\n   already described in the conversation as the description and do not re-ask. If\n   there are no arguments and nothing was described, ask",
        ),
    ],
    "session-issue": [
        (
            "2. **Issue numbers in `$ARGUMENTS`** (`#127 #125 #115`, `127 and 125`, `127,125`):",
            "2. **Issue numbers in the invocation arguments** (`#127 #125 #115`, `127 and 125`, `127,125`):",
        ),
    ],
    "session-orchestrate": [
        (
            "- `$ARGUMENTS` — optional initial description. If empty and no context inherited from `session-start`, ask the user to describe the feature before starting Phase 1.",
            "- The invocation arguments — optional initial description. If absent and no context inherited from `session-start`, ask the user to describe the feature before starting Phase 1.",
        ),
        (
            "- Issue refs (`#N`) in `$ARGUMENTS` with no prior spine run in this session",
            "- Issue refs (`#N`) in the invocation arguments with no prior spine run in this session",
        ),
    ],
}


def strip_frontmatter_line(text: str, key: str) -> str:
    m = re.match(r"^(---\n.*?\n---\n)", text, re.S)
    if not m:
        return text
    fm, rest = m.group(1), text[m.end() :]
    fm = "\n".join(l for l in fm.splitlines() if not l.startswith(f"{key}:")) + "\n"
    return fm + rest


for skill in SKILLS:
    src = SRC / skill / "SKILL.md"
    dst = DST / skill / "SKILL.md"
    text = src.read_text()
    text = strip_frontmatter_line(text, "allowed-tools")
    text = render(text)
    for old, new in ARG_REWRITES.get(skill, []):
        if old not in text:
            print(
                f"WARN: {skill}: $ARGUMENTS rewrite not applied (text changed upstream?):\n  {old[:80]}..."
            )
        text = text.replace(old, new)
    if "ARGUMENTS" in text:
        print(f"WARN: {skill}: leftover $ARGUMENTS")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text)
    print(f"ported: {dst.relative_to(DST.parent.parent)}")
