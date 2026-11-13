# Auxiliary solver reference data

[English](README.md) · [中文](README_ZH.md)

Transition and pruning tables and stage masks generated from legacy `79a1e4c`.
The source functions are `initializeCrossTables`, `initializeEOLineTables`,
`getPetrusTables`, `initializeRouxTables`, plus the stage metadata in
`packages/solver/src/assist/three-by-three/`. Values use signed i32 little endian;
`assist-tables.json` records dimensions and element offsets. No JS runtime is used
by the SDK. Search orchestration and validation are implemented in Rust.

Binary SHA-256: `2d1c6c659081efc9ee89fa8d4893ce95205ce11f7ebcd557770e95fdeeac095b`.
