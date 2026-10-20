# 舒适尺寸、原生悬浮提示与今日实时统计验证

- final result: passed
- 用户要求：比 300 pt 紧凑版稍大、用量提示格式统一并悬浮显示、今日改用监控程序实时统计。
- 当前宽度 340 pt，字号约增加 10%，仍无 ScrollView。
- 视觉证据：`dist/design/comfortable-month.png`、`dist/design/comfortable-six-rows.png`、`dist/design/comfortable-hover.png`、`dist/design/comfortable-hover-dark.png`；原生 SwiftUI 2x 渲染。
- 月历、六行月份、额度重置时间、长用量数字与底部按钮均可完整显示。
- 悬浮层使用原生 onHover + overlay + Material，无第三方组件、系统 tooltip 延迟或网络等待。提示按列向内对齐，鼠标穿透避免遮挡日期交互。
- 提示与统计卡共用 TokenFormatting，使用万／亿格式；点击日期仍可在下方固定详情。

## 今日实时统计

- 在后台 actor 中读取 CODEX_HOME（默认 ~/.codex）的 sessions / archived_sessions，只解析元数据和 token_count 记录。
- 首次补算当天，之后每 5 秒按文件偏移量增量读取。尚未完成的 JSONL 行暂存到换行后处理。
- 用累计计数差值统计增量；处理重复计数、计数重置、跨午夜、分叉继承记录和归档副本，重启后可重新补算。
- 今日值替换官方当天桶，之前日期仍由官方每日数据决定；累计值减去官方当天桶再加入本机值，避免重复。
- 今日标注“本机实时”，指本机 OpenAI Codex 日志统计，模型响应写入日志后更新；不含其他设备和云端任务，日志也无法按登录账户完整拆分。

## 验证

- 31 项自动测试通过，新增本地增量统计测试覆盖跨日基线、重复、半行追加、归档／分叉、重启、其他 provider、计数重置、日期滚动和目录缺失。
- 独立 ViewModel 检查：今日覆盖、历史不变、累计不重复、过期本机数据不覆盖昨天、仅本地数据与万／亿格式。
- 本机实测首次扫描约 550 ms，后续无新增内容约 3.4 ms；磁盘操作不在 UI actor 执行。
- Debug 与 Release 构建、签名验证通过。
- 未对真实鼠标事件至屏幕呈现的延迟做端到端计时；悬浮状态已通过原生截图验证。

## 2026-09-16 周汇总调整

- 周视图改为历史每周汇总方块图，一列对应周一至周日；一屏最多 26 周，支持历史翻页、悬浮及固定详情。
- 周合计排除未来日期，缺失周保留未知状态，明确零用量为 0；月视图仍按天展示。
- 32 项测试通过，新测试覆盖周日／周一边界、跨月、跨年、缺失周、未来日期和夏令时。
- 浅色／深色检查截图：`dist/design/weekly-totals.png`、`dist/design/weekly-totals-dark.png`。图表、日期区间、月份标记和底部入口完整可见。
- 本机 Swift 6.4 默认 macOS 27 SDK 缺少 SwiftUIMacros 插件；采用已安装的 MacOSX26.5.sdk 和 SwiftPM native 构建系统打包，未修改系统 SDK 设置。临时 swift 包装命令仅用于本次执行，未纳入项目。

## 重置卡信息板块

- 使用本地 Codex 生成的协议核实 `account/rateLimits/read` 的 `rateLimitResetCredits`，并只读确认当前账号返回 2 张可用卡。
- 在每日／每周用量图下方新增可展开的信息卡，展示数量、重置类型、带本地时区的到期时间；不含兑换操作。
- 可用数量为 0、元数据缺失或全部到期时不渲染板块。仅有数量或明细不完整时显示说明，避免伪造卡片。
- 33 项测试通过，覆盖到期边界、零数量、空／缺失数据、数量与明细不齐、已兑换卡过滤和未知重置类型。
- 浅色、深色和无卡截图分别为 `dist/design/reset-credits.png`、`dist/design/reset-credits-dark.png`、`dist/design/no-reset-credits.png`。两张卡的标题及到期信息完整，底部入口可见。
- Release 使用本机 MacOSX26.5 SDK 构建，签名校验通过；未消耗重置卡。

