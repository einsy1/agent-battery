# agent battery 2.3.0

一个用 AppKit 和 SwiftUI 编写的 macOS 菜单栏工具。查看 **Codex 与 Claude Code 套餐额度、Antigravity 模型组额度、DeepSeek API 账户余额**，支持本机 Codex 默认模型切换。

[下载最新版](https://github.com/einsy1/agent-battery/releases/latest) · [更新记录](CHANGELOG.md) · [反馈问题](https://github.com/einsy1/agent-battery/issues)

## 2.3.0 更新

- 新增 **Claude Code** 服务页：五小时额度、每周额度、各自重置时间，以及 Opus 等模型的每周额度（服务端返回时）。
- 数据来自本机 Claude Code 的官方 `get_usage` 查询，不发送对话、不调用模型、应用本身不读取登录凭证。
- 四种布局（Bento / Ultra / 流体胶囊 / HUD）沿用 Codex 页面组件；HUD 同屏显示 Codex、Claude Code、Antigravity。
- 菜单栏显示范围新增「仅 Claude Code」；设置中新增 Claude Code 连接与程序选择。

## 2.2.0 更新

- 顶部统一为 **Codex / Antigravity / DeepSeek** 三个同级服务入口。DeepSeek 不再是底部附加卡片。
- 新增 DeepSeek 账户余额查询，展开查看赠金和充值余额；人民币、美元分别显示。
- 修复默认概览切换「极客双色」没有视觉变化的问题，增加设置内配色预览。
- 刷新、加载指示和底部状态跟随当前服务，减少重复操作。

## 界面与演示

以下为 **2.2.0 实际运行的界面预览**：不读取钥匙串、不查询账户，未知数据显示「—」，没有使用虚构余额或百分比。动图展示服务切换和设置操作。

![服务切换演示](docs/images/service-switch.gif)

| Codex 额度 | DeepSeek 余额 |
| --- | --- |
| ![Codex 页面](docs/images/main-panel.png) | ![DeepSeek 页面](docs/images/deepseek.png) |

![设置与配色](docs/images/appearance.png)

## 安装与使用

1. 下载 Release 中的 `agent-battery-2.3.0-macos-arm64.zip`，解压后把 `agent battery.app` 放入「应用程序」。GitHub 自动生成的 Source code 压缩包是源码，不是安装包。
2. 从旧版本升级时，先退出旧 App；移走旧的 Codex Battery / Codex Quota Preview 等副本，避免同时运行。bundle 标识沿用旧版，保留已有偏好。
3. 顶部选择要查看的服务，点击刷新，或使用 ⌘R。⌘, 打开设置，Escape 返回。

**环境：** Apple Silicon（M 系列），macOS 15 或更新版本。当前没有 Intel 安装包。查询组件需要 Python 3.9+；Codex、Claude Code 和 Antigravity 需要本机已安装并登录对应服务。

发布包使用本地 ad-hoc 签名，**尚未经过 Developer ID 签名和 Apple 公证**。若系统阻止打开，请按系统安全提示核实来源；有开发环境也可自行构建。此项目不是 OpenAI、Anthropic、Google 或 DeepSeek 官方产品。

下载页提供 `SHA256SUMS.txt`。把它与 ZIP 放在同一目录，执行 `shasum -a 256 -c SHA256SUMS.txt` 可检查文件完整性；校验和不代替发布者身份认证。

## 服务与功能

| 服务 | 显示内容 | 配置方式 |
| --- | --- | --- |
| Codex | 五小时、每周可用额度，套餐及重置时间 | 登录本机 Codex / ChatGPT；可在高级设置指定 CLI |
| Claude Code | 五小时、每周可用额度，重置时间，套餐；模型每周额度（如 Opus） | 在 Claude Code 中用 Pro / Max 订阅登录（Claude 页「连接」或 `claude auth login`）；可在高级设置指定 CLI |
| Antigravity | 按模型组区分额度与重置时间 | 在官方 Gemini / Antigravity CLI 中登录 |
| DeepSeek | API 可用总余额、赠金、充值余额及币种 | DeepSeek 页菜单 → 配置或更新 API Key |

DeepSeek Key 存在 macOS 钥匙串中，与模型切换功能共用；配置余额查询无需切换当前模型。使用官方 [`GET /user/balance`](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)，不向模型提问。面板显示 DeepSeek 时每 5 分钟检查，手动刷新可立即查询。错误会清空旧余额，不把未知数据当作零余额。[实现说明](docs/DeepSeek-balance.md)

菜单栏提供 **Codex / Claude Code / Antigravity / Codex + Antigravity** 四种显示范围，以及能量环、分段条、小幽灵三种图标。**DeepSeek 余额目前仅在面板内显示**，不会将金额换算成额度百分比。

保留 Bento、Ultra、流体胶囊、HUD 四种布局和两套色彩模式；设置 → 外观中切换。DeepSeek 使用相同的卡片、文字层级和空状态规范。

**Claude Code：** 应用启动一个隔离的 Claude Code 进程（不加载 MCP、工具、斜杠命令，不保存会话），通过 stream-json 控制协议发送 `get_usage`（`skip_behaviors`），读取后立即结束进程。认证请求由 Claude Code 自己完成，本应用不打开钥匙串或凭证文件。自动查找 `~/.local/bin`、Homebrew、`~/.claude/local` 以及 Claude 桌面版内置的 Claude Code。使用 API Key、Bedrock / Vertex 或未登录时没有套餐额度，面板会提示连接，不会显示为 0。刷新与 Codex 相同：3 分钟一次，失败退避重试，五小时窗口重置时自动刷新。[实现说明](docs/Claude-usage.md)短暂额度查询失败会退避重试；只有有效期内的数据可作为缓存，未知数据不会用 0 或 100% 代替。

## 自动触发与模型切换

**「满额自动轻量触发」默认开启。** 当 Codex 五小时额度为满且满足使用条件时，发送一次要求回复 OK 的真实请求，消耗少量套餐额度。每次尝试冷却至少 5 小时 1 分钟，失败或超时也不立即重复。可在设置 → Codex → 满额自动触发中关闭，关闭不取消已经发出的请求。

应用退出后停止自身调度。如果以前安装过独立 `local.codex.quota-keeper` LaunchAgent，需用独立脚本的 `uninstall` 操作单独停用；应用内开关不控制旧后台任务。

设置 → Codex 中可切换 ChatGPT、DeepSeek Flash / Pro。该功能会修改本机 Codex 的模型配置，DeepSeek 使用自己的 API 计费；需要兼容的 Codex CLI（切换器要求 0.164.0+）。切换后新开 CLI 会话或重启桌面端。选回 ChatGPT 时恢复切换前的受管理配置，其他配置保留。

## 隐私与安全

- 普通 Codex / Claude Code / Antigravity 刷新查询额度元数据，不读取认证令牌文件；Antigravity 本地回退查询会使用同用户进程中的 CSRF token，仅发送到本机环回服务。
- DeepSeek Key 只从钥匙串读取，用于请求官方 HTTPS 余额地址；禁止重定向，不输出 Key，不写入源码、配置或余额日志。
- 无数据、未配置、加载和读取失败分别呈现。普通余额查询不创建模型会话。
- 自动触发与模型切换的真实请求、计费和配置副作用见上一节。
- 请勿在 issue 中提交 API Key、认证文件或未脱敏日志。敏感问题的报告方式见 [SECURITY.md](SECURITY.md)。

## 构建与测试

```sh
./test.sh
./build.sh
"agent battery.app/Contents/MacOS/CodexBattery" --ui-preview
"agent battery.app/Contents/MacOS/CodexBattery" --ui-preview --dark
```

需要支持项目所用 SwiftUI API 的 Xcode / Command Line Tools SDK（使用 macOS 26+ SDK 构建，部署目标 macOS 15），以及 Python 3.9+。构建时从 PyPI 安装固定版本 `tomlkit==0.13.3` 并打包到 App。

本次发布在本机 macOS 26.5 SDK 上构建。若默认 SDK 缺少 SwiftUI 宏插件，可在已安装对应 SDK 的情况下用 `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh`。这不是对所有环境强制指定的路径。

测试覆盖 Claude Code 用量解析（剩余换算、超额截断、模型窗口、未登录与临时不可用）、额度解析、子进程超时、失败恢复、模型组隔离、图标、偏好持久化、自动触发冷却，以及 DeepSeek 金额解析、币种隔离、认证错误和凭证不出现在输出中。DeepSeek 成功余额路径使用 mock 验证，尚未用真实 Key 验证成功返回；未执行真实模型调用或计费测试。三种保留布局未逐一完成全状态视觉回归。

## 授权与依赖

本仓库目前未指定项目许可证，公开源码不等同于授予开源许可。第三方依赖的许可独立适用：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
