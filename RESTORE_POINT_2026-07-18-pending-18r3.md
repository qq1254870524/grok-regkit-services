# Restore Point #4 — stable-2026-07-18-pending-18r3

Date: 2026-07-18

Companion restore point for grok-regkit `stable-2026-07-18-pending-18r3`.

## Highlights
- pending SSO recovery: bad_password / auth_error → hybrid re-register (not delete-only)
- login quiet wait / Cloudflare gate / loading title fix
- main registration path still immediate SSO on success
- Grok2API grok-4.5 verified callable
- stop registration still only stops 8092 job; 8010/8080/8317/8318 stay up

## Does not overwrite
- stable-2026-07-18
- stable-2026-07-18-sso-mainflow
- stable-2026-07-18-matrix-uifallback
