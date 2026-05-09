---
name: convert-doc
description: >-
  Convert documents to/from markdown via pandoc — DOCX, HTML, RST, EPUB, ODT,
  RTF, LaTeX. Use when reading or producing any of those formats, or
  exporting markdown to PDF/DOCX.
allowed-tools: Bash, Read, Write
---

# convert-doc

Convert documents to and from markdown using pandoc.

## To markdown (primary use case)

Convert a document to GitHub-Flavored Markdown. Pandoc auto-detects the input format from the file extension.

**To stdout** (preferred — then read the output directly):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -t gfm input.docx
```

**To a file:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -t gfm -o output.md input.docx
```

**From a URL:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -t gfm https://example.com/page.html
```

### Supported input formats

| Extension | Format |
|-----------|--------|
| `.docx` | Microsoft Word |
| `.html` | HTML |
| `.rst` | reStructuredText |
| `.epub` | EPUB |
| `.odt` | OpenDocument Text |
| `.rtf` | Rich Text Format |
| `.tex` | LaTeX |

Use `-f <format>` to override auto-detection when the extension is ambiguous or missing.

### Typical workflow

1. Convert the document to markdown: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -t gfm input.docx`
2. Read the markdown output
3. Work with the content as needed

## From markdown (secondary use case)

**To DOCX:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -o output.docx input.md
```

**To PDF:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pandoc-wrap -o output.pdf input.md
```

PDF output requires a LaTeX engine. If not installed, suggest: `brew install basictex` (macOS) or `apt install texlive` (Linux).

If pandoc is not found, run `/convert-doc:setup`.
