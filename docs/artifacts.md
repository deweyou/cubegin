# 产物标识与安装

SDK 版本取自 `Cargo.toml` 的 `[workspace.package].version`。Web 和 Android 包版本需与其一致，App 版本独立管理。构建生成本地候选产物，带未提交改动的候选需要保存实际源码快照。

构建和打包脚本共用 `scripts/artifact-metadata.mjs`，清单使用 schemaVersion 1。

- `artifact` 标识产物和平台，`version` 记录 Cargo 工作区版本。
- `sourceCommit` 和 `sourceDirty` 记录打包时 Git 状态，包括未跟踪文件。`sourceObservation: packaging-time` 表明这是打包时观察值。
- `packagedAt` 记录 UTC 打包时间，`license` 为 GPL-3.0-only。
- `files` 保存相对于清单目录的路径及 SHA-256。清单不包含自身，归档旁的校验文件覆盖整个归档。

清单拒绝软链和超出目录的路径。校验和可发现文件损坏，安装前应与可信构建记录比较。

| 命令 | 清单与产物 |
| --- | --- |
| `cargo xtask build-sdk web` | `sdk/web/SDK.json`，记录 JS、类型、WASM、包声明和归属，随 npm 包交付 |
| `cargo xtask verify-packages` | `dist/npm-SDK.json` 及 npm 归档校验文件 |
| `cargo xtask build-sdk native` | `dist/native/SDK.json`，记录宿主库、Swift/Kotlin 绑定和归属 |
| `cargo xtask build-sdk ios` | `dist/CubeginSDK-<version>/SDK.json`，完整 Swift 包及 ZIP 校验文件，另有 `dist/xcframework-SDK.json` |
| `cargo xtask build-sdk android` | `dist/android-SDK.json`，记录 AAR 和 Maven AAR/POM/源码清单，复制时保持相对 dist 的布局 |
| `cargo xtask verify-rust-packages` | `dist/rust/SDK.json`，七个已验证的 crate 归档及校验文件 |
| `cargo xtask build-sdk cli` | `dist/cli/SDK.json`，宿主 CLI 和归属 |

直接运行 Cargo 构建单个目标不会生成这些打包清单。Android 清单随暂存 Maven 仓库交付，Rust 清单位于 crate 归档旁。分别记录宿主验证、消费验证、真机验收和远程发布状态。

仓库内 iOS App 通过根 Swift Package 使用 `dist/CubeginFFI.xcframework`。外部项目可解压完整的 `CubeginSDK-<version>` 目录，例如放到 `Vendor/CubeginSDK`，作为本地 Swift Package 引入 **Cubegin** 产品。完整包包含配套绑定、XCFramework、消费测试、许可证和来源说明，可独立于 Core checkout 构建。`scripts/package-ios.mjs` 负责打包和验证。
