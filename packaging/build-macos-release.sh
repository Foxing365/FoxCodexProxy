#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=2.2.1
maczip="$root/dist/FoxCodexProxy-macOS-v$version-preview.zip"
skillzip="$root/dist/fox-codex-proxy-skill-v$version-macos-preview.zip"
mkdir -p "$root/dist"
if test -e "$maczip" || test -e "$skillzip"; then
  echo 'Output already exists; archive it before rebuilding.' >&2
  exit 1
fi
(cd "$root/bin/macos" && shasum -a 256 -c SHA256SUMS.txt)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
mac="$stage/FoxCodexProxy-macOS"
mkdir -p "$mac/bin" "$mac/scripts" "$mac/references"
cp -R "$root/bin/macos" "$mac/bin/"
cp -R "$root/scripts/macos" "$mac/scripts/"
cp "$root/setup-macos.command" "$mac/"
cp "$root/references/macos.md" "$mac/README.md"
cp "$root/references/macos-comparison.md" "$mac/references/"
ditto -c -k --keepParent "$mac" "$maczip"
skill="$stage/fox-codex-proxy"
mkdir -p "$skill"
for item in scripts bin references SKILL.md AI_GUIDE.md README.md CHANGELOG.md setup-windows.cmd setup-macos.command; do
  cp -R "$root/$item" "$skill/"
done
ditto -c -k --keepParent "$skill" "$skillzip"
(cd "$root/dist" && shasum -a 256 "$(basename "$maczip")" "$(basename "$skillzip")" > SHA256SUMS-macOS-v$version.txt)
echo "$maczip"
echo "$skillzip"
