#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^public let pntCliVersion = "\(.*\)"$/\1/p' Sources/PntCliCore/CLI.swift)"
if [[ -z "$version" ]]; then
  echo "Could not determine pnt-cli version." >&2
  exit 1
fi

package="${1:-dist/pnt-cli-${version}.pkg}"
if [[ ! -f "$package" ]]; then
  echo "Release package not found: $package" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [[ "${PNT_CLI_REQUIRE_SIGNED_PKG:-0}" = "1" ]]; then
  if ! signature_output="$(/usr/sbin/pkgutil --check-signature "$package" 2>&1)"; then
    echo "$signature_output" >&2
    exit 1
  fi
  echo "$signature_output" | grep -q "Developer ID Installer:"
  echo "$signature_output" | grep -q "Status: signed by a certificate trusted by Mac OS X"
fi

/usr/sbin/pkgutil --expand-full "$package" "$tmpdir/expanded" >/dev/null
pkg_id="$(/usr/bin/sed -n 's/.*identifier="\([^"]*\)".*/\1/p' "$tmpdir/expanded/PackageInfo")"
test "$pkg_id" = "com.keithchambers.pnt-cli"

binary="$tmpdir/expanded/Payload/usr/local/bin/pnt-cli"
test -x "$binary"
file "$binary" | grep -q "arm64"
file "$binary" | grep -q "x86_64"
test "$("$binary" --version)" = "$version"

if [[ "${PNT_CLI_REQUIRE_SIGNED_BINARY:-0}" = "1" ]]; then
  /usr/bin/codesign --verify --verbose=2 "$binary"
  /usr/bin/codesign -dv "$binary" 2>&1 | grep -q "Authority=Developer ID Application:"
  /usr/bin/codesign -d --entitlements :- "$binary" 2>/dev/null | grep -q "com.apple.security.cs.disable-library-validation"
fi

if [[ "${PNT_CLI_REQUIRE_NOTARIZED_PKG:-0}" = "1" ]]; then
  /usr/bin/xcrun stapler validate "$package"
  /usr/sbin/spctl -a -vv --type install "$package"
fi

echo "Verified $package"
