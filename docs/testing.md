# Verification

| Layer | Repeatable evidence |
| --- | --- |
| State | 22 original 3x3 fixtures, 223 multi-puzzle legacy fixtures including Clock board rotations; legality/inverse properties |
| Standard events | Actual WASM generation for 17 single-cube IDs + explicit multi-blind batches; replay of every applicable full solver |
| Training | 188 independently certified state fixtures: 94 types × seeds 42/7; selected last cases, natural weights, orientation and invalid input |
| Auxiliary | 40 result fixtures / 200 solutions across all 20 methods, short and longer scrambles, certified with legacy goal validators |
| Playback | Piece position/quaternion inverse round trips for all 12 puzzle models, arbitrary seek, tuple legality and invalid positions |
| Web | Real WASM bindings, all training types, cases, batches, FMC, assist and player; Worker browser consumers |
| Swift/Kotlin | Generated bindings, shared state fixtures, errors, generation/solve, training, assist and SVG frames on host native library |
| Package | Seven Rust crate archives, isolated npm install, extracted XCFramework SwiftPM consumer, staged Maven AAR consumer and three ELF architecture checks |
| E2E | Nine Chromium tests; six screenshot baselines: original 3x3 nets plus all-event net/start/middle/end grids; workbench catalogs, training case/orientation, auxiliary results, error recovery, narrow layout and playback |

CI requires unit tests, browser E2E and all platform artifact builds/consumers;
see [CI acceptance](ci.md) for the jobs and aggregate gate.

Run `cargo xtask check`, then build SDKs and run their tests using README commands.
`cargo test --release -p cubegin-solver -- --ignored` exercises the cold 4x4/FTO
solver replay tests separately. `cargo xtask verify-rust-packages` checks archives
through a fresh temporary registry, avoiding same-version Cargo source cache reuse.

`node scripts/verify-legacy.mjs` is an independent migration oracle. It extracts the
retained legacy commit into a temporary directory, runs old state/goal validators
against the checked-in fixtures, reports counts and removes temporary files. It
requires the legacy commit and installed Web build dependencies, but ships no old
JavaScript runtime in SDKs. Rust tests regenerate results and compare those certified
fixtures; the Web tests additionally exercise actual bindings and replay.

For Kotlin smoke tests, provide the JNA 5.17.0 JVM jar at
`target/kotlin-test/jna.jar`, set JAVA_HOME and optionally KOTLINC, then run
`node scripts/test-kotlin.mjs` after native generation.

Run `pnpm test:e2e --update-snapshots` only for an intentional visual change and
inspect the resulting images. CI compares committed baselines. Baselines currently
target macOS Chromium; other OS rasterizers require separately reviewed baselines.

These checks validate sampled behavior and regression contracts. They do not prove
all training states, randomness distribution or WCA conformance. Physical-device
runtime/native GPU rendering acceptance, performance budgets, fuzzing and remote CI
remain separate from local host/package tests. No native UI widget is included.
