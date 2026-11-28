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
触屏和空格在按住期间保留计时首页布局和原读数。启动延迟为零时，按下立即变绿。启动延迟大于零时，按下变红，到时变绿。提前松手恢复原色，达到延迟后松手进入观察或计时。上滑取消在触屏就绪后即可触发。
在支持触感的真机上，开启「计时触感」，分别用零启动延迟和非零启动延迟长按，确认变绿后继续按住 150 毫秒时和停表时各触发一次重档触感。检查触感触发前松手、滑入取消区或启用 WCA 观察时无就绪触感。关闭设置后重复长按和停表，确认两处都无触感。
计时页统计在分组零把时隐藏。第一把后显示次数，有有效成绩时显示总平均和最好单次。窗口满后才显示对应滚动平均，结果为 DNF 的窗口也要显示。

成绩庆祝以当前项目的当前分组为准。保存首次有效成绩或严格打破已有单次、Ao5、Ao12 纪录时，先显示成绩，等待 0.2 秒后自动播放。同一条成绩命中多项纪录时合并展示一次，首次有效 Ao5 或 Ao12 和追平纪录均不触发。单测覆盖手动保存、分组隔离、判罚后部分纪录仍成立，以及恢复判罚后自动播放去重。

刷新纪录的有效成绩在最后一位数字右上角显示倾斜的金色皇冠。单次是实心皇冠，Ao5 和 Ao12 在皇冠内分别镂空 `5`、`12`。同一把刷新多项时，皇冠按单次、Ao5、Ao12 的顺序选一项，庆祝提示列出所有纪录。皇冠随读数缩放，按住、观察、开表或失去纪录后收起。首次成绩沿用首次庆祝提示。

符合条件的最新成绩在 +2、DNF 和删除之后显示礼花按钮。点按立即重播，在等候自动播放时点按也只播一次。改判罚后没有任何纪录时隐藏，改回来时恢复按钮。界面用例验证首次停表自动播放、改为 DNF、恢复后只允许手动重播，以及删除后入口消失。

彩纸从屏幕底部左右两角贴边喷出。每次庆祝在计时页底部居中显示一颗单行的系统玻璃胶囊。同一把刷新多项时按单次、Ao5、Ao12 排列在同一条提示中，提示淡入后再淡出。单次和首次成绩的庆祝动画应用在概要的 best 数值上，Ao5、Ao12 的动画应用在概要里对应的数字上。首次播放后，对应数字持续使用成绩列表的最佳成绩绿色，重播时保持绿色。更换最新成绩或判罚使某项纪录失效时，按当前成绩重新判断。普通 iPhone 竖屏的提示在底部导航上方预留 24 pt。Duo 半折竖屏时，提示显示在上半屏底部，按钮下方空间不足时靠右避让成绩和操作区。彩纸从上半屏的底部两角喷出。动画期间仍可点按计时页控件。单测覆盖八种提示的中英文文案。UI 测试覆盖首次成绩、仅 Ao12、Ao5 与 Ao12 同时刷新，以及三项纪录合并成一条提示后的对齐和自动消失。开启系统「减少动态效果」后检查成绩保持静态。

计时显示需覆盖实时、到秒和仅观察。检查 WCA 观察读数和停表后的三位小数，并确认切到手动后轻点计时区直接打开录入。手动录入覆盖分格从左到右输入、高亮当前格、点选改单格、非零时可提前保存、秒位校验、+2、空时间 DNF、取消和保存失败重试。只有保存成功才推进打乱。成绩详情的无惩罚、+2 和 DNF 始终单选。零秒 DNF 在详情及计时页均不可修改判罚。iPhone 竖屏录入时对照键盘弹出前后的截图，确认底部面板贴着键盘，背后的计时页保持原位。检查小窗口和横屏键盘弹出后，判罚和保存操作仍可到达。

