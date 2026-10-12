#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$root/bin/macos/fox-codex-proxy" --install "$@"
printf '\n安装结束。请从原图标重新打开 Codex。\n'
