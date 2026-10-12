#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="$root/bin/macos"
mkdir -p "$out"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" "$root/scripts/macos/FoxCodexProxy.swift" -o "$stage/$arch"
done
lipo -create "$stage/arm64" "$stage/x86_64" -output "$out/fox-codex-proxy"
codesign --force --sign - "$out/fox-codex-proxy"
(cd "$out" && shasum -a 256 fox-codex-proxy > SHA256SUMS.txt)
file "$out/fox-codex-proxy"
