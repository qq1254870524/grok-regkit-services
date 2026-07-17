# CPA Gateway

轻量 key 配额网关，转发到本机 CLIProxyAPI。

## 运行

```bash
copy keys.example.json keys.json
# 编辑 keys.json
python -B cpa_gateway.py
```

默认监听 `127.0.0.1:8318`，上游默认 `http://127.0.0.1:8317`。

**不要提交真实 keys.json。**
