# DeepSeek 手机端客户端（iOS）

按 `手机端接入 DeepSeek API 客户端方案.md` 实现的原生 iOS 客户端。

部署目标当前为 **iOS 26.0**：托管 runner 目前只提供 Xcode 26.6 / iOS 26.5 SDK，写 27.2 会因 SDK 不足直接编译失败。工程没有使用任何 26 之后才有的 API，所以这不影响功能；等 runner 提供 iOS 27.2 SDK 后，把 `project.yml` 里两处 `26.0` 改回 `27.2` 即成。

## 当前进度

已完成的第一阶段（可编译骨架 + 核心对话链路）：

| 模块 | 状态 |
|---|---|
| XcodeGen 工程定义 + 云构建工作流（未签名 IPA） | 完成 |
| Messages API 流式请求（thinking / 搜索工具 / 标题 / 风控 / 用户元信息） | 完成 |
| SSE 解析、事件映射（思考、正文、工具调用、引用、用量） | 完成 |
| 正文渲染器：Markdown + KaTeX 公式 + 代码高亮 + Mermaid，流式实时渲染 | 完成（移植自 chat-demo） |
| 思考框（流式滚动 / 收起为一行 / 点击回看） | 完成 |
| 会话与消息本地持久化（扁平节点树，支持分支保留） | 完成 |
| 首页、顶部栏、输入区、双开关、上下文用量徽标 | 完成 |
| 会话列表、删除、重新生成、停止生成、错误重试 | 完成 |
| API Key 存钥匙串、模型/档位/强度设置 | 完成 |
| 中转服务与断网取回 | 未开始 |
| 搜索条目卡片、引用角标跳转 | 未开始（数据已解析保留） |
| 图片/文件上传、拍照相册入口 | 未开始 |
| 上下文自动压缩、档位作为触发点 | 未开始 |
| 长期记忆、人设、回退到任意节点 | 未开始（回退所需的数据结构已就绪） |
| 语音输入（端侧 ASR + 录音光效） | 未开始 |
| 导出分享（长图 / ZIP）、清理中转缓存 | 未开始 |

## 目录结构

```
DSClient/
├── project.yml                 # XcodeGen 工程定义（唯一的工程真相源）
├── .github/workflows/build.yml # 云构建：生成工程 → 归档 → 打未签名 IPA → 发布 rolling release
├── Support/Info.plist          # 权限与启动屏等声明
├── Docs/
│   ├── UI-notes.md             # 参考视频逐帧提取的界面记录与待确认项
│   └── demo-parity.md          # 与官方 chat-demo 的功能对照
├── web/                        # 正文渲染器源码（Node 工程，产物提交进仓库）
└── Sources/
    ├── App/                    # 入口、全局状态、设置项
    ├── Core/                   # SSE、API 客户端、请求构造、token 估算、钥匙串
    ├── Storage/                # 会话模型与文件持久化
    ├── Design/                 # 配色、通用控件
    ├── Resources/web/          # 渲染器产物：renderer.js、KaTeX 样式与字体
    └── Features/
        ├── Chat/               # 对话界面、WebView 渲染桥、输入区、流式会话
        ├── Sidebar/            # 会话列表
        └── Settings/           # 设置
```

## 构建

工程文件不入库，由 XcodeGen 从 `project.yml` 生成，避免 `.xcodeproj` 的二进制式冲突。流水线沿用同账号下 `opengate` 已验证的一套口径。

云构建：

1. 把 `DSClient` 目录作为仓库根目录，默认分支 `main`。
2. Actions 执行：下载固定版 XcodeGen → `xcodegen generate` → `xcodebuild archive`（不签名）→ 打 `DSClient.ipa` → 上传产物，并在 `main` 上把 IPA 发布为 `latest` rolling release。
3. 构建号取 `github.run_number`，每次推送自动递增，侧载工具能正确识别为新版本。
4. 前提：runner 的 SDK 不得低于部署目标。工作流第一步会打印实际 Xcode 与 SDK 版本；若部署目标高于 SDK，归档会失败——此时要么改部署目标，要么换带更新 Xcode 的 runner。

日常不需要手动进 GitHub 下载，一体化脚本会把产物直接放到本地：

```bash
python tools/build.py                  # 提交并推送 → 等构建 → 下载到 _local/
python tools/build.py --skip-push      # CI 已在跑，只等结果并下载
python tools/build.py --commit "说明"   # 指定提交信息
python tools/logs.py                   # 构建失败时拉日志，列出失败步骤与 error 行
```

