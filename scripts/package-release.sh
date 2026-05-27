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

swift test
swift build -c release --arch arm64 --arch x86_64

rm -rf "$payload_dir" "dist/$pkg_name"
mkdir -p "$payload_dir/usr/local/bin"

cp "$binary_path" "$payload_dir/usr/local/bin/pnt-bpm"
chmod 0755 "$payload_dir/usr/local/bin/pnt-bpm"

/usr/bin/pkgbuild \
  --root "$payload_dir" \
  --identifier "com.keithchambers.pnt-bpm" \
  --version "$version" \
  --install-location "/" \
  "dist/$pkg_name"

echo "Created dist/$pkg_name"