左右轻扫默认均为「无」，已保存的选项优先。界面用例从「设置 → 计时 → 手势」分别设置左右轻扫，重启后验证生成新打乱和单次手动录入。保存后仍可继续计时。删除快捷操作弹出确认框，确认后更新读数。选「无」时轻扫不执行操作。从按下到就绪后 150 毫秒这段时间内，横向位移超过 10 pt 会退出按住状态并恢复读数原色，达到 44 pt 且方向明确才会触发快捷操作。之后横向或向下移动再松手会开始计时。检查两阈值之间的短拖动、长按后的横向和向下移动，以及计时前和观察期间的上滑取消。

在打乱公式上测试两个方向的快捷手势，打乱图、成绩概要和计时数字处测试长按启动。停表后短点成绩操作仍执行按钮动作，长按至少 250 毫秒且达到配置的启动延迟后，松手开始计时。成绩操作的点击区域高 44 pt。确认「项目」和「辅助公式」图标仍对齐原有内容边缘，并点按两者朝向页面中心的扩展区域。顶部按钮的点击区域至少为 64 × 44 pt。

Duo 半展开竖屏时，计时页根据系统报告的活动横向折痕启用上下布局。单测检查横向折痕的选择，以及完全展开、纵向折痕和超出页面的折痕。Duo 界面用例检查 WCA 观察和计时读数保持在上半屏中央。停表后，成绩操作出现在上半屏读数下方。待机时，下半屏在打乱图和成绩概要下方显示「轻点开始计时」「长按开始」或「轻点开始观察」。就绪后持续按住会显示松手提示。观察期间下半屏显示「轻点开始计时」，计时期间显示「轻点停止」。验证开表、上滑取消、停表和加两秒。
Duo 内屏展开横屏时，对照两个横屏方向，确认导航胶囊与右侧系统状态栏同列，首页、成绩和设置都可点。界面用例关闭机型匹配，验证 App 仍能根据系统折痕区域识别内屏并使用对应布局。
待机布局还需检查三阶和五魔方，确认五魔方的七行打乱清晰可读，公式和待机读数有足够间距。
触屏与空格均在松手进入观察或计时后才将读数移到上半屏中央，并收起打乱图和成绩概要。上滑取消只用于触屏输入。
WCA 观察期间，按住或上滑取消时观察读数继续更新。
进入 WCA 观察和从观察开表都在松手时生效，无需等待设置的长按时长。普通计时仍按设置判断长按时长。
成绩、统计和设置共用顶部柔和滚动边缘。调整固定页头或滚动效果时，三页一起检查，覆盖 iPhone、iPad 和 Duo 的竖屏及横屏布局。确认内容从页头下方滚过、页头保持固定，Duo 外屏的侧栏区域也没有滚动条遮挡。
评分邀请需要至少 12 条有效成绩，成绩日期覆盖至少 3 天。进入成绩列表并停留一秒后，App 每次安装最多请求一次。手动验收时可先快速切回计时页，再返回成绩列表，确认只有留在成绩列表时才请求。StoreKit 决定是否展示弹窗。

在「设置 → 关于 → 反馈与评价」检查原生表单。Cubegin Dev 的 Debug 构建可用 `-cubegin-show-feedback` 启动参数直达。正文、截图和选填邮箱应在同一张卡片里。截图和计数各靠一侧，在同一行底部对齐，和邮箱之间有分割线。空反馈或邮箱格式错误时，「发送反馈」应呈灰色，点击时显示具体原因。正文按 UTF-16 单元计数，iOS 表单去掉首尾空白后须在 1 至 200 个单位之间。接口接受旧客户端提交的最多 4,000 个单位。用键盘删除正文后，计数应归零。合法内容可在邮箱为空时发送。使用邮箱成功提交后，再次进入应预填同一地址。点邮箱清空按钮后，重新进入时应为空。正文下方应显示左对齐的虚线加号方格。附图应按顺序显示为等大的方形缩略图，加号紧随最后一张，选满三张时隐藏。移除任意缩略图后应能继续选图。验证接口失败后保留正文和截图，成功后清空表单。评价链接打开 App Store，网页支持入口也可独立提交。

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