产物路径固定为 `_local/DSClient-<MARKETING_VERSION>.ipa`，签名工具直接从该目录取包。令牌读 `.token` 或环境变量 `GITHUB_TOKEN`；`.token` 与 `_local/` 都不入库。

本地 Mac（可选，用于真机调试）：

```bash
curl -sL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip
unzip -q /tmp/xcodegen.zip -d /tmp && sudo cp -R /tmp/xcodegen/*.bundle /tmp/xcodegen/xcodegen /usr/local/bin/
cd DSClient && xcodegen generate --spec project.yml && open DSClient.xcodeproj
```

## 安装到手机

工程不配置签名，产物是未签名 IPA，安装前需要用自己的 Apple ID 签一次。两条路选一条。

### A. Windows 电脑签名（Sideloadly）

前置：安装 [iTunes（Apple 官网版）](https://www.apple.com/itunes/) 或「Apple 设备」应用，**不要用 Microsoft Store 版本**——它缺 USB 驱动组件，Sideloadly 会找不到设备。

1. 手机用 USB 连接电脑，解锁并在弹窗中选「信任此电脑」。
2. 安装 [Sideloadly](https://sideloadly.io/)，打开后把 `DSClient.ipa` 拖进窗口。
3. `Apple Account` 填自己的 Apple ID，点 Start；按提示输入密码与双重认证验证码。
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任对应开发者描述文件。
5. 免费 Apple ID 的签名 7 天失效，到期后重连电脑再点一次 Start 即可；同一 Apple ID 可同时签 3 个 App。

覆盖安装同一个 bundle id 的新版本会**保留**本地会话与钥匙串里的 API Key，不需要重新配置。

### B. 手机端 SideStore 签名

1. 手机打开仓库 Releases → `latest` → 下载 `DSClient.ipa`，分享存入「文件」。
2. SideStore → `+` → 选择该 IPA → 用 Apple ID 签名安装。
3. 首次安装若提示未受信任，按上面第 4 步信任描述文件。

## 关键设计决策

- **协议选 Messages API**（`/anthropic/v1/messages`），不是 Chat Completions。只有它把 thinking 块、`server_tool_use`、`web_search_tool_result`、`citations_delta`、以及 `message_delta` 里的会话标题结构化下发，与 App 的思考框、搜索条目、来源角标一一对应。
- **会话用扁平节点数组 + 父指针**，不用树形嵌套。回退到任意节点时，被抛弃的分支仍在 `nodes` 里，活动路径由 `activeLeafID` 回溯得到，序列化与导出都不会退化。
- **正文用内嵌 WKWebView 渲染，不用原生 MarkdownUI**。官方 chat-demo 的渲染栈是 KaTeX + Prism + Mermaid，SwiftUI 侧没有等价替代（MarkdownUI 不支持 LaTeX，也没有图表）。直接把同一套 JS 打包进 App，公式与图表才能和网页端一致。这也顺带解决了长回答的性能问题：DOM 增量更新比每来一个 token 重建整棵 AttributedString 便宜得多。
- **流式渲染靠 `micromark-extension-llm-math`**。它在 `$$` 尚未闭合时就按公式排版，不会先显示一段 LaTeX 源码；行内 `$…$` 未闭合的短暂窗口由渲染器临时补一个闭合符，且只在该尾段看起来确实是公式时才补（避免把「$100 美元」当成公式）。
- **历史只回传正文**。官方口径：之前轮次的思考、搜索结果、打开的网页不进入后续上下文；只传 `text` 既符合拼接规则，也让前缀稳定以命中硬盘缓存。
- **每轮 user 消息前固定插入 `latest_reminder`**，格式 `<date>,<weekday>,<location>,<platform>,<language>`，原文存进节点，重发时原样复用，避免破坏缓存前缀。
- **上下文用量优先用 `usage.input_tokens + output_tokens`**（权威值），本地估算只用于发送前的档位判断。

## 已知限制

- 未在真实 Xcode 上编译过（开发环境为 Windows）。首轮云构建预计需要修正少量编译问题，尤其是 SwiftUI/并发相关的细节。
- 鲸鱼标志暂用 SF Symbol 占位，需替换为正式素材。
- 顶部「声音」按钮、图片缩略图横条、「拍照/相册/文件」三个入口尚未接入，避免出现点了无反应的死按钮。
- 中转服务未接入，当前为直连模式；断网取回与「清理中转缓存」依赖中转落地后才能验证。
