# 交付状态

Rust 引擎已覆盖 18 类标准项目、94 类训练、20 种辅助求解、FMC 校验、SVG 展开图和 12 种魔方模型的 3D 回放。Web/WASM Worker、Swift 和 Kotlin 共用这些接口。求解边界见 [SDK 示例](sdk.md)。

[PR #50](https://github.com/deweyou/cubegin/pull/50) 将 iOS App 并入仓库，Swift 原始提交历史随 merge commit 保留。iOS App 通过根 Swift Package 使用同一次构建的 XCFramework。App 功能和设备验收记录见 [iOS 状态](../apps/ios/docs/status.md)。

## 验证证据

- [PR #50 的 GitHub Actions](https://github.com/deweyou/cubegin/actions/runs/43413040921) 验证了 Rust、Web、Apple SDK、iOS App 和 Android SDK。iOS 模拟器任务在可用 runner 上重试通过。该结果对应当时的 PR 提交。
- 旧版独立样例验证覆盖 223 个项目状态、188 个训练样例和 200 条辅助解法。命令和范围见[验证](testing.md)。
- 构建可暂存 npm、Swift ZIP、Android AAR/Maven、Rust crate 和 CLI 候选包。标识与消费方式见[产物文档](artifacts.md)。

## 待验收

正式 registry 发布、签名、完整传递依赖许可清单、随机性审计及性能预算需单独验收。平台测试结果以对应提交的 CI 为准，App 真机与视觉验证以模块状态记录为准。[发布流程](releasing.md)
