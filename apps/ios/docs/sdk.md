# Core SDK 接入

正式工程通过相对路径 `../..` 引用仓库根目录的 Swift Package，链接 **Cubegin**。
首次运行或修改 Core 后，在仓库根目录执行：

```sh
node scripts/build-ios.mjs --app-only
```

生成的 Swift 绑定位于 `sdk/swift/Generated/`，XCFramework 位于
`dist/CubeginFFI.xcframework`。App 和 SDK 独立管理版本，SDK 版本以根目录
`Cargo.toml` 为准。完整打包和独立消费验证使用 `cargo xtask build-sdk ios`。

## 调用契约

Engine.swift 在 Task.detached 上调用同步 Rust 接口，结果再回到产品状态：

- generateEvent：项目 ID 与随机 UInt32 seed → 打乱公式。
- generateTraining：训练 ID、seed 与默认 optionsJson `{}` → JSON；App 解码 algorithm。
- evaluateEvent：项目 ID 与公式 → 状态与 SVG 展开图。
- solveAssist：333、方法 JSON、公式、深度选项 → 辅助解法 JSON。

UI 不创建模拟公式。独立 CubeginPreview 工程缺少 SDK 时会明确报错。
SDK 的 seed 是可重现接口，不构成比赛随机性认证；后台任务取消也不保证终止引擎。

保留完整 LICENSE、NOTICE、docs/provenance.md。公开分发前还需处理来源可用性与
完整依赖归属；分发说明见根目录的 [Provenance](../../../docs/provenance.md)。
