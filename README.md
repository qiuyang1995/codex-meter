# Codex Meter

**Codex 额度监控** — 一个轻量的原生 macOS 菜单栏工具，用来查看当前本机已登录 Codex 账户的**周额度**。

打开菜单栏图标后，大约一秒内就能看清：

- 本周还剩多少额度
- 什么时候刷新
- 当前消耗节奏是否偏快

不抓网页，不读 Cookie，不解析 `auth.json`，也不要求填写 OpenAI API Key。额度只来自本机已经登录的 Codex。

## 截图位置说明

仓库根目录的 `原型图.png` 是早期金额式 Dashboard 草稿，**不是**当前界面。当前界面展示剩余额度百分比与 Token 用量统计，不显示美元金额。

应用运行后：

1. 顶部菜单栏右侧出现带字母 `C` 的图标
2. 点击图标弹出约 340pt 宽的浮层
3. 浮层直接显示本周剩余百分比、刷新时间和最近趋势

## 功能

- 菜单栏常驻，默认不出现在 Dock
- 自动发现本机 `codex` 可执行文件
- 持久化运行 `codex app-server`，通过 JSON-RPC 读取额度
- 识别 10080 分钟（7 天）的 Weekly Limit
- 同时识别 300 分钟（5 小时）和 10080 分钟（7 天）额度窗口
- 使用 Codex 返回的真实 `resetsAt`，不会假设周一或周日刷新
- 监听 `account/rateLimits/updated`，额度变化时立即更新
- 读取 Codex 账户每日 token 用量，以周／月日历热力图展示
- 1 / 5 / 10 / 30 分钟保险轮询，默认 5 分钟
- 本地缓存最近快照与 30 天历史趋势
- 剩余 30% / 15% / 5% 系统通知，同一周周期每个阈值只提醒一次
- 周额度刷新后可发送一次通知
- 开机启动、菜单栏百分比、Codex 路径均可在设置中调整
- 浅色 / 深色模式

## 系统要求

