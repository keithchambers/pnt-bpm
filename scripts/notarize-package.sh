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

if ! signature_output="$(/usr/sbin/pkgutil --check-signature "$package" 2>&1)"; then
  echo "$signature_output" >&2
  exit 1
fi
echo "$signature_output" | grep -q "Developer ID Installer:" || {
  echo "Package must be signed with a Developer ID Installer certificate before notarization." >&2
  exit 1
}

notary_args=()
if [[ -n "${PNT_CLI_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  notary_args+=(--keychain-profile "$PNT_CLI_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${PNT_CLI_NOTARY_KEY_PATH:-}" || -n "${PNT_CLI_NOTARY_KEY_ID:-}" || -n "${PNT_CLI_NOTARY_ISSUER_ID:-}" ]]; then
  : "${PNT_CLI_NOTARY_KEY_PATH:?PNT_CLI_NOTARY_KEY_PATH is required.}"
  : "${PNT_CLI_NOTARY_KEY_ID:?PNT_CLI_NOTARY_KEY_ID is required.}"
  : "${PNT_CLI_NOTARY_ISSUER_ID:?PNT_CLI_NOTARY_ISSUER_ID is required.}"
  notary_args+=(
    --key "$PNT_CLI_NOTARY_KEY_PATH"
    --key-id "$PNT_CLI_NOTARY_KEY_ID"
    --issuer "$PNT_CLI_NOTARY_ISSUER_ID"
  )
elif [[ -n "${PNT_CLI_NOTARY_APPLE_ID:-}" || -n "${PNT_CLI_NOTARY_PASSWORD:-}" || -n "${PNT_CLI_NOTARY_TEAM_ID:-}" ]]; then
  : "${PNT_CLI_NOTARY_APPLE_ID:?PNT_CLI_NOTARY_APPLE_ID is required.}"
  : "${PNT_CLI_NOTARY_PASSWORD:?PNT_CLI_NOTARY_PASSWORD is required.}"
  : "${PNT_CLI_NOTARY_TEAM_ID:?PNT_CLI_NOTARY_TEAM_ID is required.}"
  notary_args+=(
    --apple-id "$PNT_CLI_NOTARY_APPLE_ID"
    --password "$PNT_CLI_NOTARY_PASSWORD"
    --team-id "$PNT_CLI_NOTARY_TEAM_ID"
  )
else
  echo "No notarization credentials configured." >&2
  exit 1
fi

/usr/bin/xcrun notarytool submit "${notary_args[@]}" --wait "$package"
/usr/bin/xcrun stapler staple "$package"
/usr/bin/xcrun stapler validate "$package"

echo "Notarized and stapled $package"
