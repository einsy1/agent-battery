# UI 调整

默认 Bento 布局改为原生分段服务切换和额度明细。保留其他三种布局及持久化选择。
模型切换和自动触发移至设置；设置改为系统分组 Form，分为外观、菜单栏、Codex、Antigravity 和高级入口。
新增 ⌘R 刷新、⌘, 设置、Escape 完成、设置页 ⌘Q 退出。
默认布局通过 freshness 隐藏失效数据，缓存另行提示。空数据以破折号和中性轨道呈现。
设置内容可滚动，最大高度随当前屏幕可用高度限制。保留系统减少透明度、减少动态效果支持。

构建环境：本机默认 macOS 27.2 SDK 缺少 SwiftUIMacros 插件，使用以下命令：

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./test.sh
```

本地界面检查模式（不启动自动触发、定时器、登录流程，不注入演示额度）：

```sh
"agent battery.app/Contents/MacOS/CodexBattery" --ui-preview
"agent battery.app/Contents/MacOS/CodexBattery" --ui-preview --dark
```

build.sh 现在会在最终复制后清理残留扩展属性、重新执行本地签名并严格校验。
此签名用于本机运行，不代表 Developer ID 签名或公证。

## 验证记录

- 完整 test.sh 通过（额度、恢复、分组、图标、偏好持久化、自动触发冷却）。
- 项目输出与 /Applications/agent battery.app 均通过 codesign --verify --deep --strict。
- 实际打开本地预览，检查浅色/深色概览、无数据状态、服务切换、原生设置、设置滚动、布局切换、Escape 返回、重启布局偏好恢复。
- 未发送真实模型请求，未切换真实模型提供方、修改登录项或执行 Google 登录。
- 三种保留布局未逐一完成全状态视觉回归；真实网络失败恢复依靠现有回归测试，未进行在线故障注入。