## 账号切换检测

- `account/read` 支持嵌套 `id`、`accountId`、`account_id`、`userId`、`user_id` 和 email 形式的标识，并兼容顶层标识。
- 服务启动时恢复持久化 `accountId`；每次刷新比较当前标识。变化时停止旧 app-server，清理快照、历史、Token、重置卡、本机采样和周期检测器，然后重连新账号。
- 旧版本缓存没有账号标识时，第一次读取到标识会清理已有旧缓存；没有标识的数据不会触发猜测性清理。
- 新增账号标识解析测试；共 34 项测试通过。

## 刷新账号上下文修复

- 刷新按钮触发的 `account/read` 现在传入 `refreshToken: true`，不再依赖 app-server 进程内可能过期的账号上下文。
- 额度响应中的顶层／嵌套 accountId 也会参与账号比较，覆盖 account/read 不返回标识的情况。
- 新增额度响应账号标识测试；共 35 项测试通过。

## 2026-09-30 新版 Codex 兼容性与额度恢复

- 本地 Codex 0.159.0 的 CLI 位于 `ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`；旧插件和旧 Resources/codex 路径已不存在。定位器增加系统／用户应用目录中的新路径，保持显式覆盖及旧版兼容。
- 协议与真实查询确认用户信息返回 email、额度返回 accountId UUID。当前实现取得两份响应后，统一优先使用额度 accountId，避免邮箱和 UUID 交替触发重连。有效额度不被缺失／失败的用户信息阻断。
- 强制刷新明确传递 forceRestart；旧进程的 stdout／退出回调由进程代号过滤，取消的重连任务不会再启动。账号变更清理后直接返回重连结果，避免外层调用误报成功。
- 39 项测试通过。新增真实子进程 JSON-RPC 测试验证缓存账号未变时不重启、手动刷新产生不同 PID、metadata null／错误仍读取额度、换账号只重启一次、旧历史和重置卡替换、未知标识及真正未登录的处理。
- 完整 CodexQuotaService 使用当前真实账号验证通过：新路径自动定位成功；首次及强制刷新均 connected，账号指纹相同，快照时间更新，获得 Plus 额度和 168 个每日用量桶。测试使用临时存储，未输出邮箱、认证令牌或完整账号 ID。
- 本节记录当前有效账号识别流程；上方早期修复记录用于保留验证历史。

## 2026-10-20 v1.2.0 官方 App 定位与发布验证

- GitHub 此前最新下载包为 2026-09-09 发布的 v1.1.0；其源码仅支持旧 `Resources/codex` 路径，尚未包含本地 9 月后续兼容性修复。
- 本机官方 App 版本 26.1013.40934，Bundle ID `com.openai.codex`，内置 CLI 0.163.0-alpha.10.2，路径仍为 `Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。
- 定位器通过 Launch Services 注册的 Bundle ID 和运行中 App 获取实际目录，同时兼容系统／用户目录中的 Codex.app、ChatGPT.app 与四种内置 CLI 布局。不依赖开发者机器中的缓存或 shell PATH。
- 两处文件选择面板均接受整个 .app，定位器将其转换为内置 CLI；未找到 App 的界面提示更新为官方 App 或 CLI 两种安装方式。
- 40 项测试通过，包括新增的全新用户、失效缓存、改名／移动安装目录、四种内置布局、选择 .app、非可执行文件及普通目录拒绝测试。
- 使用全新临时 UserDefaults、无路径缓存、无手动 CLI 覆盖的完整服务，实际连接本机官方 App 并成功读取额度；强制刷新后账号保持一致、快照时间更新，获得 28 个每日用量桶。
- Debug 截图：`dist/design/v1.2.0-missing-app.png`、`dist/design/v1.2.0-overview.png`。新增提示和选择按钮完整，无换行截断；正常用量界面及重置卡显示完整。
- Release 版本 1.2.0 / Build 3，Apple Silicon，签名验证通过。发布包保留 macOS 13 最低版本。
