# StepAway

[English](README.md) | 中文

一个 macOS 菜单栏应用：运行工作/休息循环，并且知道什么时候该闭嘴。当你空闲、
在会议中、在共享屏幕、处于全屏或专注应用、或者不在工作时间内时，提醒会自动挂起
——只在真的能站起来走开的时候才出现。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#环境要求)

## 功能

**计时** — 工作 20 分钟、短休息 20 秒、每 4 次短休息后长休息 5 分钟，所有时长均可
配置。菜单栏显示剩余时间（休息中为 `☕`，手动暂停为 `⏸`，被检测器暂停为 `◐`）。

**休息遮罩** — 覆盖每一块屏幕，并加入全屏应用所在的 Space，而不是把你从全屏里拽出来。
背景由 Metal 着色器实时渲染（极光 / 等离子 / 射线），显卡不可用时回退到渐变。遮罩默认
通过 `NSWindow.sharingType = .none` 排除在屏幕录制之外。

**休息前提示** — 遮罩出现前 60 秒给出提示，方便你收尾。

**跳过休息** — 休息满 10 秒后，遮罩底部淡入「跳过休息」按钮，点击消耗一次每日跳过额度；
额度用完则不显示，因此任何一次休息都不会在真正发生之前被跳过。

**长休息锁屏** — 长休息第 20 秒通过 `login.framework` 的私有接口
`SACLockScreenImmediate`（⌃⌘Q 背后的调用）锁屏，回到电脑前需要解锁。按钮出现的
10 秒内跳过则会取消，短休息从不锁屏。默认开启，可在设置里关掉；若将来系统移除该符号，
会回落到 `pmset displaysleepnow`。

**自动暂停** — 检测器每 5 秒轮询一次，判定需连续两次命中才暂停、连续两次未命中才恢复，
避免一个偶然的窗口让计时器来回抖动。

| 检测器 | 触发条件 |
| --- | --- |
| 空闲 | 5 分钟无输入，说明你已经离开了 |
| 会议 / 屏幕共享 | 摄像头或麦克风正在被使用 **且** 已知的会议客户端在运行 |
| 全屏应用 | 非播放器的应用拥有全屏窗口（游戏、沉浸式应用） |
| 视频播放 | 已知视频播放器拥有全屏窗口 |
| 日历事件 | 进行中的非全天事件（需授予日历权限） |
| 工作时间 | 超出配置的工作时段（支持跨午夜区间） |
| 专注应用 | 你标记为专注的应用处于前台（默认关闭） |

日历、屏幕共享、全屏、视频、工作时间检测可分别开关；其中工作时间与专注应用默认关闭。
应用可通过忽略列表排除。

**额度约束** — 跳过和推迟是有限额的：每天 3 次跳过、30 分钟推迟，本地时间 0 点重置，
菜单栏会显示剩余额度。系统睡眠时计时暂停，唤醒后自动校正剩余时间。重复启动会直接退出，不会起第二个实例；打包
后的 app 还会把已在运行的实例切到前台。

**全部本地化** — 无网络访问。设置保存在 `UserDefaults`，休息统计与每日额度保存在
`~/Library/Application Support/StepAway/`（`stats.json`、`quotas.json`）。

## 环境要求

- macOS 13 Ventura 或更高版本
- Swift 5.10 工具链（Xcode 15+ 或独立 Swift 工具链）

## 构建与运行

```sh
swift build                # 编译
swift run StepAway         # 以裸进程运行
swift run StepAway --demo  # 8 秒工作 / 6 秒休息的演示节奏，演示设置不写入 UserDefaults
```

演示模式仍会记录休息统计。若不想污染真实统计：

```sh
STEPAWAY_STATS_PATH=/tmp/stepaway-demo.json swift run StepAway --demo
```

打包成可启动的 app：

```sh
./Scripts/make-app.sh      # release 构建、生成并 ad-hoc 签名 build/StepAway.app
open build/StepAway.app
```

日常使用请运行打包后的 app：它设置了 `LSUIElement`（仅菜单栏）并带有
`NSCalendarsUsageDescription`，EventKit 需要该键才会让 macOS 弹出日历授权提示。

## 使用

启动后从菜单栏点开 `设置…`（⌘,）进行配置。

| 菜单项 | 快捷键 | 说明 |
| --- | --- | --- |
| Pause / Resume | ⌘P | 手动暂停；恢复时标题会显示检测到的原因 |
| Start break now | ⌘B | 跳过剩余工作时间，立即休息 |
| Skip break | ⌘S | 仅休息中可用，消耗一次每日跳过额度 |
| Postpone | — | 仅工作阶段可用，消耗每日推迟额度 |
| 忽略当前应用 | — | 让前台应用不参与检测器判定 |
| 标记当前应用为专注应用 | — | 把前台应用加入专注列表（需先开启该检测器） |
| Quit | ⌘Q | 退出 |

## 开发

```sh
swift run StepAway --selftest   # 确定性检查；退出码 = 失败数量
```

自测覆盖计时状态机、检测器、额度与统计持久化、实例锁和 Metal 着色器可用性，不依赖
UI，可无人值守运行；但着色器检查需要可用的 GPU，在无显卡的机器上会失败。

目录结构：

- `Sources/StepAway/Core` — 计时引擎、设置、统计/额度存储、检测器协议
- `Sources/StepAway/Detectors` — 每个自动暂停信号一个类型
- `Sources/StepAway/UI` — 菜单栏、休息遮罩、休息前提示、设置窗口
- `Scripts/make-app.sh` — app bundle 打包脚本

检测器保持轻量且无副作用：只按轮询间隔给出判定，不自行改变状态。

环境变量覆盖（主要用于测试与本地截图）：

- `STEPAWAY_STATS_PATH`、`STEPAWAY_QUOTA_PATH` — 改变 JSON 存储位置
- `STEPAWAY_SHOW_IN_CAPTURE=1` — 让遮罩出现在屏幕录制中

## 已知限制

- 构建为 ad-hoc 签名、未公证，首次启动可能需要在 Gatekeeper 中手动确认。
- 屏幕共享检测是启发式的：macOS 没有公开查询“是否有其他应用正在截屏”的接口，因此改为
  观察摄像头/麦克风是否在被占用，并结合会议客户端是否在运行。
- 界面目前仅中文；bundle identifier（`com.example.stepaway`）是占位值，分发前需替换。

## 参与贡献

欢迎提交 issue 和 pull request。提交前请运行 `swift build` 与
`swift run StepAway --selftest`，并保持 `Sources/StepAway/Detectors` 中的逻辑无副作用，
以便持续可测。

## 许可证

[Apache License 2.0](LICENSE)
