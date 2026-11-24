# CI 验收

各 [workflow](../.github/workflows/) 在 `paths` 声明 PR 和推送到 main 的触发路径，匹配后各自运行。产品和版本 workflow 也支持合并队列，所有 workflow 均可手动运行。

| Workflow | 触发输入与检查 |
| --- | --- |
| `rust.yml` | Cargo 工作区、Rust 测试与示例、打包脚本。运行 `cargo xtask check`、4×4/FTO 解法回放及七个 crate 的独立打包验证。 |
| `web.yml` | Rust 引擎、WASM 绑定、Web SDK、工作台、浏览器测试及构建输入。运行 `pnpm lint`，验证真实 WASM 和 npm 独立消费，浏览器 E2E 复用构建结果并比较截图。 |
| `apple.yml` | Rust 引擎、原生绑定、Swift SDK、iOS App 源码、资源和测试。运行 SwiftLint，验证 Swift 宿主调用及生成绑定，复用同一份 XCFramework 构建 iOS Release、并行运行两组 iOS 模拟器检查，并验证独立 SwiftPM 消费。 |
| `android.yml` | Rust 引擎、原生绑定、Android SDK 和 Gradle 消费方。验证 Kotlin 单测、三种 ABI 的 AAR 及独立 Maven 消费。 |
| `versions.yml` | Cargo 清单、npm 包元数据、Android Gradle 版本和发布计划脚本。验证版本一致性并保留 dry-run 计划。 |
| `docs.yml` | Markdown、模块文档目录和品牌 SVG。验证仓库内文档链接和资源。 |
| `ci-rules.yml` | Workflow YAML。用 actionlint 验证语法。 |

纯文档改动走文档检查，修改 workflow 后可手动运行受影响的产品检查来验证构建命令或 runner 配置。Rust crate 的测试和诊断示例由 Rust workflow 验证。平台共享样例为 `fixtures/states.json` 和 `fixtures/events.json`。iOS 使用已提交的资源，排除设计参考、素材生成脚本和预览工程。随 App 打包的隐私政策和 iOS 更新记录 Markdown，以及构建使用的诊断配置脚本会触发 Apple 检查。Android 的 `sdk/android/smoke/` 由独立的本地 Kotlin 冒烟测试使用。

合入前确认 PR 最新提交所需检查全部通过。路径筛选可能使无关 workflow 不产生检查结果。GitHub 的路径比较最多覆盖 300 个文件，大型改动若缺少预期检查，手动运行对应 workflow。跟进步骤见 [PR 跟进](pr-follow-up.md)。

## iOS 模拟器分组

`iOS Simulator test build` 使用 Apple SDK 构建产物，对 arm64 通用模拟器目标执行一次
`build-for-testing`，把 `.xctestrun` 与 App、测试包一起上传为
`ios-simulator-test-products`。`iOS App (simulator-a)` 和 `iOS App (simulator-b)`
下载并解包同一份产物，各自在独立的 macOS runner 和 iPhone 17 Pro 模拟器上使用
`test-without-building` 执行本组，组内保留 `-parallel-testing-enabled NO`。
iOS Release 和 SDK 打包直接使用 Apple SDK 构建产物，可与测试构建并行。

[测试分组脚本](../scripts/test-ios-simulator.sh)用指定用例运行 A 组。B 组执行 App 单测
和其余 UI 用例，并排除 A 组清单中的用例。新增测试会自动进入 B 组。根据 GitHub
Actions 的实测用例耗时，把需要分流的 `SolveFlowTests` 用例移入 A 组清单。iPad 和
Duo 用例保留原有设备检查，在 iPhone CI 中按原条件跳过。

2026-11-24 按最近五次成功的 Apple workflow 调整分组。取每条用例在可用样本中的中位耗时，
再加上各组测试步骤中其余时间的中位数，计入 B 组的单测开销。计时手势和清空成绩两条
用例的中位耗时分别为 80 秒和 76 秒，已从 B 组移入 A 组。按此模型估算，
A、B 两组的测试步骤各约 13 分钟，不含构建、runner 排队及模拟器启动。
[最近一次采样](https://github.com/deweyou/cubegin/actions/runs/45319945829)

横屏项目选择器用例五次的中位耗时为 29 秒。在[一次 577 秒的运行](https://github.com/deweyou/cubegin/actions/runs/45056566569/job/137315458118)中，
XCTest 在点击、拖动和恢复竖屏时共九次等待动画完成通知超时，每次约 60 秒。
排查类似异常时，先对照单条用例内的时间戳和 XCTest 的空闲等待日志。

失败时在 GitHub Actions 单独重跑对应 job。每组上传 `app-test-results-simulator-a`
或 `app-test-results-simulator-b`，包含各自的 `.xcresult`。比较吞吐量时，分别记录
共享测试构建的等候、编译和上传时间，以及各组的等候、下载解包、模拟器准备、
测试和 runner 用时。合计等待时间以 SDK 完成至较晚结束的模拟器 job 通过为准。

`main` 当前规则集未配置必需的检查名称。若之后需要把模拟器测试设为必需检查，
在分支保护中同时要求 `iOS App (simulator-a)` 和 `iOS App (simulator-b)`。

## 运行环境与产物

Rust 用 1.96.0，Node 用 24，pnpm 由 packageManager 固定。Web 使用 wasm-bindgen CLI 0.2.126，Playwright/Chromium 由锁文件固定，截图在 macOS 上比较。Apple 使用 arm64 与 Xcode 26.2。Android 使用 JDK 17、SDK 35、NDK 28.2.13676358、cargo-ndk 4.1.2 和仓库里的 Gradle wrapper。runner 更新后应核对环境和截图差异。参见 [macOS runner 清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)。

候选产物保留 14 天。Rust 保存 crate 归档，版本检查保存 dry-run 计划，Web 保存 npm 包与消费结果，Apple 保存 XCFramework ZIP、校验和、配套绑定、Package.swift 和消费验证，Android 保存 AAR、Maven POM、源码包和消费结果。Apple 下载包解压到 `dist/` 后可在本地接入。所有产物附有[清单](artifacts.md)。

浏览器失败保留 HTML 报告、截图和 trace，Android 保留 Gradle XML 和报告。iOS 模拟器结果和配套 Apple SDK 产物按 workflow 保存。真机运行、GPU 渲染和远程发布需分别验收。参见[验证](testing.md)和[发布流程](releasing.md)。
