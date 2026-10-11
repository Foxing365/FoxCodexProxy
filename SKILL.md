---
name: fox-codex-proxy
description: Install, inspect, repair, configure, or remove FoxCodexProxy for Codex Desktop on Windows, with a process-scoped direct-or-Clash bridge and tray launcher. macOS is not released in this version.
---

# FoxCodexProxy for Windows

Read [references/windows.md](references/windows.md) before installing or changing the proxy. This release supports native Windows only; do not run these installers on macOS, Linux, or WSL. macOS release is pending.

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
- The installer enables `respect_system_proxy` only when detected in the local CLI. This is an ordinary-launch fallback; the tray launch is the primary bridge entrypoint.
- Confirm the listener and a TLS request through it, and inspect fresh status/route evidence. HTTP reachability does not prove account login or eliminate service errors.
- Verify a newly opened Codex session when practical; if keeping the current session open, disclose that end-to-end relaunch remains for the user.
- Auto-mode direct probing may still be intercepted by Clash TUN. Do not promise that all reconnects disappear or that every future Codex update remains compatible.

Read-only inspection does not authorize installation, repair, or removal. Follow the user's requested action; use the installed `status.cmd` or `uninstall.cmd` for those operations.
