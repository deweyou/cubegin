# 辅助求解参考数据

[English](README.md) · [中文](README_ZH.md)

转移表、剪枝表和阶段掩码生成自旧版 `79a1e4c`。来源包括 `initializeCrossTables`、`initializeEOLineTables`、`getPetrusTables`、`initializeRouxTables`，以及 `packages/solver/src/assist/three-by-three/` 的阶段元数据。数值为小端有符号 i32，`assist-tables.json` 记录维度和元素偏移。搜索与验证由 Rust 实现。

二进制 SHA-256：`2d1c6c659081efc9ee89fa8d4893ce95205ce11f7ebcd557770e95fdeeac095b`。
