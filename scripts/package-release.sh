#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^public let pntBpmVersion = "\(.*\)"$/\1/p' Sources/PntBpmCore/CLI.swift)"
if [[ -z "$version" ]]; then
  echo "Could not determine pnt-bpm version." >&2
  exit 1
fi

arch="$(uname -m)"
package_name="pnt-bpm-${version}-macos-${arch}"
package_dir="dist/$package_name"

swift test
swift build -c release

rm -rf "$package_dir" "$package_dir.zip"
mkdir -p "$package_dir"

cp ".build/release/pnt-bpm" "$package_dir/pnt-bpm"
cp "scripts/install.sh" "$package_dir/install.sh"
cp "README.md" "$package_dir/README.md"
cp "LICENSE" "$package_dir/LICENSE"
chmod +x "$package_dir/pnt-bpm" "$package_dir/install.sh"

cat > "$package_dir/README.txt" <<README
pnt-bpm $version

Install:
  ./install.sh

Verify Serato Pitch n' Time LE can be loaded:
  pnt-bpm --doctor --verbose

Usage:
  pnt-bpm song.aiff --source 120 --target 125,128

Serato Pitch n' Time LE must be installed and licensed separately.
README

(
  cd dist
  /usr/bin/zip -r -X "$package_name.zip" "$package_name" >/dev/null
)

echo "Created dist/$package_name.zip"
