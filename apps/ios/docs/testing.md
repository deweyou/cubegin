# 验证

## 自动化测试与 CI

单测使用固定输入、隔离存储和可控时间。UI 测试使用稳定的可访问性标识、条件等待
和独立的成绩文件。涉及视觉或设备交互的改动，在 PR 中记录验证方式和结果。

App 单测位于 `CubeginTests/`，通过正式工程的 `CubeginApp` scheme 执行。覆盖
计时输入和中断、打乱预取、成绩迁移和读写、分组和罚时，以及从 mo3 到 ao10000
的滚动统计。计时用例使用固定打乱、可控的单调时间和独立的临时存储。

`CubeginUITests/` 通过同一个 scheme 运行。当前 XCUITest 从冷启动开始，等待真实 SDK
生成三阶打乱，长按并松开开始计时，点按停止，标记 DNF，再重启 App 打开成绩详情并校验
罚时和原打乱。Debug App 根据测试会话 ID 使用独立的临时成绩文件，两次启动共用该文件。
辅助公式用例切换 Cross 和 XCross，核对转体在公式开头，直接拖动两条解法，并验证重新打开时恢复上次方法和顺序。单测验证不同项目、分组和方法的偏好隔离，以及新打乱按保存的目标顺序显示。训练界面用例通过项目弹窗的分段按钮选择训练项目，检查简单 XCross 显示入口、PLL 隐藏入口。使用 SDK 验证简单十字与简单 XCross 只返回 D 面，以及 F2L 训练省略已完成的 Cross。
横屏用例另外检查双栏内容、右侧三个 Tab 的切换、开表时隐藏侧栏且数字横纵居中、停表后回到右栏、
从左侧和原侧栏区域点按停表、转屏时保留成绩详情，以及项目列表滚回顶部后可选择三阶速拧。
横屏成绩用例检查统计内容滚动时经过固定的分组和视图按钮，并验证概要下方的趋势、分布切换和筛选控件。旋转到灵动岛在右的一侧后，检查图表控件和单次成绩行均避开导航列。
左右横屏分别记录计时首页、单次成绩、平均成绩、统计和设置截图，比较页头与卡片的左右边界，并检查成绩行的触摸区域与侧栏分开。
竖屏记录首页、单次成绩和设置的边距，并检查成绩列表滚过固定的分组和视图按钮后，按钮仍可操作。
各设备共用就绪反馈延时。就绪后持续按住 150 毫秒才显示松手提示，快速松手直接进入观察或计时。上滑取消在触屏就绪后即可触发。
在支持触感的真机上，开启「计时触感」，分别用零启动延迟和非零启动延迟长按，确认松手提示出现时和停表时各触发一次重档触感。检查提示出现前松手、滑入取消区或启用 WCA 观察时不触发就绪触感。关闭设置后重复长按和停表，确认两处都无触感。
计时页统计在分组零把时隐藏。第一把后显示次数，有有效成绩时显示总平均和最好单次。窗口满后才显示对应滚动平均，结果为 DNF 的窗口也要显示。

成绩庆祝以当前项目的当前分组为准。保存首次有效成绩或严格打破已有单次、Ao5、Ao12 纪录时，先显示成绩，等待 0.2 秒后自动播放。同一条成绩命中多项纪录时合并展示一次，首次有效 Ao5 或 Ao12 和追平纪录均不触发。单测覆盖手动保存、分组隔离、判罚后部分纪录仍成立，以及恢复判罚后自动播放去重。

符合条件的最新成绩在 +2、DNF 和删除之后显示礼花按钮。点按立即重播，在等候自动播放时点按也只播一次。改判罚后没有任何纪录时隐藏，改回来时恢复按钮。界面用例验证首次停表自动播放、改为 DNF、恢复后只允许手动重播，以及删除后入口消失。

彩纸从屏幕底部左右两角贴边喷出。每项纪录在计时页底部居中显示一颗单行的系统玻璃胶囊，多项时竖排，提示淡入后再淡出。单次和首次成绩让计时读数放大、轻微左右晃动，Ao5、Ao12 的动画应用在概要里对应的数字上。首次播放后，对应数字持续使用成绩列表的最佳成绩绿色，重播时保持绿色。更换最新成绩或判罚使某项纪录失效时，按当前成绩重新判断。普通 iPhone 的胶囊紧贴底部导航上方，Duo 半折竖屏时，提示显示在上半屏底部，按钮下方空间不足时靠右避让成绩和操作区。彩纸从上半屏的底部两角喷出。动画期间仍可点按计时页控件。UI 测试覆盖同次刷新三项纪录时胶囊的顺序、对齐和自动消失。开启系统「减少动态效果」后检查成绩保持静态。

计时显示需覆盖实时、到秒和仅观察。检查 WCA 观察读数和停表后的三位小数，并确认切到手动后轻点计时区直接打开录入。手动录入覆盖分格从左到右输入、高亮当前格、点选改单格、非零时可提前保存、秒位校验、+2、空时间 DNF、取消和保存失败重试。只有保存成功才推进打乱。成绩详情的无惩罚、+2 和 DNF 始终单选。零秒 DNF 在详情及计时页均不可修改判罚。iPhone 竖屏录入时对照键盘弹出前后的截图，确认底部面板贴着键盘，背后的计时页保持原位。检查小窗口和横屏键盘弹出后，判罚和保存操作仍可到达。

