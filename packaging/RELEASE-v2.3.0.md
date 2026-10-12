# FoxCodexProxy v2.3.0

Windows + macOS 跨平台正式发布。**正式发布是分发渠道，不代表所有“五次重试”已消除。**

## 下载选择

| 使用场景 | 文件 |
|---|---|
| Windows 普通安装 | `FoxCodexProxy-Setup-v2.2.1.exe` |
| Windows 解压安装 | `FoxCodexProxy-Windows-v2.2.1.zip` |
| macOS 普通安装 | `FoxCodexProxy-macOS-v2.3.0.zip` |
| 任意有本地执行能力的 AI agent 辅助安装 | `fox-codex-proxy-skill-v2.3.0.zip` |
| 下载校验 | `SHA256SUMS-v2.3.0.txt` |

Windows runtime/安装器沿用已有 v2.2.1 已构建产物，内容与校验值不变；macOS 和统一 skill 为 v2.3.0。旧 Windows 预览包的历史 README 描述其当时状态，当前跨平台使用说明以本 Release 和仓库为准。

## macOS 怎么装最方便

1. 完整解压 macOS ZIP，结束 Codex 中进行的任务并完全退出应用。
2. 双击 `setup-macos.command`，核对自动检测到的 Clash 端口，回车保留或输入本机端口。
3. 安装完成后，从 Codex 原图标打开，日常自动使用；不需要托盘、菜单栏、专用图标、Python 或登录常驻监控。
4. 状态检查和卸载分别双击 `status-macos.command`、`uninstall-macos.command`。

Apple Silicon/Intel Universal 二进制，部署目标 macOS 13+。launchd 只保留回环 socket，连接时唤醒 helper，没有活跃连接后 30 秒退出。WSS 和原 provider 保留，不修改系统代理、不安装证书。

旧服务仍在运行时 installer 会拒绝升级；先结束任务并退出 Codex、等待旧代理退出，不需要强杀进行中的请求。

复杂端口/旧代理迁移推荐 agent 辅助：下载 skill ZIP，完整解压后给 AI：

> 请读取 SKILL.md，按我的实际系统安装 FoxCodexProxy，核对 Clash 端口与旧代理，保留原图标、自动按需启动和 WSS。不要修改系统代理、添加托盘或强杀任务。安装后验证监听和完整真实回复，明确尚未完成的验证。

复制 skill 只是安装说明；agent 还应在获得应用安装授权后执行对应平台 installer。

## Windows 使用

EXE 安装或完整解压 Windows ZIP 后运行 `setup-windows.cmd`。继续使用托盘启动 Codex；两个启动选项独立保存。Windows 原图标启动不保证经过桥接。需要 Windows 10/11、.NET Framework 4.8；无法直连时需要可用 Clash 节点。

## 验证与已知限制

- macOS：64 MiB 双向 hash、半关闭、35 秒活跃静默、真实 launchd 唤醒/退出/再唤醒通过。
- macOS 隔离 home/launchd 命名空间的真实安装、升级、卸载、重新安装、用户编辑保留和活跃服务保护通过。
- 真实 Codex WSS 请求完成，但测试仍观察到 2 次 TLS 握手 EOF 重试，未回退 HTTPS；不保证消灭节点/上游/服务端或大上下文故障。
- 原图标生产环境新启动的实际回复及长期稳定性仍需逐机验证；不会因下载或发布而替换开发者正在运行的旧代理。
- Intel/macOS 13 是编译覆盖，尚未该设备/系统真机运行验证。
- macOS 仅 ad-hoc 签名，没有 Apple Developer ID 签名/公证；Windows 安装器也未经代码签名。请按系统正常批准流程处理，不要关闭系统安全保护。
- 不上传订阅、节点凭据、账号认证或本机配置。卸载保留本地备份和用户后续编辑。

[macOS 详细说明](https://github.com/Foxing365/FoxCodexProxy/blob/v2.3.0/references/macos.md) · [方案比较](https://github.com/Foxing365/FoxCodexProxy/blob/v2.3.0/references/macos-comparison.md)
