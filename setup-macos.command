#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$root/bin/macos/fox-codex-proxy"
# Agents pass explicit arguments and never receive interactive prompts.
if test "$#" -gt 0; then
    exec "$helper" --install "$@"
fi
printf 'FoxCodexProxy macOS 自动安装\n无需托盘或特殊图标。请先结束 Codex 任务并完全退出应用。\n'
port=$("$helper" --detect-clash-port)
if test -t 0; then
    printf 'Clash mixed port（检测/已有配置为 %s，回车保留）：' "$port"
    read -r selected
    if test -n "$selected"; then port="$selected"; fi
fi
if "$helper" --install --clash-port "$port"; then
    printf '\n安装成功。从原图标重新打开 Codex 即可。状态和卸载见 README。\n'
else
    printf '\n安装未完成。若旧代理仍在运行，请退出 Codex 并等待 30 秒再试。\n' >&2
    exit 1
fi
