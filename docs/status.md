# Rebuild status

Branch: `codex/rust-core-rebuild`. Legacy reference: `79a1e4c`.

Migrated the legacy capability catalog into Rust: 18 standard event IDs and 94
training types, selectable cases/natural weights/orientation, unique batches,
applicable full solvers, 20 auxiliary methods, FMC validation, SVG nets and
platform-neutral 3D geometry/transforms/seek/SVG animation frames for all 12 puzzle
models. Web/WASM/Worker and generated Swift/Kotlin bindings share these APIs.
Products remain outside this repository. The API intentionally differs from old TS.

Full solver coverage matches the legacy boundary: 2x2/3x3/4x4/Pyraminx/Skewb/
Square-1/FTO, plus Clock inverse notation. No full 5x5–7x7 or Megaminx solver is
claimed. Native view widgets/GPU renderers belong in product repositories; this
repository provides SVG frames and platform-neutral piece geometry.

## Local evidence — 2026-11-02

Environment: Apple Silicon macOS, Rust 1.96.0, Node 24.15.0, pnpm 10.33.0,
Xcode 27.2; Kotlin smoke compiler 2.2.20, Android Gradle Kotlin 2.1.20 / JDK 21,
NDK 28.2.13676358.

| Check | Result |
| --- | --- |
| Rust check | Pass: rustfmt, Clippy with warnings denied, workspace tests; post-render-fix Clippy and playback tests passed |
| Heavy full solvers | Pass: release 4x4/FTO solution replay |
| Independent old implementation | Pass: 223 event states, 188 training samples, 200 auxiliary solutions |
| Actual WASM SDK | Pass: 4 tests, all 18 standard IDs (multi-blind separately), all 94 training types, cases/batches/FMC/assist/player |
| Browser E2E | Pass: 9 Chromium tests; 6 baselines, animation/net grids plus workbench catalog, generation, case/orientation, assist, error recovery and mobile playback checks |
| Swift host | Pass: 22 original + 223 event fixtures, errors, generation/solve, training, assist, player |
| Kotlin/JNA host | Pass: 22 original + 223 event fixtures, errors, generation/solve, training, assist, player |
| Apple package | Pass: iOS arm64, simulator arm64/x86_64, macOS arm64 XCFramework; isolated ZIP SwiftPM consumer, 2 tests |
| Android package | Pass: arm64-v8a/armeabi-v7a/x86_64 ELF architectures, AAR/POM/sources staging, Gradle tests and isolated Maven consumer |
| npm package | Pass: tarball installed outside workspace; fixtures and expanded capability calls |
| Rust archives | Pass: 7 crate archives compiled through a fresh temporary registry; verified archives in dist/rust |
| CI configuration | actionlint and aggregate-gate failure cases passed locally; first hosted validation is tracked in [PR #46](https://github.com/deweyou/cubegin-core/pull/46); required branch rules remain unconfigured |
| CLI | Pass: build and FMC adjudication smoke check; --help documents expanded commands |

The evidence above was captured locally before the first remote CI run. Branch
commits and live GitHub check results are tracked in the pull request. Builds stage
local candidates; no tag or registry publication is performed by these scripts. Physical-device runtime, native GPU-renderer acceptance,
statistical randomness audits, performance budgets, transitive distribution-license
inventory and registry publication remain separate release work. See testing.md,
releasing.md and sdk.md for reproducible commands and contracts.

## Local artifact metadata follow-up (2026-11-03)

Shared metadata now covers Web/npm, native, iOS, Android, Rust archives and CLI
packaging. SHA-256/path validation tests, xtask formatting/Clippy, native bundle and
CLI builds/smoke check passed. The copied iOS package passed its 2 SwiftPM consumer
tests and was reinstalled in the Swift product. Workflow YAML parsed locally;
actionlint and hosted runs were not rerun. No claim of a new combined CI pass.
Web and Android full builds were not repeated in this follow-up. Rust archive
verification was attempted but failed under the local crates.io source replacement:
Cargo could not resolve the unpublished cubegin-tnoodle through its temporary
registry. No new seven-crate consumer pass or metadata output is claimed. Existing
historical evidence above is separate from this follow-up.
