# FoxCodexProxy

给 Windows 上的 Codex 桌面应用使用的本地代理桥接和托盘启动器。当前发布版本：**v2.2.0（仅 Windows）**。macOS 版暂不发布。

这是第三方辅助工具，不是 OpenAI 官方产品。不需要管理员权限，不安装证书，不修改 Windows 全局代理，也不设置用户级代理环境变量。

## 下载安装

打开 [Releases](https://github.com/Foxing365/FoxCodexProxy/releases/latest)，选择一种方式：

- 普通用户：下载 `FoxCodexProxy-Setup-v2.2.0.exe`，双击后按安装窗口操作。
- ZIP 安装：下载 `FoxCodexProxy-Windows-v2.2.0.zip`，先完整解压，再双击 `setup-windows.cmd`。
- AI agent：下载 `fox-codex-proxy-skill-v2.2.0.zip`，解压给 agent，要求它读取 `SKILL.md` 并在本机安装。也可以让 agent 从本仓库根目录安装 skill，名称使用 `fox-codex-proxy`。

需要 Windows 10/11、.NET Framework 4.8 和已安装的 Codex 桌面应用。无法直连时还需要可用的 Clash Verge 节点；默认 Clash mixed port 为 `7897`，桥接端口为 `7898`，可按本机设置修改。代理端口和桥接端口不能相同。

安装器未经代码签名，Windows 可能提示未知发布者。单文件 EXE 是自解压启动器：在临时目录展开本仓库的 Windows 安装文件，显示相同的安装窗口，不会自动提权。

## 日常使用

安装后，完全退出已经打开的 Codex，再从代理托盘菜单的“启动 Codex”打开一次。代理参数只传给这样启动的 Codex，不会影响其他应用。

托盘有两个独立的勾选项：

- “随 Windows 登录启动代理”。
- “代理启动时同时启动 Codex”，默认开启。

建议两项都开启，并关闭 **Codex/ChatGPT 自己的开机自启**（Windows 设置 → 应用 → 启动；应用内有登录启动选项也应关闭），保留 Clash Verge 自启。这样先启动桥接，再启动 Codex，避免 Codex 抢先启动而没有继承桥接参数。安装窗口也会提醒这一步。

程序启动时先监听桥接端口，最多等待 Clash 30 秒再启动 Codex；Clash 尚未可用时连接仍可能失败，启动 Clash 后重试即可。托盘可选择 Auto、Direct、Clash；Auto 根据连通性探测选择路由，启用 Clash TUN 时，“Direct”不代表绕过 TUN。

Auto 可在路线建立失败时尝试另一条路线，但 CONNECT 建立后的 TLS/业务失败不会在同一隧道内换线或重放请求。托盘路线和状态表示探测结果，不等于账户登录或模型请求一定成功。

每次启动 Codex 都会重新查询当前注册的 Store 安装版本，避免正常更新后路径失效；非 Store 安装可在安装窗口指定桌面 EXE。不要选择 `bin` 目录中的 Codex CLI。未来 Codex 若改变代理支持或启动接口，仍可能需要更新本工具。

如果从原图标启动 Codex，可使用 Clash 系统代理作为备用方式（安装器会在 CLI 支持时启用 `respect_system_proxy`）。主要推荐托盘启动。

## 状态与卸载

安装到 `%LOCALAPPDATA%\CodexAutoProxy`，配置、日志和状态也在该目录。开始菜单有启动、状态检查和卸载入口；也可在 Windows“已安装的应用”中卸载 Codex Auto Proxy。

升级时请重新核对安装窗口的端口和两个启动选项；安装器会按本次选择重新生成配置，自定义桥接端口应通过命令行 `-ListenPort` 指定。

工具保留 CONNECT 长连接，不再使用旧版的 15 秒空闲超时，并有异常退出守护。它不能解决节点失效、上游 TLS 中断、服务端拥挤、账户认证问题，也不保证消除所有“重试 5 次”。旧版遗留用户级代理变量会按原备份恢复；迁移后其他已运行的应用可能需要重启一次。

连接诊断记录路线、端口、异常类型、持续时间和字节数，每分钟最多 10 条详细网络记录。不记录目标 URL、请求头、令牌或对话内容；快速关闭记录也可能是正常连接结束，并不单独证明 TLS 故障。

## 从源码构建

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1 -OutputDirectory .\bin\windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\build-release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

发布产物位于 `dist/`，包含 EXE 安装器、Windows ZIP、skill ZIP 和 SHA-256 校验文件。安装器源码为 `packaging/SetupLauncher.cs`，托盘源码为 `scripts/windows/CodexAutoProxy.cs`。构建不需要下载第三方打包器。
