# CHANGELOG

## 2026-07-19 — stable-2026-07-19-docs-sync-18r28i

- 文档对齐 grok-regkit **18r28i** / 业务基线 **18r28h**（pending ONE login、即时 SSO 主路径）。
- 明确端口：8092 regkit · 8080 Sub2API · 8010 grok2api · 8317 CLIProxy · 8318 CPA Gateway。
- 停注册只停 8092 任务；服务管理器 Stop 才会停全栈。
- **不覆盖**旧 restore points / releases。

﻿# CHANGELOG

## 2026-07-18 — restore point #4 stable-2026-07-18-pending-18r3

See RESTORE_POINT_2026-07-18-pending-18r3.md

## 2026-07-18 — restore point #3 `stable-2026-07-18-matrix-uifallback`

- Companion docs for grok-regkit matrix + UI fallback last-resort snapshot.
- Does not overwrite `stable-2026-07-18` or `stable-2026-07-18-sso-mainflow`.
- Runtime reminder: stop registration on 8092 only; keep 8010/8080/8317/8318 up.

