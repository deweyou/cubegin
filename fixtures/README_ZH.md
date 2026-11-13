# 共享迁移样例

[English](README.md) · [中文](README_ZH.md)

这些样例用于验证 Rust 实现和各平台 SDK。旧版 Cubegin 提交 `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97` 提供行为参照。

| 文件 | 用途 |
| --- | --- |
| `states.json` | Rust 与 SDK 共用的 22 个三阶外层转动样例 |
| `events.json` | 223 个项目状态样例，覆盖宽层转动、中层转动、整转和 Clock 扩展方向 |
| `legacy-catalog.json` | 18 类标准项目和 94 类训练的参考目录 |
| `fto-conventions.json` | 旧版与后端之间的 FTO 面片和颜色约定 |
| `fto-coordinate-conventions.json` | 迁移时使用的 FTO 拼块坐标映射 |

`states.json` 将旧版面序 RUFLDB 转为 URFDLB，索引顺序为 1、0、2、4、3、5。每个面从外侧观察并按行排列。原三阶 API 仅接受外层转动，项目 API 支持各魔方的记号、宽层转动、中层转动和整转。参见 [SDK 契约](../docs/sdk.md)。

Rust 还验证状态合法性、群恒等关系和解法回放。状态样例的打包副本位于 `crates/puzzle/tests/fixtures/`，两处应同步更新。训练和辅助求解样例随各自 crate 的测试保存。参见[验证指南](../docs/testing.md)。
