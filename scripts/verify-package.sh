#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "Verification failed: $*" >&2
  exit 1
}

require_equal() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

require_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if ! grep -q "$needle" <<< "$haystack"; then
    echo "$haystack" >&2
    fail "$description: missing '$needle'"
  fi
}

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
  echo "$signature_output"
  require_contains "$signature_output" "Developer ID Installer:" "Package signature"
  require_contains "$signature_output" "Status: signed" "Package signature"
  require_contains "$signature_output" "trusted" "Package signature"
fi

/usr/sbin/pkgutil --expand-full "$package" "$tmpdir/expanded" >/dev/null
pkg_id="$(/usr/bin/sed -n 's/.*identifier="\([^"]*\)".*/\1/p' "$tmpdir/expanded/PackageInfo")"
echo "Package identifier: $pkg_id"
require_equal "$pkg_id" "com.keithchambers.pnt-cli" "Package identifier"

binary="$tmpdir/expanded/Payload/usr/local/bin/pnt-cli"
if [[ ! -x "$binary" ]]; then
  find "$tmpdir/expanded" -maxdepth 4 -type f >&2
  fail "Expected executable not found at Payload/usr/local/bin/pnt-cli"
fi

file_output="$(file "$binary")"
echo "$file_output"
require_contains "$file_output" "arm64" "Release binary architecture"
require_contains "$file_output" "x86_64" "Release binary architecture"

binary_version="$("$binary" --version)"
echo "Binary version: $binary_version"
require_equal "$binary_version" "$version" "Release binary version"

if [[ "${PNT_CLI_REQUIRE_SIGNED_BINARY:-0}" = "1" ]]; then
  /usr/bin/codesign --verify --verbose=2 "$binary"
  codesign_output="$(/usr/bin/codesign -dvvv "$binary" 2>&1)"
  echo "$codesign_output"
  require_contains "$codesign_output" "Authority=Developer ID Application:" "Release binary signature"

  entitlements_output="$(/usr/bin/codesign -d --entitlements :- "$binary" 2>/dev/null)"
  echo "$entitlements_output"
  require_contains "$entitlements_output" "com.apple.security.cs.disable-library-validation" "Release binary entitlements"
fi

if [[ "${PNT_CLI_REQUIRE_NOTARIZED_PKG:-0}" = "1" ]]; then
  /usr/bin/xcrun stapler validate "$package"
  /usr/sbin/spctl -a -vv --type install "$package"
fi

echo "Verified $package"
