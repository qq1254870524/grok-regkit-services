# CLIProxyAPI (local companion)

本目录只提供本地示例配置，**不包含官方 exe 二进制**。

1. 从上游发布页下载 CLIProxyAPI：
   - https://github.com/router-for-me/CLIProxyAPI
2. 将可执行文件放到本目录，命名为 `cli-proxy-api.exe`（Windows）
3. 复制 `config.example.yaml` → `config.yaml` 并修改 `api-keys`
4. 把 grok-regkit 导出的 `cpa_auths/xai-*.json` 放到 `auth-dir`（默认 `./auths`）

```bash
cli-proxy-api.exe -config config.yaml
```

默认仅监听 `127.0.0.1:8317`。
