# 回放几何数据

[![English](https://img.shields.io/badge/English-blue)](README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](README_ZH.md)

`models.json` 保存固定几何和基本转动置换，提取自 Cubegin 提交 `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97` 的 `packages/player/src/puzzles`，属于声明式数据。

立方体几何由格点坐标生成。Pyraminx、Skewb、Megaminx 和 FTO 沿用旧版静态多面体适配器。前三种参考 cubing.js PuzzleGeometry（MPL-2.0 或 GPL-3.0-or-later，此处选用 GPL）。Square-1 使用闭合的楔形拼块，Clock 包含实际的指针、按钮和外壳。

Rust 负责转动跟踪、累计四元数姿态、Square-1 楔块交换、Clock 方向和插值。JSON 输出采用 `schemaVersion: 1`。原生应用可用自身的 GPU 渲染拼块，也可直接使用确定性的 SVG 帧。原生 SDK 不运行 JavaScript 适配器。
