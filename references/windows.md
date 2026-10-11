# Windows installation and operation

## Design

Version 2.2.1 uses a .NET Framework tray application. It injects `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `WS_PROXY`, `WSS_PROXY`, and `NO_PROXY` only into Codex Desktop launched by the tray. It restores legacy managed user variables on migration, exit, or uninstall, and never enables user-level proxy variables.

Two independent checked menu options control proxy Windows login startup and launch-Codex-on-start (default true, persisted in config.ini). At startup the bridge begins listening, allows Clash up to 30 seconds to start, then launches Codex. `--launch` explicitly launches Codex; `--no-launch` suppresses automatic launch for maintenance. Crash recovery restarts the proxy with its configured launch behavior. No 15-second read timeout remains after CONNECT setup.

During installation, disable Codex/ChatGPT's own login startup when its entry is positively identified, or instruct the user to disable it in Windows Settings → Apps → Startup and in the app if offered. Keep Clash startup and proxy startup enabled. An already-running Codex instance does not acquire new environment variables; fully quit it and reopen from the proxy tray after migration.

The installer detects `respect_system_proxy` support and disables this experimental feature in effective `CODEX_HOME`, retaining the prior value for uninstall restoration. This prevents system-proxy preference from overriding process bridge settings for model/plugin requests; it does not modify the OS or main Clash system proxy. Launch through the tray: ordinary app-icon launches are not guaranteed to use the bridge. Store application paths are rediscovered if an update invalidates the configured desktop executable. CLI executables are excluded.

A separate watcher handles unexpected exits and limits repeated restarts. Neither it nor the main process needs user-level proxy variables. Existing other applications must be restarted once after migrating away from old environment values.

Auto probes https://chatgpt.com/backend-api/codex/responses using HEAD with normal certificate validation. Direct requires three consecutive successful TLS/HTTP probes (including normal unauthenticated HTTP 405); a Direct tunnel closed within five seconds with uploaded bytes but no downloaded bytes triggers a 120-second cooldown. PreferClash=true makes Auto prefer the configured Clash endpoint. These heuristics do not guarantee login, model availability, or freedom from retries. Once CONNECT is established, do not replay TLS or business requests to switch routes.

## Install

Double-click `setup-windows.cmd`. The graphical installer lets the user select:

- the native Codex executable for the optional tray **启动 Codex** command, or automatic discovery;
- Clash Verge's mixed port;
- whether the tray should start with Windows;
- whether starting the proxy also launches Codex (enabled by default).

For command-line installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1
```

Optional parameters:

```powershell
.\scripts\windows\install.ps1 -CodexExe "C:\path\to\Codex.exe" -ClashPort 7897 -StartWithWindows
```

## Installed layout

- Application: `%LOCALAPPDATA%\CodexAutoProxy`
- Per-user startup: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexAutoProxy`
- Installed apps entry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexAutoProxy`
- Uninstaller: `%LOCALAPPDATA%\CodexAutoProxy\uninstall.cmd`
- Local bridge: `127.0.0.1:7898`

No administrator permission is required. The package includes `bin\windows\CodexAutoProxy.exe`, a small .NET Framework 4.8 Windows GUI executable compiled from the bundled C# source. The installer uses it directly and retains `build.ps1` as a source-build fallback. The executable is unsigned.

## Status

Run `%LOCALAPPDATA%\CodexAutoProxy\status.cmd` or:

```powershell
.\scripts\windows\status.ps1
```

## Configure

Right-click the tray icon and open **设置 Clash 端口…**. The window saves the new mixed port and the Windows startup preference. New connections use the new port immediately.

Upgrades preserve existing ports, startup options, PreferClash, and managed upstream paths. If a dedicated route is active, disable it before changing only its upstream port.

## Optional dedicated node

After testing the user's own nodes and obtaining authorization, run:

```powershell
& "$env:LOCALAPPDATA\CodexAutoProxy\configure-dedicated-route.ps1" -NodeName "USER'S TESTED NODE NAME"
```

The script extracts one local independent node and borrows installed mihomo to create a tray-managed loopback instance, normally on port 17897. It disables TUN in that instance, binds a physical interface, and leaves the main Clash selector, TUN, and OS proxy unchanged. Optional parameters are -ClashConfig, -CorePath, -InterfaceAlias, and -Port. Dynamic-provider or dialer-dependent nodes cannot necessarily be exported directly.

config.ini records PreferClash=true, UpstreamExe, UpstreamConfig, and the dedicated ClashPort. managed-upstream.pid records PID, UTC start ticks, and config path; verify all three against the process before identifying it as managed. Never identify or stop an unrelated mihomo process by name alone.

The private dedicated-route directory contains credentials and YAML backups. Keep it local and outside release packages/Git. Reconfigure after subscription/node credentials or physical-interface changes; borrowed core paths may also change after Clash updates. Roll back route settings with:

```powershell
& "$env:LOCALAPPDATA\CodexAutoProxy\configure-dedicated-route.ps1" -Disable
```

This restarts the bridge without closing Codex; active requests may briefly disconnect. It restores saved route settings, not unrelated startup changes. Read status without printing private YAML. A dedicated node is optional and does not promise to fix server load, account issues, or every reconnect.

## Uninstall

Use Windows **Installed apps**, the Start Menu uninstall entry, or `%LOCALAPPDATA%\CodexAutoProxy\uninstall.cmd`. The uninstaller restores the feature setting if this installer changed it, stops the tray, restores proxy environment variables, cleans legacy `.env` blocks and per-user entries, and deletes the installed directory. When upgrading from an older package that redirected shortcuts, legacy backups are restored first.
