#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^public let pntBpmVersion = "\(.*\)"$/\1/p' Sources/PntBpmCore/CLI.swift)"
if [[ -z "$version" ]]; then
  echo "Could not determine pnt-bpm version." >&2
  exit 1
fi

package="${1:-dist/pnt-bpm-${version}.pkg}"
if [[ ! -f "$package" ]]; then
  echo "Release package not found: $package" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

/usr/sbin/pkgutil --expand-full "$package" "$tmpdir/expanded" >/dev/null
pkg_id="$(/usr/bin/sed -n 's/.*identifier="\([^"]*\)".*/\1/p' "$tmpdir/expanded/PackageInfo")"
test "$pkg_id" = "com.keithchambers.pnt-bpm"

binary="$tmpdir/expanded/Payload/usr/local/bin/pnt-bpm"
test -x "$binary"
file "$binary" | grep -q "arm64"
file "$binary" | grep -q "x86_64"
test "$("$binary" --version)" = "$version"

echo "Verified $package"
