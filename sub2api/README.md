# Sub2API companion notes

Sub2API 本体请使用上游：https://github.com/Wei-Shaw/sub2api

## 与 grok-regkit 的约定

| 项 | 值 |
|----|----|
| 本机地址 | `http://127.0.0.1:8080` |
| 注册后 SSO 入池 | `POST /api/v1/admin/grok/sso-to-oauth` |
| 存量 CPA OAuth JSON 入池 | `POST /api/v1/admin/accounts`（`platform=grok type=oauth`） |

## 导入 CPA 目录

在 grok-regkit 目录：

```bash
python -B scripts/import_cpa_to_sub2api.py --dir "C:/path/to/Grok/cpa"
```

或 Web 控制台「号池联动」→ 填写 CPA 目录 →「导入 CPA 到 Sub2API」。

## WSL / Docker

服务管理器默认通过 WSL distro + compose 管理 Sub2API，部署目录可用环境变量：

```text
SUB2API_DEPLOY=/home/ubuntu/sub2api-deploy
```

请自备 compose 与数据库卷；本仓不包含生产密钥与数据库。
