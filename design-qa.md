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
