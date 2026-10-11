# Windows v2.2.1 verification

Status: preview, not verified continuously stable. The initially passing dedicated node subsequently failed; a fresh independent instance reproduced node TCP dial timeouts. Other tested nodes were intermittent or returned HTTP 403. The dedicated route was rolled back on the test host. Earlier passing counts below describe a finite test window, not sustained stability.

Local Windows checks performed before publication:

- CONNECT tunnel remains usable after 17 seconds of inactivity.
- Startup settings and dedicated route settings persist.
- Direct health requires three successes; early empty tunnels trigger cooldown.
- Managed upstream start, crash recovery, exact-process adoption and exit cleanup pass.
- Occupied bridge port aborts initialization and cleans its private core.
- GUI upgrade retains dedicated port and startup preferences; conflicting port changes are rejected.
- Live dedicated bridge: 10/10 Codex endpoint TLS/HTTP probes and 10/10 GitHub probes passed. Control through the existing main Clash route passed only 4/10 and 5/10 respectively.
- With experimental system-proxy preference disabled: three repeated authenticated model requests returned the expected reply, with zero reconnects and zero transport errors. A preceding three-request command-line override test also passed.
- Terminating only the recorded private core caused tray recovery within seven seconds; a subsequent endpoint probe passed.

Endpoint HEAD responses prove TLS/HTTP reachability, not authentication. Model smoke requests verify only the tested account, network and time window. This is not a promise that every node, app update or server condition will work. Private node configurations and account data are excluded from this repository.
