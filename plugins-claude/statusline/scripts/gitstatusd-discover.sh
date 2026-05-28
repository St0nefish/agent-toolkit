#!/bin/bash
# Locate the gitstatusd binary across known install methods.
# Echoes the first executable match and returns 0; returns 1 if none found.
# Order: $GITSTATUS_DAEMON, self-bootstrap cache, Homebrew, PATH.
# Globbing the arch suffix matches whatever romkatv ships (arm64 vs aarch64).
find_gitstatusd() {
  local platform candidate brew_prefix
  platform=$(uname -s | tr '[:upper:]' '[:lower:]')

  if [[ -n "${GITSTATUS_DAEMON:-}" && -x "${GITSTATUS_DAEMON}" ]]; then
    echo "$GITSTATUS_DAEMON"
    return 0
  fi

  for candidate in "$HOME/.cache/gitstatus/gitstatusd-${platform}-"*; do
    [[ -x "$candidate" ]] && {
      echo "$candidate"
      return 0
    }
  done

  if brew_prefix=$(brew --prefix gitstatus 2>/dev/null) && [[ -n "$brew_prefix" ]]; then
    for candidate in "$brew_prefix/usrbin/gitstatusd-${platform}-"*; do
      [[ -x "$candidate" ]] && {
        echo "$candidate"
        return 0
      }
    done
  fi

  if candidate=$(command -v gitstatusd 2>/dev/null); then
    echo "$candidate"
    return 0
  fi

  return 1
}