手势单测验证默认左扫生成新打乱、右扫删除上一条成绩，已保存的选项优先。界面用例从「设置 → 计时 → 手势」分别设置左右轻扫，重启后验证生成新打乱和单次手动录入。保存后仍可继续计时。删除快捷操作弹出确认框，确认后更新读数。选「无」时轻扫不执行操作。横向位移超过 10 pt 会退出按住状态，达到 44 pt 且方向明确才会触发快捷操作。检查两阈值之间的短拖动、长按后的横向拖动和观察期间的上滑取消。

Duo 半展开竖屏用例检查 WCA 观察和计时读数保持在上半屏中央。停表后，成绩操作出现在上半屏读数下方。待机时，下半屏显示项目和打乱工具栏、打乱图与成绩概要、计时提示。计时期间，下半屏只显示居中的停表提示。验证开表、上滑取消、停表和加两秒。
待机布局还需检查三阶和五魔方，确认五魔方的七行打乱清晰可读，公式和待机读数有足够间距。
触屏与空格均在显示松手提示时将读数移到上半屏中央，并同时收起打乱图和成绩概要。上滑取消只用于触屏输入。
WCA 观察期间也收起打乱图与成绩概要，按住或上滑取消时观察读数继续更新。普通计时显示松手提示时，读数归零为 `0.000`，取消后恢复之前的读数。
进入 WCA 观察和从观察开表都在松手时生效，无需等待设置的长按时长。普通计时仍按设置判断长按时长。
成绩、统计和设置共用顶部柔和滚动边缘。调整固定页头或滚动效果时，三页一起检查，覆盖 iPhone、iPad 和 Duo 的竖屏及横屏布局。确认内容从页头下方滚过、页头保持固定，Duo 外屏的侧栏区域也没有滚动条遮挡。
长成绩用例通过独立的 Debug 测试会话检查计时显示上限、+2 操作和五项 Summary 长成绩，并保留截图。

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test

xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'generic/platform=iOS' -configuration Release \
  CODE_SIGNING_ALLOWED=NO build

