---
description: "Verify ast-grep installation and print version or install instructions"
disable-model-invocation: true
allowed-tools: Bash
---

# ast-grep Setup

Check whether `ast-grep` is installed and print its version. If missing, print install instructions.

```bash
if command -v ast-grep &>/dev/null; then
  echo "ast-grep is installed:"
  ast-grep --version
else
  echo "ast-grep is NOT installed."
  echo ""
  echo "Install via Cargo (recommended):"
  echo "  cargo install ast-grep --locked"
  echo ""
  echo "Or via Homebrew (macOS):"
  echo "  brew install ast-grep"
  echo ""
  echo "After installing, run /ast-grep:setup again to verify."
fi
```
