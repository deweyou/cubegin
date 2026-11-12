# 验证

## 自动化测试与 CI

App 单测位于 `CubeginTests/`，通过正式工程的 `CubeginApp` scheme 执行。覆盖
计时输入和中断、打乱预取、成绩迁移和读写、分组和罚时，以及从 mo3 到 ao10000
的滚动统计。计时用例使用固定打乱、可控的单调时间和独立的临时存储。

`CubeginUITests/` 通过同一个 scheme 运行。当前 XCUITest 从冷启动开始，等待真实 SDK
生成三阶打乱，长按并松开开始计时，点按停止，标记 DNF，再重启 App 打开成绩详情并校验
罚时和原打乱。Debug App 根据测试会话 ID 使用独立的临时成绩文件，两次启动共用该文件。
横屏用例另外检查双栏内容、右侧三个 Tab 的切换、开表时隐藏侧栏且数字横纵居中、停表后回到右栏、
从左侧和原侧栏区域点按停表、转屏时保留成绩详情，以及项目列表滚回顶部后可选择三阶速拧。
横屏成绩用例检查统计内容滚动时经过固定的分组和视图按钮，并验证概要下方的趋势、分布切换和筛选控件。旋转到灵动岛在右的一侧后，检查图表控件和单次成绩行均避开导航列。
左右横屏分别记录计时首页、单次成绩、平均成绩、统计和设置截图，比较页头与卡片的左右边界，并检查成绩行的触摸区域与侧栏分开。
竖屏记录首页、单次成绩和设置的边距，并检查成绩列表滚过固定的分组和视图按钮后，按钮仍可操作。
成绩、统计和设置共用顶部柔和滚动边缘。调整固定页头或滚动效果时，三页一起检查，覆盖 iPhone、iPad 和 Duo 的竖屏及横屏布局。确认内容从页头下方滚过、页头保持固定，Duo 外屏的侧栏区域也没有滚动条遮挡。
长成绩用例通过独立的 Debug 测试会话检查计时显示上限、+2 操作和五项 Summary 长成绩，并保留截图。

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test

xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'generic/platform=iOS' -configuration Release \
  CODE_SIGNING_ALLOWED=NO build

swift test --package-path Vendor/CubeginSDK
```

也可在 Xcode 选中 `CubeginApp` 和已安装的 iOS 模拟器后按 ⌘U。命令中的模拟器
名称可换成 `xcrun simctl list devices available` 列出的设备。只运行 UI 测试时，
在上述 `xcodebuild test` 命令加上 `-only-testing:CubeginUITests`。

[App checks](../.github/workflows/check.yml) 在 PR、推送到 `main`、合并队列及手动触发时运行。
`iOS build and tests` 使用 arm64 macOS 和 Xcode 26.2，执行无签名 iOS Release
构建、iPhone 17 Pro（iOS 26.2）App 单测、XCUITest 和随仓 SDK 消费测试。测试结果
`AppTests.xcresult` 生成后保留 14 天。设备构建用于验证编译和链接，安装及交互见下方。
合入前应通过该检查。GitHub 将其设为必需状态检查需要单独配置仓库规则。

## 模拟器与交互验证

Debug 构建传入 `--measure-picker` 可按默认动态字体逐项测量中英文项目按钮。
结果写入模拟器 App 容器的 `Documents/picker-widths.json`，包含 220 条记录。
`compactPicker` 和 `regularPicker` 包含选中态图标、训练文案、箭头及最小点击宽度。
窗口控制区、工具栏系统留白和训练图标占位需另计。

所有命令在本仓库根目录执行。正式运行 scheme 是 CubeginApp。

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

定向运行时用 xcrun simctl list devices available 获取设备 UUID，以
platform=iOS Simulator,id=<UUID> 作为 destination。在 Xcode 27 使用 Device Hub
显示设备窗口；老版本的 Simulator.app 路径不适用于当前安装。

SDK 更新后至少执行：安装文件校验、独立包消费者测试、正式 App 新构建、模拟器
运行。不要用没有 SDK 的 Preview 工程通过构建来证明核心接入成功。

手动检查真实打乱和 SVG 显示、项目切换、开始/停止、成绩重启后保留、后台中断取消、
错误提示以及 Cross 输出。检查 iPhone/iPad 尺寸、横竖屏、浅色/深色、字体放大、
VoiceOver 和降低透明度。计时器核心状态改变时应补充独立时钟/存储验证，避免只测视图。

host SwiftPM 测试验证 SDK 调用与消费；模拟器截图验证特定运行画面；签名真机运行、
设备渲染、完整交互验收和发布均为独立结果，不可相互替代。

## 开屏视觉调试

Debug 安装后，先终止 App，再用以下命令启动即可持续停留在开屏：

```sh
xcrun simctl terminate booted io.github.deweyou.cubegin
xcrun simctl launch booted io.github.deweyou.cubegin --hold-launch-screen
```

通过 `xcrun simctl ui booted appearance light` / `dark` 比较两种外观。
移除参数并重新启动即恢复一次性动画和自动进入计时页；Release 不启用停留模式。

## 系统启动画面

本地模拟器也需要临时签名：未签名包会被 SplashBoard 以资源安全校验错误 -67056
拒绝生成启动快照，出现黑屏。这与 SwiftUI 动画首帧是不同阶段。上面的构建命令使用
本地 ad-hoc 签名，不需要开发者账号或真机签名配置。

可用 `xcrun simctl launch --wait-for-debugger booted io.github.deweyou.cubegin`
暂停 App 代码，单独检查系统静态启动画面；检查后 terminate，再正常 launch。
启动页 PNG 可用 `xcrun swift scripts/generate-launch-images.swift "$PWD"` 从原 SVG
重新生成，保持布局与 LaunchView 一致。

## 多尺寸开屏检查

检查 iPad 横竖屏（含倒置）以及 Duo 合拢、半展开、展开状态；每种状态分别检查系统
静态页、`--hold-launch-screen` 和正常冷启动，并切换深浅色。系统页与动画页都应按
完整窗口居中，不能只检查动画最终截图。系统页可用暂停调试器的方法单独观察。
Duo 多显示器截图要明确选择当前屏幕，不能默认读取外屏：先用
`xcrun simctl io <UUID> enumerate` 确认 Screen ID。验证范围和未完成项见 docs/status.md。

## 本地真机安装

Xcode 需登录开发者账号并完成 Apple 要求的协议更新，手机需配对并启用开发者模式。
`xcrun devicectl list devices` 获取物理设备 UDID。可用命令行覆盖签名团队和版本，
避免将个人签名配置写进工程：

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'platform=iOS,id=<UDID>' -configuration Debug \
  -derivedDataPath /tmp/cubegin-ios-device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> CURRENT_PROJECT_VERSION=1 MARKETING_VERSION=0.1.0 build
xcrun devicectl device install app --device <UDID> \
  /tmp/cubegin-ios-device/Build/Products/Debug-iphoneos/cubegin.app
xcrun devicectl device process launch --device <UDID> io.github.deweyou.cubegin
```

签名构建、安装返回成功、启动返回成功与真机画面/交互验收应分开记录。