- macOS 13.0 或更高
- 已安装并登录官方 Codex／ChatGPT macOS App；也支持单独安装的 [Codex CLI](https://github.com/openai/codex)
- Xcode 15+（用 Xcode 打开工程时）或 Swift 5.9+ 命令行工具

## 运行方式

### 用 Xcode

1. 打开 `CodexMeter.xcodeproj`
2. 选择 **CodexMeter** scheme
3. Run

也可以打开 `Package.swift`，运行 `CodexMeter` executable target。

### 用命令行打包 .app

```bash
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh
open CodexMeter.app
```

首次从 Finder 启动时，macOS 可能会提示未签名应用。这是本地开发版，使用 ad-hoc 签名。

## 构建方式

```bash
# 编译
swift build -c release --product CodexMeter

# 测试（本仓库使用独立测试运行器，不依赖完整 Xcode / XCTest）
swift run CodexMeterTests
# 或
./Scripts/test.sh
```

如果已安装完整 Xcode：

```bash
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -configuration Release build
```

## Codex CLI 要求

应用会按以下顺序寻找 `codex`：

1. 设置里手动指定的路径
2. 上次成功缓存的路径
3. 通过 Bundle ID `com.openai.codex` 及正在运行的应用定位官方 App，再检查内置 CLI；兼容系统／用户应用目录的 `Codex.app` 和 `ChatGPT.app`
4. Homebrew、用户 CLI、旧版插件和旧版 ChatGPT 内置路径
5. nvm、Volta、Cargo 等 CLI 安装目录
6. 登录 shell：`/bin/zsh -l -c "command -v codex"`

找到后会启动：

```bash
codex app-server --stdio
```

请先保证本机 Codex 已经完成 ChatGPT 登录。应用不会要求你输入密码、Access Token 或 Cookie。

## 数据来源说明

应用通过 Codex App Server 的本地 JSON-RPC 读取额度，主要方法：

| 方法 | 用途 |
| --- | --- |
| `initialize` / `initialized` | 连接握手 |
| `account/read` | 账户类型与 Plan（只用于状态，不展示邮箱） |
| `account/rateLimits/read` | 读取当前额度窗口 |
| `account/rateLimits/updated` | 额度变化时的推送 |
| `account/usage/read` | 读取个人中心中的每日 token 用量 |

周额度识别方式：遍历返回的所有 rate limit window，找到

```text
windowDurationMins == 10080
```

或兼容字段 `window_minutes == 10080`。

实际兼容的字段包括：

- `usedPercent` / `used_percent`
- `remainingPercent` / `remaining_percent`
- `windowDurationMins` / `window_minutes`
- `resetsAt` / `resets_at`
- `rateLimits.primary` / `rateLimits.secondary`
- `rateLimitsByLimitId`

主界面展示 5 小时与周剩余额度，以及包含具体时刻的重置说明。今日、本周消耗只显示 Tokens，本周从本地时间周一开始累计。下方显示累计 Token、已获取历史中的单日峰值和可切换周／月的每日用量热力图；点击日期可查看精确用量。不支持每日用量接口时显示空状态。累计总量优先采用接口 summary.lifetimeTokens，缺少时明确标记为已获取历史的合计。

## 隐私说明

- 数据只留在本机
- 不上传 Codex 额度、对话、项目代码
- 不读取浏览器 Cookie
- 不解析或导出 `auth.json`
- 不要求 OpenAI API Key
- 没有第三方统计、广告或远程账号系统
- 日志里不会打印 Access Token、Refresh Token、Cookie 或 Authorization Header
- `account/read` 返回的邮箱不会写入界面或日志

## 常见问题

**菜单栏没有图标？**  
确认应用已启动。这是菜单栏应用，Dock 默认不显示。可在「活动监视器」里搜索 Codex Meter。

**提示未检测到 Codex？**  
安装 Codex CLI 并登录后点「重新检测」。如果 GUI 应用找不到 PATH 中的 `codex`，到设置里手动选择可执行文件。

**提示尚未登录？**  
在终端运行 `codex` 或打开 Codex / ChatGPT 桌面应用，完成 ChatGPT 登录后再刷新。

**刷新时间显示「未知」？**  
说明当前响应里没有可用的 `resetsAt`。应用不会自行伪造周一或周日刷新时间。

**开机启动无效？**  
需要把 `CodexMeter.app` 放到「应用程序」文件夹，并在「系统设置 → 通用 → 登录项」中允许。

**会不会留下 `codex app-server` 僵尸进程？**  
退出应用时会 terminate 子进程。如果异常退出，可在活动监视器中结束残留的 `codex app-server`。

## 项目结构

```text
CodexMeter.xcodeproj
Package.swift
Sources/
  CodexMeterCore/
    Models/
    Services/
    Utilities/
  CodexMeter/
    App/
    ViewModels/
    Views/
    Resources/
Tests/
  CodexMeterCoreTests/
Scripts/
  package-app.sh
  generate-xcodeproj.py
```

分层关系：

```text
View → ViewModel → CodexQuotaService → CodexAppServerClient
```

View 不直接启动 Process。额度 JSON 先进入 DTO / Parser，再变成 `CodexQuotaSnapshot`。

## 版本

- Version `1.2.0`
- Build `3`
- Bundle Identifier `com.local.CodexMeter`
- Deployment Target macOS 13.0

### 今日实时用量

“今日 · 本机实时”每 5 秒增量读取 `$CODEX_HOME/sessions` 和 `archived_sessions`（默认 `~/.codex`）中的 OpenAI Codex `token_count` 记录。应用启动时补算当天，模型响应写入日志后更新，不是流式逐 Token 计数。今日及相关周合计／峰值使用该值；昨日及更早日期继续使用 Codex 官方统计，累计值避免重复加入官方当天桶。

本机日志不包含其他设备、远程主机或云端任务，也不能完整按登录账号隔离。切换账号不会把本机日志自动拆成不同账户的今日用量。界面明确标注本机口径；日志不可读时不伪造实时数值。程序不修改会话日志、不上传其内容。

日历悬浮提示使用原生 SwiftUI 悬浮层，和顶部统计卡统一采用万／亿 Tokens 格式；点击可固定详情。

周视图按周一至周日汇总历史 Token，用一列方块表示一周，蓝色方块数量对应周用量；一屏最多 26 周，可以翻页查看更早记录。悬停显示日期范围及该周合计，点击可固定详情。本周累计至今日，包含本机实时用量；月视图继续按天展示。

### 重置卡信息

用量图下方在有可用重置卡时显示“使用限额重置”板块，包含可用次数、每张卡的重置类型及本地时区到期时间，支持展开／收起。信息随额度刷新读取；零张、接口不支持或全部到期时隐藏。后端仅返回数量时保留数量并提示暂无明细。本板块只读，不提供兑换或消耗重置卡的操作。

### 账号切换检测

每次额度刷新会先读取用户信息及额度，再统一选择账号标识：优先使用 `account/rateLimits/read` 的 `accountId`，缺失时才回退到 `account/read` 的标识。这样不会把同一账号的邮箱和 UUID 误判成两个账号。检测到账号变化时，Codex Meter 会停止旧 `codex app-server`，清理旧账号的额度快照、Token 日用量、重置卡、历史采样和本机实时统计索引，再启动新的 app-server 读取新账号。账号标识缺失时不会猜测切换，避免误清理数据。

账号刷新时会向 `account/read` 传递 `refreshToken: true`。用户信息为空或读取失败时，仍会尝试读取额度；有效额度响应不会被可选用户信息阻断。点击“刷新数据”会真正停止旧 app-server 并启动新进程；定时刷新继续复用连接。

### 官方 App 已安装，但提示未检测到 Codex

请先确认 Codex Meter 为 v1.2.0 或更新版本。v1.1.0 的下载包尚未支持新版官方 App 的内置 CLI 路径，仅点击“重新检测”不会升级程序。

新版先通过 macOS 注册的 Bundle ID `com.openai.codex` 和运行中的应用定位安装目录，并兼容以下内置布局：

- `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`
- `Contents/Resources/codex-cli/bin/codex`
- `Contents/Resources/codex`
- `Contents/MacOS/codex`

不要求用户在 shell 中配置 PATH。自动检测仍未找到时，点击“选择 Codex App”，直接选择已安装的 `.app` 即可；设置页同样支持选择 App 或独立 CLI。旧路径缓存不存在时会继续检测其他路径。
