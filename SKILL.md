---
name: fox-codex-proxy
description: Install, inspect, repair, configure, or remove FoxCodexProxy for Codex Desktop on Windows or macOS. Windows uses a tray launcher; macOS uses an on-demand native launchd bridge with the original app icon.
---

# FoxCodexProxy

Version: 2.2.1. Windows release and native macOS preview.

Choose the host platform. On macOS read [references/macos.md](references/macos.md), use the bundled universal `bin/macos/fox-codex-proxy`, and install only when requested with `--install`. Preserve original-icon launches, WSS, and on-demand launchd activation; do not add a tray, login watcher, KeepAlive, RunAtLoad, global proxy, or new model provider. Run `--status` and a fresh `--check`, then verify a real Codex response separately. Active-service upgrades stop safely; do not kill running tasks to continue. Source build: `scripts/macos/build.sh`. See [macOS comparisons](references/macos-comparison.md) for evidence and limitations.

The instructions below are Windows-specific. Read [references/windows.md](references/windows.md) before Windows operations. Do not run Windows installers on macOS, Linux or WSL.

Installation of this agent skill only makes the instructions available; it does not install the tray application or enable startup. When the user asks to install the proxy, run the application installer too.

## Install

Use the bundled `bin/windows/CodexAutoProxy.exe`; build from `scripts/windows/build.ps1` only when missing or when asked to rebuild. With authorization to install the application, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1 -StartWithWindows
```

Detect Clash's mixed port or use `-ClashPort` for the user's port. The default bridge port is 7898; it must differ from the Clash port. Resolve Codex Desktop, not a CLI from a `bin` directory. The graphical alternative is `setup-windows.cmd`.

Keep the proxy startup and launch-Codex-on-start options enabled unless the user chooses otherwise. These are independent persistent tray checkboxes. During installation, identify Codex/ChatGPT's own startup entry and disable it if accessible and positively identified; otherwise instruct the user to turn it off in Windows Settings → Apps → Startup and the app's login-start setting if present. Do not disable Clash startup or unrelated entries. Explain that independent Codex startup can race ahead of the bridge.

Do not close an active Codex session during installation or upgrade. Ask the user to fully quit and reopen Codex from the proxy tray afterward. An already-running process does not acquire new proxy parameters.

## Constraints and verification

- Bind only to 127.0.0.1; inject proxy variables only into Codex launched by the tray. Never set new user-level proxy variables, modify global OS proxy settings, retarget Codex shortcuts, or install TLS certificates.
- Preserve unrelated settings. Legacy managed proxy values are restored from saved backups. Existing applications may need restarting after migration.
- When supported by the local CLI, the installer disables experimental `respect_system_proxy` so system proxy preference does not override process-scoped bridge settings for model/plugin requests. It saves the previous feature value for uninstall restoration. Do not change the OS/main Clash system proxy. Use the tray launch; ordinary app-icon launches are not guaranteed to use this bridge.
- Confirm the listener and a TLS request through it, and inspect fresh status/route evidence. HTTP reachability does not prove account login or eliminate service errors.
- Verify a newly opened Codex session when practical; if keeping the current session open, disclose that end-to-end relaunch remains for the user.
- Auto-mode direct probing may still be intercepted by Clash TUN. Do not promise that all reconnects disappear or that every future Codex update remains compatible.

## Optional dedicated route

PreferClash=true in installed config.ini makes Auto prefer the configured Clash endpoint. Auto otherwise probes the actual Codex responses endpoint using HEAD, requires three consecutive successful TLS/HTTP probes before Direct, and cools Direct down for 120 seconds after an early empty tunnel close. These are health heuristics, not account verification or a guarantee against retries. Do not replay TLS/application requests inside an established tunnel.

When the user authorizes a dedicated route, test nodes from that user's local subscription first, then run the installed script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexAutoProxy\configure-dedicated-route.ps1" -NodeName "USER'S TESTED NODE NAME"
```

This borrows the already-installed mihomo executable for an isolated loopback instance, without changing the main Clash selector, TUN, or system proxy. The default dedicated port is 17897. Node names are machine-specific; never hard-code the developer's node. Dynamic providers or nodes depending on other proxies need separate inspection. Use -ClashConfig, -CorePath, or -InterfaceAlias when discovery does not match the host.

Private YAML and backups stay under LOCALAPPDATA\CodexAutoProxy\dedicated-route and must never be published, logged, or copied into the skill/repository. Reconfigure after subscription credentials, node definitions, or the physical network interface change. To roll back only the route settings, run the same script with -Disable; the bridge restarts without closing Codex, but active connections can briefly disconnect. Upgrades preserve ports, startup options, and dedicated-route settings.

HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, WS_PROXY, WSS_PROXY, and NO_PROXY are process-scoped. Inspect config.ini, status.json, and verified managed PID evidence only; never print the private YAML. Do not call the network stable solely because a port listens or an unauthenticated HEAD returns HTTP 405; verify repeated TLS tests, long-lived connections, and a real Codex turn separately.

Read-only inspection does not authorize installation, repair, or removal. Follow the user's requested action; use the installed `status.cmd` or `uninstall.cmd` for those operations.