冷启动后，从计时页首次进入「设置」或「成绩」，检查设置分组标题和成绩类型切换项的位置
用灰色占位保留，表单或真实成绩就绪后替换占位。成绩类型栏最多显示三个同款圆条，
每个成绩占位行用左长右短两个圆条保留行高。
设置骨架只显示一到两个分组，上下滑动时占位保持原位。返回再切入时保留已加载页面。计时页可用且空闲后
会预读当前分组的首批成绩。验证时在首次切页前也按住起表，确认计时输入和停止正常。
`SolveFlowTests.testFirstTabLoadingRevealsContentAndSubsequentVisitsReuseIt`
在测试中延长占位显示时间，以便断言首次和再次切入的界面。

将成绩切到 Ao5 或统计，来回切换标签检查视图保留。保存一次计时后进入成绩，确认显示当前项目单次列表的第一条。单次列表已滚到下方时也要置顶。切换项目回到新项目的单次列表第一条。

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

本地开发验收使用 Cubegin Dev App ID。开发签名须启用 CloudKit、iCloud 键值存储，并关联
`iCloud.io.github.deweyou.cubegin.sync-prototype` 容器。按上面的真机构建命令，
将空的 `CODE_SIGN_ENTITLEMENTS=` 替换为以下两个构建参数。

```sh
CODE_SIGN_ENTITLEMENTS=Cubegin/CubeginResultsSyncDev.entitlements \
'OTHER_SWIFT_FLAGS=$(inherited) -D CUBEGIN_RESULTS_SYNC'
```

正式候选用同一 TestFlight build 在两台真机验收，先确认签名使用正式容器，且 CloudKit Production 已部署 `CubeginResult` 记录类型和 Bytes 类型的 `payload` 字段。App 将成绩和分组分别存放在私有数据库的 `CubeginResultsV1` 和 `CubeginResultsV1Metadata` 区域。

两台已登录同一 iCloud 账号的测试设备分别预置一条不同的测试成绩。打开「设置 → 通用 → 同步」，
验证首次合并、编辑罚时、离线删除后重试，以及更换 iCloud 账号后本机成绩保留。先核对测试设备和专用容器，
再打开开关。两台设备都显示测试成绩后再验证删除。在其中一台设备改分组名称、拖动分组、设为默认组，
再切换项目、选择辅助公式方法并调整解法顺序。在另一台设备确认这些改动。改变主题或报时设置，确认两台设备会同步。
关掉一台设备上的开关，确认它仍可本地修改设置和成绩，并停止接收另一台设备的新修改。重新开启后验证本机离线修改传到另一台设备。
在新设备打开空的成绩页并保持当前页面，待另一台设备上传完成后，确认新成绩在下一轮前台同步完成时自动出现。
已有成绩时，在成绩页保持当前列表并等待本轮同步完成。看到「iCloud 成绩有更新」后，确认旧成绩仍在原位。点「刷新」，确认列表显示本机已经同步的成绩。

模拟器用 Debug 启动参数 `--preview-icloud-error` 或 `--preview-icloud-success`，可以从「设置 → 通用 → 同步」检查同步中、错误、成功时间和刷新。用 `--preview-icloud-upload` 检查上传状态右侧的计数及下方的进度条，关闭同步后确认上传提示消失。计数以这一轮待上传的成绩和元数据记录为单位。用 `--preview-icloud-account-error` 检查长错误文案换行时刷新图标是否与首行居中，并在系统最大字号下核对应用字体尺寸。
用 `--preview-icloud-late-results` 模拟首次拉取为空、第二次才收到成绩。界面测试验证后台同步在停留页面时收到成绩并展示。
同一个预览带已有成绩时，界面测试验证同步完成后先提示刷新，点按后才显示新成绩。分页单测用 8,126 条成绩检查首屏、下一页、滚动平均跨页窗口和分组筛选，并核对待刷新期间本机编辑和云端成绩隔离。
上传每批最多 100 条。CloudKit 回报请求超限时拆半重试。收到每批结果后，按实际保存或解决冲突的记录数推进计数。批内失败的记录留待重试，下一轮跳过已处理的记录。
单测用内存服务验证成绩和分组的合并、偏好同步、分批进度、冲突重试和超限拆批，全程使用临时成绩文件。
本机升级测试从两种旧版 JSON 格式迁入 SQLite，检查成绩、分组顺序、罚时、导入撤销、同步版本和删除标记。覆盖迁移失败后重试、写入事务回滚、再次启动跳过已完成迁移，以及大批迁移后只更新变更行。

