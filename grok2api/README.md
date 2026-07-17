# grok2api companion notes

建议直接使用上游/你自己维护的 grok2api 源码，不要把生产 `data/accounts.db`、`.env` 提交到公开仓。

## 最小本地约定（与服务管理器兼容）

| 项 | 值 |
|----|----|
| 监听 | `127.0.0.1:8010` |
| 配置 | `.env` / `data/config.toml`（本地私有） |
| 健康 | `http://127.0.0.1:8010/docs` 或管理页可访问 |

示例环境变量见 `.env.example`。

## 与 grok-regkit 联动

- 注册成功后可自动把 SSO 写入 grok2api 号池（`grok2api_auto_add_local/remote`）
- Sub2API 走另一条 OAuth 账号池，不互相替代

参考：https://github.com/qq1254870524/grok-regkit
