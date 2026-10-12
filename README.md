# FoxCodexProxy

给 Codex 桌面应用使用的本地代理工具。当前正式发布包：**v2.3.0**，包含 Windows v2.2.1 托盘运行程序和 macOS v2.3.0 原生自动代理。macOS 无托盘、保留原图标。正式发布不表示已解决所有连接重试。

软件回归测试已通过，但持续端到端稳定性尚未验证：后续测试中，曾短期连续通过的节点也出现 TCP 超时。请勿把本版理解为已消除重连；专用节点仅在你自己的重复真实请求验证通过后启用。

这是第三方辅助工具，不是 OpenAI 官方产品。不需要管理员权限，不安装证书，不修改 Windows 全局代理，也不设置用户级代理环境变量。

## macOS 安装与使用

从 [v2.3.0 Releases](https://github.com/Foxing365/FoxCodexProxy/releases/tag/v2.3.0) 下载 `FoxCodexProxy-macOS-v2.3.0.zip`，完整解压后双击 `setup-macos.command`，核对检测到的 Clash 端口即可安装。状态和卸载分别双击包内 `status-macos.command`、`uninstall-macos.command`。

希望 AI 处理端口核对和旧代理迁移：下载 `fox-codex-proxy-skill-v2.3.0.zip`，让 agent 读取 `SKILL.md` 并安装；安装 skill 本身不等于安装代理。

macOS 13+，支持 Apple Silicon / Intel。系统 launchd 仅保留回环 socket；Codex 连接时启动 helper，所有连接结束 30 秒后退出，不添加登录常驻程序。保留原图标和 WSS，不需要 Python。

```sh
./scripts/macos/build.sh
./packaging/build-macos-release.sh
# 在安装包完整解压后，核对 Clash 端口再安装
./bin/macos/fox-codex-proxy --install --clash-port 7897 --port 7898
```

安装到本地 Application Support，不从 OneDrive 长期运行。安装/卸载的配置保护、未签名公证限制和验证边界见 [macOS 使用说明](references/macos.md)。实际方案与 GitHub 项目的比较见 [研究记录](references/macos-comparison.md)：使用体验更符合我们的需求，尚无证据证明稳定性更优。构建和下载不会自动替换本机旧代理，安装时运行中的服务会安全拒绝升级。

## Windows 下载安装

打开 [Releases](https://github.com/Foxing365/FoxCodexProxy/releases/tag/v2.3.0)，选择一种方式：

- 普通用户：下载 `FoxCodexProxy-Setup-v2.2.1.exe`，双击后按安装窗口操作。
- ZIP 安装：下载 `FoxCodexProxy-Windows-v2.2.1.zip`，先完整解压，再双击 `setup-windows.cmd`。
- AI agent：下载 `fox-codex-proxy-skill-v2.3.0.zip`，解压给 agent，要求它读取 `SKILL.md` 并在本机安装。也可以让 agent 从本仓库根目录安装 skill，名称使用 `fox-codex-proxy`。

需要 Windows 10/11、.NET Framework 4.8 和已安装的 Codex 桌面应用。无法直连时还需要可用的 Clash Verge 节点；默认 Clash mixed port 为 `7897`，桥接端口为 `7898`，可按本机设置修改。代理端口和桥接端口不能相同。

安装器未经代码签名，Windows 可能提示未知发布者。单文件 EXE 是自解压启动器：在临时目录展开本仓库的 Windows 安装文件，显示相同的安装窗口，不会自动提权。

## 日常使用

安装后，完全退出已经打开的 Codex，再从代理托盘菜单的“启动 Codex”打开一次。代理参数只传给这样启动的 Codex，不会影响其他应用。

托盘有两个独立的勾选项：

- “随 Windows 登录启动代理”。
- “代理启动时同时启动 Codex”，默认开启。

建议两项都开启，并关闭 **Codex/ChatGPT 自己的开机自启**（Windows 设置 → 应用 → 启动；应用内有登录启动选项也应关闭），保留 Clash Verge 自启。这样先启动桥接，再启动 Codex，避免 Codex 抢先启动而没有继承桥接参数。安装窗口也会提醒这一步。

程序启动时先监听桥接端口，最多等待 Clash 30 秒再启动 Codex；Clash 尚未可用时连接仍可能失败，启动 Clash 后重试即可。托盘可选择 Auto、Direct、Clash；Auto 根据连通性探测选择路由，启用 Clash TUN 时，“Direct”不代表绕过 TUN。

Auto 用 Codex 实际响应接口的 HEAD 请求检测 TLS 连通性，连续通过三次才采用 Direct；直连隧道在 5 秒内上传数据却未收到任何数据便关闭时，进入 120 秒冷却。`config.ini` 的 `PreferClash=true` 可让 Auto 优先使用指定 Clash 出口，不再因直连探测偶然成功而跳回 Direct。HTTP 405 等正常响应只说明 TLS/HTTP 可达，不等于登录成功。

Auto 可在路线建立失败时尝试另一条路线，但 CONNECT 建立后的 TLS/业务失败不会在同一隧道内换线或重放请求。托盘路线和状态表示探测结果，不等于账户登录或模型请求一定成功。

每次启动 Codex 都会重新查询当前注册的 Store 安装版本，避免正常更新后路径失效；非 Store 安装可在安装窗口指定桌面 EXE。不要选择 `bin` 目录中的 Codex CLI。未来 Codex 若改变代理支持或启动接口，仍可能需要更新本工具。

请从托盘启动 Codex；从原图标启动不保证经过本工具。安装器检测 CLI 支持时关闭实验性 `respect_system_proxy`，防止系统代理优先覆盖进程桥接，让模型和插件请求遵循同一个进程出口。原设置会保存，卸载时按备份恢复；主 Clash/Windows 系统代理本身不作修改。

## 状态与卸载

安装到 `%LOCALAPPDATA%\CodexAutoProxy`，配置、日志和状态也在该目录。开始菜单有启动、状态检查和卸载入口；也可在 Windows“已安装的应用”中卸载 Codex Auto Proxy。

升级会保留已有端口、启动选项和专用出口配置；安装窗口可核对或调整选项。已启用专用出口时，不能只修改出口端口，应先按下文停用专用出口。

工具保留 CONNECT 长连接，不再使用旧版的 15 秒空闲超时，并有异常退出守护。它不能解决节点失效、上游 TLS 中断、服务端拥挤、账户认证问题，也不保证消除所有“重试 5 次”。旧版遗留用户级代理变量会按原备份恢复；迁移后其他已运行的应用可能需要重启一次。

连接诊断记录路线、端口、异常类型、持续时间和字节数，每分钟最多 10 条详细网络记录。不记录目标 URL、请求头、令牌或对话内容；快速关闭记录也可能是正常连接结束，并不单独证明 TLS 故障。

## 可选：Codex 专用稳定节点

如果当前 Clash 节点对 Codex 经常出现 TLS 握手失败，可先分别测试自己订阅中的节点，再为 Codex 单独选一个稳定节点，不需要改变其他应用正在使用的主节点：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexAutoProxy\configure-dedicated-route.ps1" -NodeName "你自己已实测稳定的节点名称"
```

工具借用本机已安装的 mihomo 内核启动独立实例，默认专用端口 `17897`，不启用 TUN、不接管系统代理、不切换主 Clash 节点。托盘管理这个实例，并通过 `PreferClash=true` 使用专用出口。节点名称应来自你自己的本机配置，不要照抄别人的；动态 provider 或依赖其他出口的节点可能不能直接导出。

节点凭据仅保存在本机 `%LOCALAPPDATA%\CodexAutoProxy\dedicated-route`；不要上传这个目录、备份 YAML 或任何订阅/凭据到公开仓库。订阅更新、节点凭据变化、网卡名称/网络切换后，需要重新运行配置命令；可用 `-InterfaceAlias "网卡名称"`、`-CorePath "内核路径"`、`-ClashConfig "本机配置路径"` 指定实际环境。

停用并恢复配置前的普通 Clash 出口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexAutoProxy\configure-dedicated-route.ps1" -Disable
```

配置命令会重启桥接，不关闭当前 Codex，但进行中的连接可能短暂中断。专用出口仍不能修复服务端错误，也不保证消灭全部重试。

## 同类参考

[Codex-Connectivity](https://github.com/zhenyangLab/Codex-Connectivity) 和 [codex-app-proxy](https://github.com/leisair/codex-app-proxy) 也可作为排障参考。本项目已具备进程级代理注入与动态 Store 路径发现，未复制这些项目的代码。HTTP/HTTPS/ALL 及 WS/WSS 代理变量仅传给托盘启动的 Codex 子进程。

## 从源码构建

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1 -OutputDirectory .\bin\windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\build-release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

发布产物位于 `dist/`，包含 EXE 安装器、Windows ZIP、skill ZIP 和 SHA-256 校验文件。Windows EXE/ZIP 沿用 v2.2.1 已构建产物，Windows runtime 未改变；macOS 和统一 skill 为 v2.3.0。安装器源码为 `packaging/SetupLauncher.cs`，托盘源码为 `scripts/windows/CodexAutoProxy.cs`。构建不需要下载第三方打包器。
