# Codex Meter

**Codex 额度监控** — 一个轻量的原生 macOS 菜单栏工具，用来查看当前本机已登录 Codex 账户的**周额度**。

打开菜单栏图标后，大约一秒内就能看清：

- 本周还剩多少额度
- 什么时候刷新
- 当前消耗节奏是否偏快

不抓网页，不读 Cookie，不解析 `auth.json`，也不要求填写 OpenAI API Key。额度只来自本机已经登录的 Codex。

## 截图位置说明

仓库根目录的 `原型图.png` 是早期金额式 Dashboard 草稿，**不是**当前界面。当前产品只展示周额度百分比，不会显示美元金额。

应用运行后：

1. 顶部菜单栏右侧出现带字母 `C` 的图标
2. 点击图标弹出约 380pt 宽的浮层
3. 浮层直接显示本周剩余百分比、刷新时间和最近趋势

## 功能

- 菜单栏常驻，默认不出现在 Dock
- 自动发现本机 `codex` 可执行文件
- 持久化运行 `codex app-server`，通过 JSON-RPC 读取额度
- 识别 10080 分钟（7 天）的 Weekly Limit
- 使用 Codex 返回的真实 `resetsAt`，不会假设周一或周日刷新
- 监听 `account/rateLimits/updated`，额度变化时立即更新
- 1 / 5 / 10 / 30 分钟保险轮询，默认 5 分钟
- 本地缓存最近快照与 30 天历史趋势
- 剩余 30% / 15% / 5% 系统通知，同一周周期每个阈值只提醒一次
- 周额度刷新后可发送一次通知
- 开机启动、菜单栏百分比、Codex 路径均可在设置中调整
- 浅色 / 深色模式

## 系统要求

- macOS 13.0 或更高
- 已安装并完成 ChatGPT 登录的 [Codex CLI](https://github.com/openai/codex)
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
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `~/.local/bin/codex`
6. `~/.npm-global/bin/codex`
7. `~/.codex/plugins/.plugin-appserver/codex`
8. 登录 shell：`/bin/zsh -l -c "command -v codex"`

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

主界面只展示总体 Weekly Limit。5 小时额度或模型专属 bucket 不会铺到主界面。

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

- Version `1.0.0`
- Build `1`
- Bundle Identifier `com.local.CodexMeter`
- Deployment Target macOS 13.0