swift test --package-path ../..
```

也可在 Xcode 选中 `CubeginApp` 和已安装的 iOS 模拟器后按 ⌘U。命令中的模拟器
名称可换成 `xcrun simctl list devices available` 列出的设备。只运行 UI 测试时，
在上述 `xcodebuild test` 命令加上 `-only-testing:CubeginUITests`。

[仓库 CI](../../../.github/workflows/apple.yml) 在 PR、推送到 `main`、合并队列及手动触发时运行。
CI 使用 arm64 macOS 和 Xcode 26.2。iOS Release 和模拟器测试构建复用同一份 XCFramework。
两组 iPhone 17 Pro 模拟器检查下载同一份 App 和测试产物，在各自 runner 上串行执行组内用例。
需要时安装 iOS 26.2 runtime 或创建对应机型。测试结果分别以
`app-test-results-simulator-a` 和 `app-test-results-simulator-b` 上传，保留 14 天。
设备构建用于验证编译和链接，安装及交互见下方。分组、重跑及计时见[CI 验收](../../../docs/ci.md#ios-模拟器分组)。

## 界面一致性与布局必验清单

新增或修改界面时，先找出应用里承担同类任务的页面和组件。交付时记录对照页面、
实际验证的设备和窗口状态，以及未覆盖的场景。

- **先找参照，再实现**：检查现有的分段切换、项目选择、列表行、排序柄、选中标记、工具栏和弹层。交互相同且样式契约一致时复用同一个组件或布局规则，例如项目和成绩类型共用 `CapsuleSegmentButton`，分组和辅助公式共用 `ListReorderHandle`。需要共享一套样式时，把规则放在共同组件里。
- **新旧场景并排验收**：在同一设备、窗口尺寸和状态下，对照文字基线、边距、间距、字号、图标尺寸和颜色，分别验证默认、选中、展开、排序及不可用等实际存在的状态，再点按或拖动确认行为一致。系统安全区或任务差异导致的有意变化，在验收记录里说明原因。共享组件有改动时，回看受影响的现有页面。
- **可测的布局关系写入回归**：入口是否可点、同一行上的对齐、面板边界等能稳定断言的行为，优先补到已有 UI 测试里。外观细节用同尺寸截图对照。

顶栏、项目选择器或弹层变更还要完成对应的设备检查：


- **成对入口**：对照项目图标和 ✨ 的垂直中心及可见图标到各自可用内容边缘的距离。计算留白时区分图标和点击区，并考虑系统安全区、iPad 窗口按钮、Duo 折痕和状态栏。分别点按两侧，确认操作正确，入口隐藏时不会把另一项移动到它原来的位置。
- **窗口与长文案**：顶栏变更覆盖 iPhone 受影响的方向、iPad 全屏与窄窗口、Duo 受影响的外屏和内屏姿态。iPad 顶部 Tab 仍可见时把窗口缩到接近切换布局的宽度，用测得最宽的训练项目检查单行省略、图标和箭头仍可见、按钮可点，列表与辅助功能保留完整名称。
- **弹层**：在受影响的窄窗口或折叠姿态检查 Popover 和 modal 的轮廓、关闭入口、内容滚动及最后一项可达。对照实际截图确认面板落在窗口内。调整分段、选中勾号或展开箭头时，检查窄窗口内与文字的比例，以及收起和展开两种状态。

## 模拟器与交互验证

Debug 构建传入 `--measure-picker` 可按默认动态字体逐项测量中英文项目按钮。
结果写入模拟器 App 容器的 `Documents/picker-widths.json`，包含 220 条记录。
`compactPicker` 和 `regularPicker` 包含选中态图标、训练文案、箭头及最小点击宽度。
窗口控制区、工具栏系统留白和辅助公式图标占位需另计。分别在 iPad 全屏和约 697 pt 宽、仍显示顶部 Tab 的浮窗运行 `PadChartTests/testPadTopBarKeepsLongTrainingProjectAccessible`。用例选择默认字号下测得最宽的训练项目 `RLDX center solved`，检查项目与 Tab 的间距、可点按和完整可访问性名称。全屏检查完整标题，浮窗检查按钮留出部分标题宽度，并通过截图确认单行省略。

App 命令在 `apps/ios/` 执行。正式运行 scheme 是 CubeginApp。

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

定向运行时用 xcrun simctl list devices available 获取设备 UUID，以
platform=iOS Simulator,id=<UUID> 作为 destination。在 Xcode 27 使用 Device Hub
显示设备窗口；老版本的 Simulator.app 路径不适用于当前安装。

Core 更新后至少执行：独立包消费者测试、正式 App 新构建、模拟器
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

本地调试默认安装 **Cubegin Dev**。独立的 Bundle ID `io.github.deweyou.cubegin.dev`
为它创建单独的成绩和设置容器。普通 Cubegin Dev 使用本机设置。下方专用签名构建可以验证 Dev 的 iCloud 设置和成绩同步。

Xcode 需登录开发者账号并完成 Apple 要求的协议更新，设备需配对并启用开发者模式。
用 `xcrun devicectl list devices` 获取 UDID。在 `apps/ios/` 下将命令中的
`<UDID>` 和 `<TEAM_ID>` 替换为实际值，然后构建：

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'platform=iOS,id=<UDID>' -configuration Debug \
  -derivedDataPath /tmp/cubegin-ios-device-dev -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  PRODUCT_BUNDLE_IDENTIFIER=io.github.deweyou.cubegin.dev \
  'INFOPLIST_KEY_CFBundleDisplayName=Cubegin Dev' CODE_SIGN_ENTITLEMENTS= build
```

安装前核对实际产物的 Bundle ID 和显示名称。两项分别是
`io.github.deweyou.cubegin.dev` 和 `Cubegin Dev` 时，再安装并启动：

```sh
dev_app=/tmp/cubegin-ios-device-dev/Build/Products/Debug-iphoneos/cubegin.app
test "$(plutil -extract CFBundleIdentifier raw -o - "$dev_app/Info.plist")" = io.github.deweyou.cubegin.dev &&
  test "$(plutil -extract CFBundleDisplayName raw -o - "$dev_app/Info.plist")" = 'Cubegin Dev' &&
  xcrun devicectl device install app --device <UDID> "$dev_app" &&
  xcrun devicectl device process launch --device <UDID> io.github.deweyou.cubegin.dev
```

签名构建、安装成功、启动成功与真机画面或交互验收应分开记录。

### iCloud 成绩同步验证

同步验证使用 Cubegin Dev App ID。开发签名须启用 CloudKit、iCloud 键值存储，并关联
`iCloud.io.github.deweyou.cubegin.sync-prototype` 容器。按上面的真机构建命令，
将空的 `CODE_SIGN_ENTITLEMENTS=` 替换为以下两个构建参数。

```sh
CODE_SIGN_ENTITLEMENTS=Cubegin/CubeginResultsSyncDev.entitlements \
'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CUBEGIN_RESULTS_SYNC'
```

两台已登录同一 iCloud 账号的测试设备分别预置一条不同的测试成绩。打开「设置 → 通用 → iCloud 同步」，
验证首次合并、编辑罚时、离线删除后重试，以及更换 iCloud 账号后本机成绩保留。先核对测试设备和专用容器，
再打开开关。两台设备的测试成绩都可见后再验证删除。改变主题或报时设置，确认两台设备会同步。关掉一台设备上的开关，确认它仍可本地修改设置和成绩，并停止接收另一台设备的新修改。

模拟器用 Debug 启动参数 `--preview-icloud-error` 模拟网络失败，可检查同步开关、错误提示和重试。
单测用内存服务验证合并和重试，全程使用临时成绩文件。
