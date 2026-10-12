# 给 AI agent 的安装提示

先读取 `SKILL.md`，按平台选择 `references/windows.md` 或 `references/macos.md`。统一发布包为 v2.3.0，Windows runtime 沿用 v2.2.1，macOS 为原生 v2.3.0。

macOS 使用原图标 + `.codex/.env` + launchd 按需监听，不要安装托盘或常驻监听器。授权安装时运行 `bin/macos/fox-codex-proxy --install`；状态/卸载用 `--status`、`--uninstall`。在 macOS 先用 `--detect-clash-port` 核对本机端口；直接运行 helper 可避免安装入口的交互提示。构建或正式发布不等于已安装或长期稳定，运行中的旧服务不得为升级而强杀。下文仅针对 Windows。

当前版本 2.2.1。升级保留端口、启动选项和专用出口配置，不要自行覆盖成本机开发者的端口或节点。

用户说“安装这个代理”时，不能只把 skill 文件复制进 skills 目录就宣布安装完成：还需要运行 Windows 安装脚本、确认托盘和桥接监听，并说明 Codex 的启动方式。

安装完成后告知用户：关闭 Codex/ChatGPT 自己的登录自启，保留代理与 Clash 自启；当前已运行的 Codex 完全退出后从托盘启动一次。托盘的两个启动选项独立保存，默认建议同时开启。

检测本机 CLI 支持时，安装器把实验性 `respect_system_proxy` 设为 false，避免系统代理优先覆盖模型/插件的进程桥接；保留原值供卸载恢复，不修改主 Clash 或 Windows 系统代理。不要再承诺原图标启动会走系统代理备用出口，主要入口是托盘启动。

若用户授权为 Codex 使用专用节点，先测试其本机订阅节点，再运行安装目录的 `configure-dedicated-route.ps1 -NodeName "用户自己实测稳定的节点名称"`。专用实例借用已有 mihomo，不修改主 Clash 节点、TUN 或系统代理；`-Disable` 恢复原出口。节点/订阅凭据或物理网卡变化后需重新配置。专用 YAML、备份和凭据只留本机，绝不上传到仓库、日志或 skill 包。

Auto 的实际 Codex HEAD 三连成功与空隧道 120 秒冷却是健康策略，PreferClash 可优先指定出口；它们不等于账户认证成功，也不保证消灭全部重连。HTTP 405 可用于证明 TLS/HTTP 到达，仍须分别验证长连接和实际 Codex 对话。代理环境变量（包括 WS/WSS）只注入托盘启动的 Codex，不接管用户级环境。
