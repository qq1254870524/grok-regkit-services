# grok-regkit-services

与 [grok-regkit](https://github.com/qq1254870524/grok-regkit) 配套的本机服务编排包（公开脱敏版）。

## 组件

| 组件 | 端口 | 本仓内容 |
|------|------|----------|
| grok-regkit Web | 8092 | 独立仓 `grok-regkit` |
| grok2api | 8010 | 启动约定 + `.env.example`（不带号池 DB） |
| Sub2API | 8080 | 联动说明（上游自建） |
| CLIProxyAPI | 8317 | `config.example.yaml`（不含 exe） |
| CPA Gateway | 8318 | `cpa_gateway.py` + `keys.example.json` |

## 快速开始

1. 克隆：
   - `git clone https://github.com/qq1254870524/grok-regkit.git`
   - `git clone https://github.com/qq1254870524/grok-regkit-services.git`
2. 按各子目录 README 准备：
   - 下载 CLIProxyAPI 可执行文件到 `cliproxyapi/`
   - 准备 grok2api 运行目录（或设置 `GROK2API_ROOT`）
   - 准备 Sub2API（WSL/Docker 或本机），设置 `SUB2API_DEPLOY` 如需
3. 复制密钥样例：
   - `runtime/runtime_secrets.example.json` → `runtime/runtime_secrets.json`
   - `cpa_gateway/keys.example.json` → `cpa_gateway/keys.json`
4. 启动：

```bat
检查服务状态.cmd
启动全部服务.cmd
```

或：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./grok_regkit_service_manager.ps1 Status
powershell -NoProfile -ExecutionPolicy Bypass -File ./grok_regkit_service_manager.ps1 Start
```

## 环境变量（可选）

```text
GROK_REGKIT_ROOT=C:/path/to/grok-regkit
GROK2API_ROOT=C:/path/to/grok2api
CLIPROXY_ROOT=C:/path/to/cliproxyapi
CPA_GATEWAY_ROOT=C:/path/to/cpa_gateway
SUB2API_DEPLOY=/home/ubuntu/sub2api-deploy
```

## CPA → Sub2API

CPA 目录（`xai-*.json` OAuth 包）导入：

```bash
cd grok-regkit
python -B scripts/import_cpa_to_sub2api.py --dir "C:/path/to/Grok/cpa"
```

说明见 grok-regkit `LOCAL_RUN.md` / `README.md`。

## 安全

**不要提交：**

- `runtime/runtime_secrets.json`
- `cpa_gateway/keys.json`
- `cliproxyapi/config.yaml` 真密钥
- `grok2api` 的 `.env` / `data/accounts.db`
- 真实 `xai-*.json` / SSO / 代理密码

本仓仅提供可复现的本地配套骨架。

## 停止注册 vs 停止服务

- grok-regkit Web「停止注册」只停注册任务
- 本管理器 `Stop` 才会停 8092/8010/8317/8318 与 Sub2API compose（按脚本实现）

## 关联仓库

- https://github.com/qq1254870524/grok-regkit
- https://github.com/qq1254870524/sub2api
- https://github.com/qq1254870524/mumu-clipboard-isolation

