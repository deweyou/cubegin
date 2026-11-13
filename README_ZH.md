# Cubegin

[![English](https://img.shields.io/badge/English-blue)](README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](README_ZH.md)

Cubegin 的核心能力 SDK 仓库，以 Rust 实现，提供 Web/WASM、Swift 和 Kotlin 绑定。
原生 iOS App 位于 [apps/ios](apps/ios/README.md)。未来的 Android App 在
`apps/android/` 开发。许可证：GPL-3.0-only。

仓库名为 `cubegin`；SDK 包名及导入名继续使用 `cubegin`（Rust/Web）、
`Cubegin`（Swift）和 `io.github.deweyou.cubegin`（Kotlin）。

Rust 引擎现已覆盖原仓库的能力目录：

- 18 类标准项目：二至七阶、盲拧／最少步／单手变体、Clock、五魔方、
  金字塔、斜转、Square-1、FTO。
- 94 类训练打乱、案例选择、自然权重、颜色朝向与批量状态去重。
- 二／三／四阶、金字塔、斜转、Square-1、FTO 完整求解，以及 Clock 逆公式；
  20 种辅助求解（Cross、XCross、EOline、Roux、Petrus、分阶段及小项目目标）
  和最少步校验。不包含五至七阶、五魔方的完整求解。
- SVG 展开图、跨平台 3D 拼块几何与刚体变换、任意位置跳转和 SVG 动画帧，
  包含 Clock 指针／按钮、Square-1 形变。
- Web/WASM + Worker、Swift、Kotlin 共同使用 Rust 实现。

这是新 API，不直接兼容旧 TypeScript 包。原生视图组件由产品仓库提供，
可消费 SVG 帧，或使用拼块几何自行绘制。打乱未作 WCA 比赛用途认证。

## 仓库结构

`crates/` 存放 Rust 核心能力，`bindings/` 存放原生和 WASM 绑定，
`sdk/` 存放平台 SDK，`apps/` 存放产品。各模块的 README 介绍职责，开发入口和验证方式见 DEVELOPMENT.md。

[开发指南](DEVELOPMENT_ZH.md)
