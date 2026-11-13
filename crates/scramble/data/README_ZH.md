# 训练数据表

[English](README.md) · [中文](README_ZH.md)

`legacy-training.json` 和 `catalog.json` 提取自 Cubegin 提交 `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97` 的 `packages/scramble-core/src/{catalog,generators/training-*}.ts`，包含案例 ID、权重、约束、坐标和子群转动集合。原函数已移植到 Rust。

`../tests/fixtures/training.json` 中的 188 条样例经过旧版 11 组 `does*TrainingStateMatch` 验证器独立验证。使用种子 42 和 7，各覆盖 94 类训练。结果仅证明这些样例。测试也会选择每组可选案例中的最后一项，并验证朝向。
