# Native macOS build validation — 2026-10-12

Built with Apple Swift 6.2 in Swift 5 language mode; macOS 13 deployment target; arm64 + x86_64 Universal Mach-O. Ad-hoc code signature verified. Runtime tests ran on the developer's Apple Silicon Mac, not an Intel/macOS 13 machine.

- `scripts/macos/build.sh`: PASS.
- `python3 tests/macos/run.py`: PASS direct and mock-Clash 64 MiB each direction, SHA256 match, delayed reply after client half-close, active silence surviving idle deadline, idle exit.
- Same suite: PASS real launchd socket activation under an isolated temporary test label; no helper at registration, 35 seconds quiet active connection, idle exit, second activation; test job removed afterward.
- `python3 tests/macos/halfclose_cpu.py`: PASS 35-second delayed response after client half-close; less than 1 CPU second during a 5-second quiet sample; idle exit. Prevents regression to repeated POLLHUP wakeups.
- Live route probe: PASS identifies Clash TUN and selects explicit mixed port.
- Isolated real Codex WSS request via native helper → existing Clash: completed with expected NATIVE_WS_OK; **two TLS handshake EOF retries**, no HTTP fallback. This is evidence that WSS completes, not evidence that retries are solved.
- Skill validation, shell syntax, zip contents/executable bit, bundled binary hash and ad-hoc signature: PASS.

No production proxy process was restarted, no existing Codex session was stopped, no model provider changed, and no macOS installer/uninstaller was run on the production home. Installer rollback and configuration ownership were reviewed, but install→upgrade→uninstall remains an end-to-end acceptance gap. No third-party implementation code was copied. GitHub publication was not performed.