## 真机验证故障诊断

在忽略提交的 `apps/ios/TelemetryConfig/` 中放置配置，也可通过
`CUBEGIN_TELEMETRY_CONFIG_DIR` 指定目录。Dev 和正式版使用独立的 Firebase 项目、
GA4 属性和 Sentry 项目。

| 构建 | Firebase 配置文件 | Sentry DSN 文件 |
| --- | --- | --- |
| 真机 Debug（Cubegin Dev） | `io.github.deweyou.cubegin.dev.plist` | `io.github.deweyou.cubegin.dev.sentry-dsn.txt` |
| 真机 Release（Cubegin） | `io.github.deweyou.cubegin.plist` | `io.github.deweyou.cubegin.sentry-dsn.txt` |

构建脚本按构建类型和 Bundle ID 选择配置，模拟器构建不打包配置。正式 Release 归档
或显式指定配置目录时，匹配的两个文件缺一都会中止。普通 Release 编译检查可以省略两份配置。
发布时设置实际的 App 版本和构建号。

按[本地真机安装](#本地真机安装)安装 Debug 版后，显式开启该次启动的诊断并启用 GA DebugView。

```sh
xcrun devicectl device process launch --device <UDID> --terminate-existing -- \
  io.github.deweyou.cubegin.dev -cubegin-telemetry-qa -FIRDebugEnabled
```

导入无效备份，在 GA4 DebugView 确认 `operation_failed`。用测试数据验证写入失败，
确认 GA4 同时记录失败，Sentry 的 `device_qa` 环境收到对应的非致命诊断。
核对两端手动错误都带有 `operation`、`reason` 和 `impact`。
核对 GA4 事件参数 `app_build` 与安装包的 `CFBundleVersion` 一致。
在 DebugView 查看 `operation_performance`，按参数 `operation` 核对各项记录。
完全退出后重新启动，等待计时页可操作，确认收到一次 `launch_to_timer_ready`。
切换项目、主动换打乱并完成一次计时，确认 `scramble_preparation` 的触发来源、缓存命中、
项目切换标记和当前项目 ID，以及 `scramble_diagram_ready` 的准备路径。
核对 `duration_ms` 为数值，事件参数中没有打乱或成绩内容。
打开统计页并切换分组，核对 `statistics_ready` 的两种触发来源和成绩量分桶。
使用尚未完成首次同步的 Dev 安装验证 `icloud_sync`，先在离线时触发失败，再联网重试。
检查 `outcome`、失败分类、网络类型以及本地和远端数据量分桶。
首次成功前的尝试使用 `sync_phase=initial`，首次成功后的尝试使用 `sync_phase=subsequent`。
在专用验证构建中触发测试崩溃后重启，确认 Sentry 收到崩溃。发布归档保留并上传匹配的 dSYM，
上传令牌配置在发布环境中。核对诊断中的设备 ID 与连点五次「版本」复制的值一致，再检查上报只包含预期字段。
发布前核对 Xcode 归档的隐私报告及 App Store Connect 隐私声明。

首次共享提示、「关于 → 隐私」入口、共享开关和行内政策链接由 `SolveFlowTests.testFirstLaunchSharingChoiceAndPrivacySettings` 验证。模拟器默认显示隐私页开关，网络上报关闭。用启动参数 `-cubegin-show-telemetry-consent` 预览首次共享提示。「关于 → 版本」按 `1.0.0(5)` 的格式显示安装包的版本与构建号。界面用例 `SolveFlowTests.testVersionCopiesHiddenDeviceIDOnFifthTap` 检查显示格式，并验证连点五次复制设备 ID。

## 产品埋点验证

按[真机验证故障诊断](#真机验证故障诊断)中的启动命令打开 Cubegin Dev，附加 `-cubegin-telemetry-qa-consent` 以使用本机共享选择。实际操作功能，在隔离的 GA4 DebugView 核对事件名称、触发次数和参数。涉及 UID 时，另外核对该事件原始上传数据中的 `user_id`。

验证跨设备埋点时，Cubegin Dev 同时使用专用 CloudKit 容器与隔离的 Firebase、Sentry 项目。使用[成绩同步验证](#icloud-成绩同步验证)中的签名授权与编译参数，保留 Firebase 包自己的编译条件。用新安装覆盖已有共享 ID、首次创建、离线超时后恢复三种情况。核对自动 `first_open`、`session_start` 实际出现的时机，以及原始数据中的 `user_id`。核对取消共享、关闭 iCloud 同步及切换 iCloud 账号时的身份切换。

正式构建使用容器 `iCloud.io.github.deweyou.cubegin`。发布前给正式 Bundle ID 关联此容器，并在 CloudKit Production 部署 `CubeginAnalyticsIdentity` 记录类型及字符串字段 `uuid`。正式版的成绩同步使用同一正式容器的私有数据库。Cubegin Dev 使用自己的专用容器。GA4 的 `cube_event`、`inspection_voice` 和 `include_dnf_in_worst` 使用事件级自定义维度。

### 2026-11-22 Cubegin Dev 验收

- 实际计时、查看成绩列表和统计、导入 DCTimer 后，DebugView 各收到一条 `wca_inspection_started`、`solve_saved`、`solve_list_viewed`、`statistics_viewed`、`dctimer_import_started` 和 `dctimer_import_completed`。SDK 日志核对了各事件的预期参数。
- 全新模拟器安装模拟 CloudKit 在 100 毫秒返回共享 UID。Firebase 上传的 `first_open` 和 `session_start` 均无 UID，随后上传的 `statistics_viewed` 带有预期 UID。其余五个业务事件已确认入站，原始上传数据中的 UID 尚未逐条核对。
- 模拟 UID 在 3.5 秒返回时，App 等满 1 秒后开启采集，UID 到达后没有重发两条自动事件。一台签名 Dev 真机成功读取并设置 CloudKit 共享 UID。真机全新安装及两台真机核对共享 UID 仍待验收。

### GA4 性能报表

App 直接上报 `operation_performance`。收到事件无需在 GA4 后台创建同名事件。上线前先在隔离的
Dev 属性核对[真机验证](#真机验证故障诊断)中的触发和参数。事件含义见[操作性能](architecture.md#操作性能)。

如果在 GA4「探索」中按参数查看，到「管理 → 数据展示 → 自定义定义」补齐以下定义。
同一属性里按参数名复用已有定义，例如 `operation`、`reason` 和 `app_build`。

| 类型 | 参数 |
| --- | --- |
| 事件范围的自定义维度 | `operation`、`outcome`、`sync_phase` |
| 自定义指标 | `duration_ms`，单位选毫秒 |

需要在 GA4 界面按网络、数据量或打乱项目拆分时，再注册相应参数。注册后通常需要 24–48 小时才能用于报表。
[GA4 自定义定义](https://support.google.com/analytics/answer/14240153) · [自定义指标](https://support.google.com/analytics/answer/14239619)

要从上线首批样本计算 P50、P95 和样本量，在发布前确认生产属性已启用 BigQuery 导出。
直接从导出的 `event_params` 读取参数，按构建版本和 `operation` 分组计算成功操作耗时。
同步成功率筛选 `operation=icloud_sync`，按 `sync_phase` 分组，用成功次数除以成功与失败次数之和。
按需用网络类型和数据量分桶拆解结果。开启成绩同步并同意共享诊断与使用数据时，正式构建会记录同步事件。
[BigQuery 导出配置](https://support.google.com/analytics/answer/9823238) · [导出字段](https://support.google.com/analytics/answer/7029846)
