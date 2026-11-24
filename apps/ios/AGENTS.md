# Cubegin iOS App

本模块负责 SwiftUI 界面、手势、计时、成绩存储和后台调度。魔方语义由 Rust SDK 提供。

- 保持系统外观和可访问性。CPU 密集的同步 SDK 调用在后台执行。
- 计时使用单调时钟。持久化错误应可见，并保留成绩的项目、打乱和日期。
- 行为变更同步更新单测，修复缺陷补回归用例，关键跨页面流程更新 UI 测试。
- 交付前跑受影响的 App 检查。SDK 接入变更同时验证打包消费者。
- 每次完成 iOS 开发后，编译、安装并打开最新 App，停在可直接操作验证的页面。默认使用 iPhone 模拟器。用户指定 iPad、Duo 或实体机时，在指定设备完成同样的流程。
- 本地真机调试默认安装独立的 **Cubegin Dev**，使用 `io.github.deweyou.cubegin.dev` 与正式版隔离成绩和设置。安装前核对产物的显示名称和 Bundle ID。构建和启动命令见[本地真机安装](docs/testing.md#本地真机安装)。
- 新增或修改界面时，先查找仓库里最接近的交互和样式，优先复用现有组件。按[界面一致性与布局必验清单](docs/testing.md#界面一致性与布局必验清单)对照新旧页面，记录验收和未覆盖的场景。

正式发包按 [iOS 发包手册](docs/releasing.md) 执行。

[开发入口](DEVELOPMENT.md) · [架构](docs/architecture.md) ·
[SDK 接入](docs/sdk.md) · [测试与验收](docs/testing.md) · [状态](docs/status.md)
