# Claude Code 套餐用量

通过本机 Claude Code 的 SDK 控制请求 `get_usage` 读取 Pro / Max 套餐的额度窗口。该请求的 `skip_behaviors` 选项就是为用量面板这类调用方设计的：只返回套餐额度，不扫描本地对话记录。

## 读取方式

1. 查找 Claude Code：设置中指定的路径 → `~/.local/bin/claude` → `~/.claude/local/claude` → Homebrew / `/usr/local/bin` → Claude 桌面版内置的最新版本。
2. 在临时目录启动 `claude -p --input-format stream-json --output-format stream-json --strict-mcp-config --no-session-persistence --disable-slash-commands --tools ""`。
3. 依次发送 `initialize` 和 `get_usage`（`skip_behaviors: true`），收到回复后结束进程，超时 30 秒。
4. `rate_limits.five_hour` / `seven_day` 的 `utilization`（已用 %）换算为剩余 %，`resets_at` 为重置时间；`seven_day_opus`、`seven_day_sonnet` 和 `model_scoped` 显示为模型每周额度。

不发送用户消息，不创建模型请求，不保存会话。认证由 Claude Code 自己完成，本应用不读取钥匙串或凭证文件，也不输出令牌。

## 状态

| 情况 | 显示 |
| --- | --- |
| 正常 | 五小时 / 每周剩余与重置时间；缓存数据按 Codex 同样规则标记 |
| 未登录、API Key、Bedrock / Vertex（`rate_limits_available: false`） | 「连接 Claude Code（官方登录）」，在终端运行 `claude auth login` |
| 服务暂时未返回、超时、限流 | 保留 10 分钟内的数据并退避重试（10s / 30s / 60s / 3min） |
| 找不到程序 | 提示安装或在设置 → 高级中选择 |

超过 100% 的使用率（超额）显示为 0% 剩余，不会出现负数。没有五小时窗口时视为不可用，不用每周额度代替。

## 验证

- `Tests/ClaudeTests.swift`：解析、截断、模型窗口、错误分类、Store 刷新与登录提示、菜单栏模式。
- `"agent battery.app/Contents/MacOS/CodexBattery" --probe-claude`：真实读取并只打印额度窗口。本次开发机上 Claude Code CLI 未单独登录，返回「需要连接」；成功路径由 mock 和界面样例覆盖。
