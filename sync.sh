#!/bin/sh
# This repo holds the one copy of every skill. The plugins that ship some of
# them carry copies; this script writes those copies from here.
#
#   ./sync.sh          copy into sibling checkouts (../jolt-nrepl-mcp, ...)
#   ./sync.sh --check  exit 1 if any copy differs, writing nothing
#
# SKILLS_ROOT points at the directory holding the sibling checkouts.
set -eu
here="$(cd "$(dirname "$0")" && pwd -P)"
root="${SKILLS_ROOT:-$(dirname "$here")}"
check=0
[ "${1:-}" = "--check" ] && check=1
status=0

ship() { # ship <plugin-dir> <skill>...
  dir="$root/$1"; shift
  if [ ! -d "$dir" ]; then echo "skip: $dir not found"; return; fi
  for s in "$@"; do
    if [ "$check" = 1 ]; then
      if ! diff -r -q "$here/$s" "$dir/skills/$s" >/dev/null 2>&1; then
        echo "differs: $dir/skills/$s"; status=1
      fi
    else
      rm -rf "$dir/skills/$s"
      mkdir -p "$dir/skills"
      cp -R "$here/$s" "$dir/skills/$s"
      echo "synced: $dir/skills/$s"
    fi
  done
}

ship jolt-nrepl-mcp jolt-nrepl clj-refactor
ship jolt-kimi-plugin jolt-nrepl jolt-lsp clj-refactor
exit $status
