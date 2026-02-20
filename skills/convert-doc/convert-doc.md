---
description: >-
  Convert documents to/from markdown using pandoc. Supports DOCX, HTML, RST,
  EPUB, ODT, RTF, and LaTeX. REQUIRED for all document conversion — do NOT
  use raw pandoc commands. Use when a user provides a .docx, .html, .rst,
  .epub, .odt, .rtf, or .tex file to read, or needs to export markdown to
  PDF or DOCX.
allowed-tools: Bash, Read, Write
---

# convert-doc

Convert documents to and from markdown using pandoc.

## Dependency check

Before running any conversion, verify pandoc is installed:

```bash
command -v pandoc
```

If not found, suggest: `brew install pandoc` (macOS) or `apt install pandoc` (Linux).

## To markdown (primary use case)

Convert a document to GitHub-Flavored Markdown. Pandoc auto-detects the input format from the file extension.

**To stdout** (preferred — then read the output directly):

```bash
pandoc -t gfm input.docx
```

**To a file:**

```bash
pandoc -t gfm -o output.md input.docx
```

**From a URL:**

```bash
pandoc -t gfm https://example.com/page.html
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

1. Convert the document to markdown: `pandoc -t gfm input.docx`
2. Read the markdown output
3. Work with the content as needed

## From markdown (secondary use case)

**To DOCX:**

```bash
pandoc -o output.docx input.md
```

**To PDF:**

```bash
pandoc -o output.pdf input.md
```

PDF output requires a LaTeX engine. If not installed, suggest: `brew install basictex` (macOS) or `apt install texlive` (Linux).
