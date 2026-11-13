# Cubegin

[![English](https://img.shields.io/badge/English-blue)](README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](README_ZH.md)

Core capability SDKs for Cubegin, written in Rust with Web/WASM, Swift and Kotlin bindings.
The native iOS app lives in [apps/ios](apps/ios/README.md). Future Android app
development belongs in `apps/android/`. License: GPL-3.0-only.

The repository is `cubegin`; SDK package and import names remain `cubegin`
(Rust/Web), `Cubegin` (Swift), and `io.github.deweyou.cubegin` (Kotlin).

The Rust engine now covers the legacy capability catalog:

- 18 standard event IDs: 2x2–7x7, blind/FMC/OH variants, Clock, Megaminx,
  Pyraminx, Skewb, Square-1 and FTO.
- 94 training types, case selection, natural weights, color orientation and unique batches.
- Full solvers for 2x2/3x3/4x4/Pyraminx/Skewb/Square-1/FTO; Clock inverse,
  20 auxiliary methods (Cross, XCross, EOline, Roux, Petrus, staged methods and
  small-puzzle goals), plus FMC validation. No full 5x5–7x7/Megaminx solver.
- SVG nets, platform-neutral 3D piece geometry, rigid transforms, arbitrary seek
  and SVG animation frames, including Clock hands/pins and Square-1 shape changes.
- Web/WASM + Worker and generated Swift/Kotlin bindings using the same Rust logic.

This is a new API rather than a drop-in TypeScript package replacement. Native view
widgets belong in product repositories; consume SVG frames or render the provided
piece geometry. Scrambles are not certified for WCA competition use.

## Repository layout

`crates/` owns Rust capabilities, `bindings/` owns native and WASM adapters,
`sdk/` owns platform packages, and `apps/` owns products. Each module has its own
README, development guide and contributor instructions.

[Development guide](DEVELOPMENT.md)
