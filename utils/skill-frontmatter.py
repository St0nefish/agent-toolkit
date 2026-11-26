#!/usr/bin/env python3
"""skill-frontmatter.py — shared SKILL.md frontmatter helpers for the porters.

Claude skills keep what a skill does in `description` and when to load it in
`when_to_use`. OpenCode and Copilot CLI read only `description`, so each porter
folds the two together. Loaded by utils/port-session-skills.py and
utils/port-copilot-skills.py via spec_from_file_location (the file name has a
hyphen, so it is not importable).

Only the frontmatter shapes this repo uses are understood: a plain single-line
scalar, a single- or double-quoted single-line scalar, or a `>`/`>-`/`|` block
scalar. In a `|` block, newlines are flattened to spaces (the same as `>`).

Anything else for `description` or `when_to_use` raises ValueError("<key>:
<reason>") rather than producing wrong text: a double-quoted escape other than
`\\"` or `\\\\`, a quoted value that does not close on its line or has trailing
content after the closing quote, a plain scalar followed by indented
continuation lines, or CRLF line endings.
"""

import re
import textwrap

_FM = re.compile(r"^(---\n)(.*?\n)(---\n)", re.S)


def _decode_quoted(key: str, v: str) -> str:
    """Decode a single-line YAML quoted scalar; raise ValueError if unsupported."""
    q = v[0]
    out = []
    i = 1
    while i < len(v):
        c = v[i]
        if q == '"' and c == "\\":
            nxt = v[i + 1 : i + 2]
            if nxt not in ('"', "\\"):
                raise ValueError(
                    f"{key}: unsupported escape '\\{nxt}' in double-quoted value"
                )
            out.append(nxt)
            i += 2
            continue
        if c == q:
            if q == "'" and v[i + 1 : i + 2] == "'":
                out.append("'")
                i += 2
                continue
            if v[i + 1 :].strip():
                raise ValueError(f"{key}: trailing content after closing quote")
            return "".join(out)
        out.append(c)
        i += 1
    raise ValueError(f"{key}: quoted value does not close on its line")


def _take(lines, key):
    """Return (start, end, value) of a top-level frontmatter key, or None.

    [start, end) is the line range the key occupies. For a block scalar, a
    continuation is an indented line, or a blank line followed by more
    indented lines (a blank line inside the block does not end it; trailing
    blank lines are not part of it). Unsupported shapes raise ValueError.
    """
    for i, l in enumerate(lines):
        if not l.startswith(f"{key}:"):
            continue
        v = l[len(key) + 1 :].strip()
        j = i + 1
        if v.startswith((">", "|")):
            parts = []
            end = j
            while j < len(lines):
                if lines[j].startswith((" ", "\t")):
                    parts.append(lines[j].strip())
                    j += 1
                    end = j
                elif not lines[j].strip():
                    j += 1  # blank: only continues if indented lines follow
                else:
                    break
            j = end
            v = " ".join(p for p in parts if p)
        elif v[:1] in ('"', "'"):
            v = _decode_quoted(key, v)
        else:
            k = j
            while k < len(lines) and not lines[k].strip():
                k += 1
            if k < len(lines) and lines[k].startswith((" ", "\t")):
                raise ValueError(
                    f"{key}: plain scalar with indented continuation lines is unsupported"
                )
        return i, j, v
    return None


def _split(text: str):
    m = _FM.match(text)
    if not m:
        if text.startswith("---\r\n"):
            raise ValueError("frontmatter: CRLF line endings are unsupported")
        return None
    if "\r" in m.group(2):
        raise ValueError("frontmatter: CRLF line endings are unsupported")
    return m


def frontmatter_value(text: str, key: str):
    """The decoded value of a top-level frontmatter key, or None."""
    m = _split(text)
    if not m:
        return None
    t = _take(m.group(2).splitlines(), key)
    return t[2] if t else None


def fold_when_to_use(text: str) -> str:
    """Append `when_to_use` to `description` and drop the `when_to_use` key.

    Emits the merged description as a `>-` folded block wrapped near 80 cols.
    Text without both keys is returned unchanged.
    """
    m = _split(text)
    if not m:
        return text
    lines = m.group(2).splitlines()
    w = _take(lines, "when_to_use")
    d = _take(lines, "description")
    if not w or not d:
        return text
    merged = f"{d[2]} {w[2]}".strip()
    block = ["description: >-"] + [
        "  " + l
        for l in textwrap.wrap(
            merged, width=78, break_long_words=False, break_on_hyphens=False
        )
    ]
    # Replace the later range first so indices stay valid.
    for (s, e, _), repl in sorted([(w, []), (d, block)], key=lambda x: -x[0][0]):
        lines[s:e] = repl
    return m.group(1) + "\n".join(lines) + "\n" + m.group(3) + text[m.end() :]
