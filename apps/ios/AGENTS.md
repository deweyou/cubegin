# Cubegin Swift App workspace

本目录拥有原生 iPhone/iPad 魔方计时器产品。核心打乱、状态、SVG 和求解语义由
本仓库的 Rust SDK 实现；这里拥有 SwiftUI、手势、计时、成绩存储及后台调度。

- 开发前读 DEVELOPMENT.md 和与任务相关的 docs/ 文档。以工程和源码为准，及时修正文档。
- 使用 Swift 6 / SwiftUI；部署下限 iOS/iPadOS 26。采用系统 Liquid Glass，保持系统外观和可访问性。
- 正式工程是 Cubegin.xcodeproj，运行 scheme 为 CubeginApp。不要误选 SDK 的 Cubegin scheme。
- App 链接仓库根目录 Swift Package 的 Cubegin 产品。在根目录运行 `node scripts/build-ios.mjs --app-only` 生成匹配的绑定和 XCFramework。
- 在 Rust 实现魔方语义，通过构建脚本生成绑定和二进制。完整 SDK 打包及消费验证用 `cargo xtask build-sdk ios`。
- CPU 密集 SDK 调用必须由 App 在后台执行；调用是同步的，取消 Swift Task 不保证停止 Rust 计算。
- 计时使用单调时钟，持久化错误必须可见。保留每次成绩对应的项目、打乱和日期。
- 修改 SDK 或接入方式后验证打包消费者及正式 App；编译通过不等同于真机或视觉验收。
- 新功能或行为变更必须在同一变更中新增或更新 `CubeginTests` 单测，覆盖正常流程及相关边界和错误路径。修复缺陷须添加能复现原问题的回归用例。
- 单测使用固定输入、隔离存储和可控时间。涉及纯视觉或设备交互的改动，在 PR 写明验证方式和结果，并覆盖其中可单测的逻辑。
- 新增或修改关键跨页面流程时，在 `CubeginUITests` 新增或更新端到端用例。使用稳定的可访问性标识、条件等待和隔离的成绩文件。
- 交付前运行 `CubeginApp` 测试和受影响的构建检查，命令见 docs/testing.md。PR 合入前须通过Apple workflow 中的 App 构建和测试，不得跳过或放宽失败门槛。
- 不提交构建缓存、个人 Xcode 状态或签名凭据；XCFramework 由根目录的构建流程生成到 `dist/`。
- 保留 GPL-3.0-only 和上游归属。不把本地候选产物描述成远程发布。
- 未经明确要求，不 commit、push、发布或上传。

## 知识库

| 文档 | 何时阅读 |
| --- | --- |
| DEVELOPMENT.md | 运行入口、前提、SDK 接入与知识库索引 |
| docs/architecture.md | 产品/core 边界、状态、计时与存储 |
| docs/sdk.md | Core SDK 接入、版本、接口和后台调用 |
| docs/testing.md | 构建、消费者、模拟器、真机与视觉验证 |
| docs/status.md | 当前验证证据和未完成功能 |

用户提到 agent.md 时，本仓库以标准 AGENTS.md 为唯一代理规则入口，避免多份规则漂移。
