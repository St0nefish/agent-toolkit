# Convert Doc

Convert documents to and from markdown using pandoc. Model-triggered — fires when you work with DOCX, HTML, RST, EPUB, ODT, RTF, or LaTeX files.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/convert-doc
```

## Supported Formats

DOCX, HTML, RST, EPUB, ODT, RTF, LaTeX — all convertible to/from GitHub-flavored markdown. PDF output requires a LaTeX engine.

## Dependencies

| Tool | Required | Install |
|------|----------|---------|
| `pandoc` | Yes | `brew install pandoc` or `apt install pandoc` |
| `basictex` / `texlive` | For PDF output | `brew install --cask basictex` |
