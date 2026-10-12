#!/bin/sh
set -eu
helper="$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy"
if ! test -x "$helper"; then
    root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    helper="$root/bin/macos/fox-codex-proxy"
fi
"$helper" --status
