# Cubegin iOS App

本模块负责 SwiftUI 界面、手势、计时、成绩存储和后台调度。魔方语义由 Rust SDK 提供。

- 保持系统外观和可访问性。CPU 密集的同步 SDK 调用在后台执行。
- 计时使用单调时钟。持久化错误应可见，并保留成绩的项目、打乱和日期。
- 行为变更同步更新单测，修复缺陷补回归用例，关键跨页面流程更新 UI 测试。
- 交付前跑受影响的 App 检查。SDK 接入变更同时验证打包消费者。

[开发入口](DEVELOPMENT.md) · [架构](docs/architecture.md) ·
[SDK 接入](docs/sdk.md) · [测试与验收](docs/testing.md) · [状态](docs/status.md)
