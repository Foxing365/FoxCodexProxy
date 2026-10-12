# macOS 方案取舍（2026-10-12）

以下比较基于实际阅读原始仓库和 issue；未复制第三方实现，也未执行它们的安装脚本。

| 方案 | 可采纳的机制 | 与本项目 macOS 的差异 |
|---|---|---|
| [Codex-Connectivity](https://github.com/zhenyangLab/Codex-Connectivity) | 明确 HTTP/HTTPS/WS/WSS 环境；保留内置 provider 和同一 CODEX_HOME | Windows 快捷方式，不适用于原图标无托盘 macOS；旧 HTTP/provider 改法可能改变历史可见性 |
| [codex-app-proxy](https://github.com/leisair/codex-app-proxy) | 简单启动器、退出后没有额外常驻中转 | Windows 专用启动入口；Chromium 参数不代表 Rust 模型链路已覆盖 |
| [codex-mobile-proxy-fix](https://github.com/hydonedo/codex-mobile-proxy-fix) | macOS .env、配置所有权与备份、检查 daemon 环境 | 固定代理没有自动切换；可选全局 launchctl 环境影响范围更大；SOCKS 稳定结论属于单机经验 |
| [codex-proxy-launcher](https://github.com/MrWynn/codex-proxy-launcher) | 明确进程代理可用于对照 | 命令启动并关闭旧进程，不符合原图标使用，可能中断任务 |
| FoxCodexProxy native macOS | .env + launchd socket activation；保留 WSS；无托盘/常驻监控；空闲退出 | 使用体验更符合本项目要求，但增加一层转发，稳定性必须与直接 Clash 同条件比较 |

没有证据证明本项目已比这些项目更稳定。固定 Clash .env 更简单，应作为对照基线。TCP keepalive 不是 WS Ping，透明 TLS 隧道不能在不解密的前提下注入 WS 心跳。

## 近期本机与外部故障

本机只读日志截至 2026-10-12 16:17，近 48 小时 108 条 responses_retry、26 个线程；61 条 TLS 握手 EOF、33 条回复完成前 WS 关闭、14 条发送失败，10 条达到 5/5。旧 Python error.log 有大量 pending task 销毁/GeneratorExit，支持生命周期缺陷线索，但没有旧日志时间戳来证明全部重试的因果关系。原生 helper 用 Dispatch 持有每条连接，直到双向完成/硬错误，避免依赖未持有强引用的 asyncio 任务。

- [#51889](https://github.com/openai/codex/issues/51889)：近期 macOS 媒体累积、大请求、Broken pipe/5次重试；没有证明统一大小阈值或 compact 是万能解法。
- [#32366](https://github.com/openai/codex/issues/32366)：长聊天 WS 断流，HTTP 200 也未必返回事件；不能把 HTTP 可达当完成。
- [#51399](https://github.com/openai/codex/issues/51399)：durable app-server 握手问题，与模型 Responses WS 是不同链路。
- [#14080](https://github.com/openai/codex/issues/14080)：旧版 macOS 代理解析差异，作者已经关闭；不能直接当作当前版本源码事实。
- [#18960](https://github.com/openai/codex/issues/18960)：多个不同原因表现相似，不能用同样的5次重试认定同一根因。
- [官方 Responses WS 源码](https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/endpoint/responses_websocket.rs)已有 Ping/Pong pump；main 不代表本机内置版本一定相同。

这些来源支持排查方向，不能证明本机上游错误已经修复。此构建不自动切换节点、不改变主 Clash、不强制 HTTP，不发布本机订阅或账号数据。
