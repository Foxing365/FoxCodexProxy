#!/bin/sh
set -eu
helper="$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy"
if ! test -x "$helper"; then
    printf '没有找到已安装的 FoxCodexProxy。\n' >&2
    exit 1
fi
printf '请先结束任务、退出 Codex 并等待旧代理退出。\n'
"$helper" --uninstall
