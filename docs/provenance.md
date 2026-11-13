# 来源与依赖归属

仓库采用 GPL-3.0-only。重写和移植保留原始来源，分发时随产物保留 LICENSE 和 NOTICE。

- 旧版 TypeScript 实现位于提交 [`79a1e4c`](https://github.com/deweyou/cubegin/tree/79a1e4c4c5239fbcda8cccf313a81b8d7d430a97)，完整 SHA 为 `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`。状态样例在移除旧实现前提取。历史来源包括 TNoodle-lib v0.19.2（GPL-3.0）和 cstimer。保留原有归属，未复制 AGPL 的 TNoodle App 代码。
- `crates/tnoodle` 基于 `tnoodle-rs 0.1.1`，来源为 enekocm7/cube-tui 提交 `373e868f802e0f095bea9353282d9fdca5d1883d`。上游采用 GPL-3.0-or-later，组合分发选用 GPLv3。包归档遗漏的 LICENSE 从该上游提交取得。源码头部和 UPSTREAM.md 保留原求解器归属。本地改动包括 crate 名称、默认串行、WASM 兼容时间、状态构造与访问、Clock 扩展旋转和立方体置换访问。归档不含上游样例，因此未验证这些样例。
- 回放静态几何和转动映射来自旧版 `packages/player`。Pyraminx、Skewb 和 Megaminx 参考 cubing.js，双许可为 MPL-2.0 或 GPL-3.0-or-later，此处选 GPL。产物无 cubing.js 或 Three.js 运行时依赖。
- 训练案例、辅助坐标表、剪枝表和子群规则由旧版 GPL 实现移植。细节见各 crate 的数据 README。
- 独立的 min2phase 0.2.4 依赖已替换，保留历史 MIT 声明。
- UniFFI 0.32.2 为 MPL-2.0。运行时进入原生产物，公开发布需满足声明和源码可用性要求。
- JNA 5.17.0 为 LGPL-2.1-or-later 或 Apache-2.0，Android 分发选 Apache-2.0。
- usvg 0.48.1 为 MIT 或 Apache-2.0，用于测量 SVG 图形及描边边界。
- wasm-bindgen、rand、rand_chacha、serde、serde_json、thiserror 均为 MIT 或 Apache-2.0。
- Gradle wrapper 8.11.1 为 Apache-2.0，取自 Gradle 官方标签。
- Vite 为 MIT，TypeScript 和 Playwright 为 Apache-2.0，均用于开发。

Cargo.lock 和 pnpm-lock.yaml 固定解析结果。公开发布前，逐产物清点传递依赖和许可文本，并核对源码可用性与移动端分发条件。现有 NOTICE 是归属记录，完整传递依赖审计仍待完成。
