# STABLE_VERSION

## Latest companion — stable-2026-07-19-docs-sync-18r28i

| 项 | 值 |
|----|----|
| Tag | `stable-2026-07-19-docs-sync-18r28i` |
| grok-regkit | `stable-2026-07-19-docs-sync-18r28i` + business `stable-2026-07-19-pending-one-login-18r28h` |
| sub2api | `stable-2026-07-19-docs-sync-18r28i` (Grok 429 failover) |

## Ports

| Port | Service |
|------|---------|
| 8092 | grok-regkit Web |
| 8080 | Sub2API |
| 8010 | grok2api |
| 8317 | CLIProxyAPI |
| 8318 | CPA Gateway |

Stop registration on 8092 only; keep other ports up.

## Prior restore docs

- RESTORE_POINT_2026-07-18-pending-18r3.md
- stable-2026-07-18-matrix-uifallback
- stable-2026-07-18-sso-mainflow
