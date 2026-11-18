# DeepSeek API 账户余额

通过官方 `GET https://api.deepseek.com/user/balance` 查询余额元数据，不向模型提问。
文档：https://api-docs.deepseek.com/zh-cn/api/get-user-balance/

- 各布局顶部提供 Codex / Antigravity / DeepSeek 同级切换；选中 DeepSeek 后，在当前内容区域显示余额，展开查看赠金和充值余额，人民币/美元分开展示。
- 复用模型切换组件保存于钥匙串的 DeepSeek Key；可在 DeepSeek 页的菜单中配置或更新，无需切换当前模型。
- 面板打开时查询；面板可见期间每 5 分钟更新。刷新按钮可立即查询。
- 未配置、加载、认证失败、网络失败、零余额分别呈现；失败清空旧余额，不以 0 代替未知数据。
- 网络请求固定官方 HTTPS 地址，拒绝重定向；Key 不写入磁盘、命令行参数、余额输出或诊断日志。
- 余额字符串按 Decimal 校验，不对不同币种求和，不使用二进制浮点数转换金额。
- 界面预览模式不读取 Key、不查询网络。

验证：新增 6 项 mock 测试及完整 test.sh 通过。真实检查返回未配置 Key；未用真实账户验证成功余额，未调用模型接口。
