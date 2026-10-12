# macOS — v2.2.1 原生预览构建

macOS 13 或更新；Universal 二进制同时包含 Apple Silicon 与 Intel。无托盘、菜单栏、特殊启动图标，不依赖 Python、Homebrew 或运行时下载。

## 安装与自动使用

将安装包完整解压，运行 `setup-macos.command`；或在包根目录运行：

```sh
./bin/macos/fox-codex-proxy --install --clash-port 7897 --port 7898 --mode auto
```

首次安装需要核对本机 Clash mixed port。桥接端口不得与 Clash 相同。无需管理员权限。二进制仅做 ad-hoc 签名，尚未 Apple Developer ID 签名或公证；若系统拦截，应由用户通过正常系统批准流程决定是否运行，不要关闭 Gatekeeper 或删除整个系统的安全策略。

安装复制 helper 到 `~/Library/Application Support/FoxCodexProxy/`，注册 `~/Library/LaunchAgents/com.openai.codex-auto-proxy.plist`，在 `~/.codex/.env` 写入标记代理块。不会改变系统代理、模型 provider 或 WSS。

安装后完全退出已运行的 Codex，再从原图标打开。Codex 必须实际读取 `.codex/.env` 才会使用桥接；新版本兼容性需用新会话确认。launchd 仅保留回环监听，首个连接触发 helper。没有活跃连接后 30 秒退出；长思考没有流量但连接仍在时不会退出。无需配置登录自启、不需要常驻监控或图标替换。

旧版本代理正在运行时，安装/卸载会停止并保持原状。先结束其他任务、退出 Codex、等待至少 30 秒，再执行操作。不要强制终止进行中的模型请求。升级保留已安装端口和模式；显式传参数才能改变它们。

## 端口、路线、状态

```sh
# 修改已安装配置：同样需要先等待旧 helper 退出
"$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy" --install --clash-port 7897 --port 7898 --mode auto

# 服务注册、当前进程与上次缓存路线
"$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy" --status

# 新检测；只检测连通性，不执行模型请求
"$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy" --check
```

`--mode` 可用 `auto`、`direct`、`clash`。Auto 检测本机 Clash TUN/fake-IP；存在接管时优先显式 Clash，否则实际 Codex 域名连续三次 TLS/HTTP 探测通过才选择 OS 路径。选择缓存 60 秒。Direct 不保证绕过其他 VPN/TUN。探测正常只说明可达，不验证账号或模型稳定性。

CONNECT 建立前可以尝试另一条路线；回复 200 后不会换线、重放、解密 TLS 或插入 WS 消息。明文 HTTP proxy 请求不在此预览版支持范围（返回 502）；目标用途为 HTTPS/WSS CONNECT。

状态在 Application Support/FoxCodexProxy/status.json；带时间戳、每分钟最多十条隧道诊断写入 `~/Library/Logs/FoxCodexProxy.error.log`。记录路线、读写错误、持续时间与读取字节数；不记录请求头、认证信息、URL、对话或节点凭据。日志暂未自动轮转，需要时可在程序退出后归档。

## 卸载与配置所有权

```sh
"$HOME/Library/Application Support/FoxCodexProxy/fox-codex-proxy" --uninstall
```

移除 launchd 服务和当前仍等于工具写入值的代理条目；保留用户编辑与原先非工具管理的代理值。畸形标记块、升级时块外代理冲突会拒绝操作，避免吞掉其他配置。首次迁移识别旧 Python job 管理的 7898 条目，不在卸载后恢复死端口。备份/日志留在本地 Application Support，卸载后不自动恢复旧 Python 服务。

## 验证与边界

本机构建应验证 64 MiB 双向 hash、半关闭、35 秒活跃静默、真实 launchd 唤醒/退出/再次唤醒。安装后还需独立验证原图标新启动的 Codex 是否继承代理、重复完整 WSS 回复及实际长期使用。这份构建不是“消除五次重试”的保证；节点 TLS 故障、服务端错误和大上下文问题仍可能存在。

安装器的事务回退已经实现并经过代码审查，但尚未在干净 macOS 13/Intel 真机上执行安装—升级—卸载流程。最低版本和 Intel 架构目前是构建验证，不能当作跨设备运行验证。构建不会替换开发者本机正在运行的旧服务。
