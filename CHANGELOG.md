# v2.2.1 — macOS native preview

- 新增 macOS 13+ arm64/x86_64 Universal helper，不依赖 Python。
- 保留原图标、WSS、launchd socket activation；无托盘、无登录常驻。
- Dispatch 持有连接任务；poll 双向有界转发、半关闭、CONNECT 后禁止换线重放。
- 增加 Auto/Direct/Clash、TUN/fake-IP 检查、带时间戳的限流诊断。
- 增加配置所有权、事务回退、活跃连接升级保护及安装/卸载命令。
- 仍为预览构建，跨设备安装和长期端到端稳定性待验证，不承诺消灭重试。

# v2.2.1 — Windows

- Auto 改用 Codex 实际响应接口 HEAD 探测，直连连续三次成功才启用；早期空隧道关闭触发 120 秒冷却。
- 新增 PreferClash 选项，避免 Auto 因偶然探测成功反复回到不稳定直连。
- 可通过 configure-dedicated-route.ps1 为 Codex 配置独立稳定节点，借用本机 mihomo，不修改主 Clash 节点、TUN 或系统代理；支持 -Disable 回滚。
- 托盘管理专用出口进程，配置凭据仅本机保存，不能包含在公开安装包或 skill 中。
- 升级保留已有端口、启动选项和专用出口配置。
- 补充仅 Codex 子进程的 WS/WSS 代理变量，以及专用出口状态检查。
- 检测支持时关闭实验性 respect_system_proxy，避免系统代理优先覆盖进程桥接；保存原值，卸载恢复。原图标启动不再承诺系统代理备用入口，主要使用托盘。
- 保留限流、无请求内容的连接诊断；不承诺消除上游 TLS、服务端高负载或所有五次重试。

# v2.2.0 — Windows

- 代理参数只注入从托盘启动的 Codex，移除旧的用户级代理变量接管。
- 托盘分别保存 Windows 登录自启和代理启动时打开 Codex两项选项。
- 桥接先监听，再等待 Clash 就绪并启动 Codex。
- 自动查询 Store 注册的 Codex 版本，避免正常更新导致旧路径失效。
- 保留长连接超时修复、异常退出守护和恢复检测。
- 安装说明要求关闭 Codex 自身登录自启，避免启动竞争。
- 图形安装器自动读取 Clash 端口，并明确提示关闭 Codex 自身自启。
- 设置窗口禁止 Clash 端口与桥接端口相同；新增不记录请求内容的限流连接诊断。
- 提供 Windows 单文件安装器、ZIP 安装包与 AI agent skill 包。
- macOS 暂不发布。
