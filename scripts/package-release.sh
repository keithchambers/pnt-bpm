#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^public let pntBpmVersion = "\(.*\)"$/\1/p' Sources/PntBpmCore/CLI.swift)"
if [[ -z "$version" ]]; then
  echo "Could not determine pnt-bpm version." >&2
  exit 1
fi

pkg_name="pnt-bpm-${version}.pkg"
payload_dir="dist/pkgroot"
binary_path=".build/apple/Products/Release/pnt-bpm"
entitlements_path="${PNT_BPM_CODESIGN_ENTITLEMENTS:-scripts/pnt-bpm.entitlements.plist}"
app_sign_identity="${PNT_BPM_APP_SIGN_IDENTITY:-}"
pkg_sign_identity="${PNT_BPM_PKG_SIGN_IDENTITY:-}"
signing_keychain="${PNT_BPM_SIGNING_KEYCHAIN:-}"

if [[ "${PNT_BPM_REQUIRE_SIGNING:-0}" = "1" ]]; then
  if [[ -z "$app_sign_identity" ]]; then
    echo "PNT_BPM_APP_SIGN_IDENTITY is required when PNT_BPM_REQUIRE_SIGNING=1." >&2
    exit 1
  fi
  if [[ -z "$pkg_sign_identity" ]]; then
    echo "PNT_BPM_PKG_SIGN_IDENTITY is required when PNT_BPM_REQUIRE_SIGNING=1." >&2
    exit 1
  fi
fi

swift test
swift build -c release --arch arm64 --arch x86_64

if [[ -n "$app_sign_identity" ]]; then
  if [[ ! -f "$entitlements_path" ]]; then
    echo "Code signing entitlements not found: $entitlements_path" >&2
    exit 1
  fi

  codesign_args=(
    --force
    --sign "$app_sign_identity"
    --identifier "com.keithchambers.pnt-bpm"
    --options runtime
    --entitlements "$entitlements_path"
    --timestamp
  )
  if [[ -n "$signing_keychain" ]]; then
    codesign_args+=(--keychain "$signing_keychain")
  fi

  /usr/bin/codesign "${codesign_args[@]}" "$binary_path"
fi

rm -rf "$payload_dir" "dist/$pkg_name"
mkdir -p "$payload_dir/usr/local/bin"

cp "$binary_path" "$payload_dir/usr/local/bin/pnt-bpm"
chmod 0755 "$payload_dir/usr/local/bin/pnt-bpm"

pkgbuild_args=(
  --root "$payload_dir"
  --identifier "com.keithchambers.pnt-bpm"
  --version "$version"
  --install-location "/"
)
if [[ -n "$pkg_sign_identity" ]]; then
  pkgbuild_args+=(--sign "$pkg_sign_identity" --timestamp)
  if [[ -n "$signing_keychain" ]]; then
    pkgbuild_args+=(--keychain "$signing_keychain")
  fi
fi

/usr/bin/pkgbuild "${pkgbuild_args[@]}" "dist/$pkg_name"

echo "Created dist/$pkg_name"
