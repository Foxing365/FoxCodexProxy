# 给 AI agent 的安装提示

本包只发布 Windows 版。请先完整读取 `SKILL.md` 和 `references/windows.md`，再按用户要求安装或诊断。

用户说“安装这个代理”时，不能只把 skill 文件复制进 skills 目录就宣布安装完成：还需要运行 Windows 安装脚本、确认托盘和桥接监听，并说明 Codex 的启动方式。

安装完成后告知用户：关闭 Codex/ChatGPT 自己的登录自启，保留代理与 Clash 自启；当前已运行的 Codex 完全退出后从托盘启动一次。托盘的两个启动选项独立保存，默认建议同时开启。
