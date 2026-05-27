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

notary_timeout="${PNT_CLI_NOTARY_TIMEOUT:-45m}"

echo "Submitting $package to Apple notary service..."
submit_output="$(/usr/bin/xcrun notarytool submit "${notary_args[@]}" --output-format json "$package")"
echo "$submit_output"

submission_id="$(printf '%s' "$submit_output" | /usr/bin/plutil -extract id raw -o - -)"
if [[ -z "$submission_id" ]]; then
  echo "Could not determine Apple notary submission ID." >&2
  exit 1
fi

echo "Waiting up to $notary_timeout for Apple notary submission $submission_id..."
set +e
wait_output="$(/usr/bin/xcrun notarytool wait "${notary_args[@]}" --timeout "$notary_timeout" --output-format json "$submission_id" 2>&1)"
wait_status=$?
set -e
echo "$wait_output"

if (( wait_status != 0 )); then
  echo "Apple notarization did not complete successfully for submission $submission_id." >&2
  /usr/bin/xcrun notarytool info "${notary_args[@]}" --output-format json "$submission_id" >&2 || true
  /usr/bin/xcrun notarytool log "${notary_args[@]}" "$submission_id" >&2 || true
  exit "$wait_status"
fi

notary_status="$(printf '%s' "$wait_output" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
if [[ "$notary_status" != "Accepted" ]]; then
  echo "Apple notarization finished with unexpected status: ${notary_status:-unknown}" >&2
  /usr/bin/xcrun notarytool log "${notary_args[@]}" "$submission_id" >&2 || true
  exit 1
fi

/usr/bin/xcrun stapler staple "$package"
/usr/bin/xcrun stapler validate "$package"

echo "Notarized and stapled $package"
