# 发布流程

Core Rust crate 和 Web、Swift、Android SDK 共用工作区版本。先按[开发指南](../DEVELOPMENT.md#构建产物与产品接入)配置环境。移动端用对应平台构建，绑定和二进制来自同一次构建。

## 构建与验证

1. 运行 `cargo xtask check`，构建 Web 并运行 SDK 和浏览器测试。
2. 在 macOS 上运行 `cargo xtask build-sdk native` 和 `node scripts/test-swift.mjs`。
3. 运行 `cargo xtask build-sdk ios`，构建 XCFramework 并测试解压 ZIP 后的独立 SwiftPM 消费方。App 通过根 Swift Package 使用该产物，按 [iOS 测试文档](../apps/ios/docs/testing.md)验证。
4. 配置 JAVA_HOME（JDK 17 或 21）、ANDROID_HOME、ANDROID_NDK_HOME（NDK 28.2.13676358）、cargo-ndk 4.1.2 和 Rust 目标 `aarch64-linux-android`、`armv7-linux-androideabi`、`x86_64-linux-android`。运行 `cargo xtask build-sdk android`，暂存 Maven 产物、验证三种 ABI，并运行 `examples/android` 独立消费测试。真机验证另行完成。
5. 运行 `cargo xtask verify-packages`，在独立项目中安装并验证 npm 归档。
6. 运行 `cargo xtask verify-rust-packages`，用全新临时 registry 验证七个 crate 及其未发布的路径依赖，归档写入 `dist/rust/`。
7. 运行 `cargo xtask release --version 0.1.0 --dry-run`，核对版本并生成发布计划。

## 公开发布准备

- 发布 PR 对齐版本和变更日志，核对 API 兼容性、许可证清单和独立消费结果。Swift 包标签提交生成的 Swift 源码，Rust/C 头文件随 XCFramework 交付。
- 从批准的提交构建一次，保留 SHA、校验和和验证证据。上传 XCFramework 到不可变的发布资产 URL，把 URL 和 checksum 写入 `sdk/swift/Artifact.json`，打标签前复验远程 SwiftPM 消费。缺少该文件时使用本地 `dist/`。
- Rust 发布顺序为 `cubegin-tnoodle` → puzzle → solver、diagram、playback → scramble → `cubegin`。逐个验证归档。绑定 crate 为 `publish=false`。
- npm 使用可信发布和 OIDC。Android 在命名空间就绪后经 Maven Central Portal 发布已签名 AAR、POM 和源码包。分别记录 registry 状态，重试缺失产物时保留已有版本，完成远程消费验证后再确认发布完成。

当前脚本只生成候选产物。签名、凭据、registry 发布、远程 SwiftPM 元数据生成和完整传递依赖归属仍待接入。打包和校验规则见[产物标识](artifacts.md)。CLI 通过 `cargo xtask build-sdk cli` 打包。
