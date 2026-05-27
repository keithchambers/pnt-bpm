#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pnt-bpm is macOS-only (Serato Pitch n' Time LE is a macOS Audio Unit)." >&2
  exit 1
fi

install_dir="${PNT_BPM_INSTALL_DIR:-$HOME/.local/bin}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Install pnt-bpm.

Usage:
  scripts/install.sh
  PNT_BPM_INSTALL_DIR=/usr/local/bin scripts/install.sh

By default the binary is installed to ~/.local/bin.
USAGE
  exit 0
fi

candidates=(
  "$script_dir/pnt-bpm"
  "$script_dir/../pnt-bpm"
  "$PWD/.build/release/pnt-bpm"
)

binary=""
for candidate in "${candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    binary="$candidate"
    break
  fi
done

if [[ -z "$binary" ]]; then
  echo "pnt-bpm binary not found." >&2
  echo "Build first with: swift build -c release" >&2
  exit 1
fi

mkdir -p "$install_dir"
install -m 0755 "$binary" "$install_dir/pnt-bpm"

echo "Installed pnt-bpm to $install_dir/pnt-bpm"
if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  echo "Add this directory to PATH if needed:"
  echo "  export PATH=\"$install_dir:\$PATH\""
fi
