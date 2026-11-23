# 与官方 chat-demo 的功能对照

对齐目标：<https://cdn.deepseek.com/chat-demo>（源码 `deepseek-ai/chat-demo`，MIT）。
先照搬，再按本项目要求升级。状态以代码实际能力为准，不用「计划中」冒充。

## 已完成

| 能力 | 实现说明 |
| --- | --- |
| 流式回答 | Messages API SSE，正文与思考分离 |
| 深度思考 | `thinking` 开关 + `output_config.effort`（低/高/最高） |
| 智能搜索 | 声明 `deepseek_web_search` + `deepseek_read_url`，由模型判断是否搜 |
| Markdown 渲染 | micromark + GFM，流式期间实时渲染 |
| KaTeX 公式 | 行内 `$…$`、`\(…\)`，块级 `$$…$$`、`\[…\]`；未闭合块级公式也能排版 |
| 代码高亮 | Prism，覆盖 20+ 常用语言，带语言标签与复制按钮 |
| Mermaid 图表 | 渲染结果按源码缓存，流式期间不重复绘制 |
| 自动标题 | `title.enabled = true`，标题随 `message_delta` 返回 |
| 停止生成 | 中断流并保留已生成部分 |
| 重新生成 | 回退活动叶后重发，旧回答作为分支保留 |
| 多会话 | 本地文件持久化，会话列表可切换、删除 |
| 用户元信息 | 每轮 `latest_reminder`（日期、星期、语言），位置留空待接 |
| 上下文用量 | 以 `usage.input_tokens + output_tokens` 为准 |
| 渲染桥 | 网页渲染器与 Swift 增量同步（正文、思考、消息重建） |

## 未完成（按优先级）

| 能力 | 缺口 |
| --- | --- |
| 来源引用 | `citations_delta` 已解析入库，但正文角标与来源卡片未渲染 |
| 搜索过程展示 | `server_tool_use` 已解析为 ToolTrace，尚未在思考框内列条目 |
| 消息分支切换 | 数据结构支持，缺「切到某个历史版本」的交互 |
| 编辑提问 | 未实现；需改写该节点后重发并保留旧分支 |
| 继续生成 | 官方仅对满足条件的回答开放；未实现 |
| 附件上传 | 图片/PDF/Office 均未接；Files API 与内容块编码未写 |
| 语音输入 | 未接；端侧 ASR（Qwen3-ASR）与录音光效一并待做 |
| 回复朗读 | TTS 未接（顶部「声音」按钮因此先不放置） |
| 位置信息 | 未接 CoreLocation；开关与一次性定位逻辑待做 |
| 历史导入导出 | ZIP 结构与 chat-demo 兼容性未验证 |
| 重命名会话 | 未实现（自动标题可用） |
| 中英双语 | 仅中文 |
| 浅色主题 | 仅深色 |
| 数据管理 | 「删除全部对话」未做 |
| 数据层 | 用 JSON 文件替代 IndexedDB，语义等价 |

## 渲染器工程

`web/` 是一个独立的小工程，产物提交到 `Sources/Resources/web/`（约 4 MB，含 KaTeX 字体）。

```bash
cd web
npm install
npm run build      # 打包到 ../Sources/Resources/web
node --experimental-strip-types src/selftest.ts   # 或见下方自检命令
```

自检（不依赖浏览器，验证解析、公式、高亮、表格、图表占位与流式边界）：

```bash
./node_modules/.bin/esbuild src/selftest.ts --bundle --platform=node --format=esm --outfile=/tmp/selftest.mjs
node /tmp/selftest.mjs
```

浏览器里看效果：用 `web/preview.html`，直接双击即可（引用的是已构建产物）。

## 已知取舍

- `singleDollarTextMath` 打开后，像「价格 $5 和 $6 元」这样的文本会被当成公式。官方 demo 同样如此，属于共用代价。
- Mermaid 的实际绘制的 SVG 尚未在真机验证，仅验证到占位与缓存路径；这一步依赖 WKWebView 的真实环境。
- 渲染器整包约 4 MB，换来公式与图表零妥协；若后续更在意体积，可把 Mermaid 拆成按需加载的第二个包。
