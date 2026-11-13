# CI acceptance

Each [workflow](../.github/workflows/) declares its inputs under `paths` for PRs
and pushes to main. Matching workflows run independently. Product and version
workflows also run on merge queue events. All workflows can run manually.

| Workflow | Inputs |
| --- | --- |
| `rust.yml` | Cargo workspace sources and configuration, shared fixtures, CLI and Rust packaging scripts |
| `web.yml` | Rust engine, WASM bindings, Web SDK, workbench, browser tests and Web build inputs |
| `apple.yml` | Rust engine, native bindings, Swift SDK and the iOS app’s sources, resources and tests |
| `android.yml` | Rust engine, native bindings, Android SDK and isolated Gradle consumer |
| `versions.yml` | Cargo manifests, npm package metadata, Android Gradle version and release planning script |
| `docs.yml` | Markdown, documentation assets and the README brand SVGs |
| `ci-rules.yml` | Workflow YAML, checked with actionlint |

Markdown and documentation directories in modules trigger documentation checks,
including the Web SDK README. Product workflows exclude those paths while
retaining inputs such as Xcode assets and shared test fixtures.
Workflow YAML changes trigger the syntax check. To exercise a changed build
command or runner configuration, run the affected workflow manually.

Platform workflows exclude Rust crate tests and diagnostic examples. The Rust
workflow still checks them. Shared platform tests consume `fixtures/states.json`
and `fixtures/events.json`. The iOS build uses the checked-in assets, so design
references, the asset generator and the preview project are outside its scope.
The Android workflow uses Gradle tests and the isolated consumer, while
`sdk/android/smoke/` belongs to the separate local Kotlin smoke test.

| Job | Required tests | Required builds and consumers |
| --- | --- | --- |
| Rust lint, unit tests and solver replay | `cargo xtask check`: fixture/license consistency, formatting, Clippy and workspace unit tests; release 4x4/FTO replay | — |
| Rust packages and CLI | — | Release CLI with metadata; seven crate archives unpacked and compiled through a fresh temporary registry; package version consistency dry run |
| Web SDK build, unit and package tests | SDK/workbench type checks; actual WASM unit tests | WASM + JS/types bundled into npm tarball and installed in an isolated consumer |
| Web browser E2E | Browser tests and screenshot comparisons | Reuses WASM and JS from the Web SDK job |
| Apple SDK build | Generated Swift host tests and committed binding drift check on full runs | iOS/simulator/macOS XCFramework and matching Swift bindings |
| Apple SDK package | SwiftPM and isolated consumer tests | Reuses the Apple SDK build to package the XCFramework ZIP and complete SDK ZIP |
| iOS App Release and simulator tests | App unit and UI tests | Release and simulator jobs run in parallel against the same Apple SDK build |
| Kotlin tests and Android build | Gradle host unit tests: shared 3x3/event fixtures, errors/replay, training, auxiliary, FMC and player calls | Three-ABI AAR, POM and sources; ELF architecture checks; isolated local-Maven consumer |

Before merging, confirm the workflows triggered for the PR head have passed.
The main ruleset currently has no required status checks. Path-filtered workflows
may not start on unrelated changes, so requiring every workflow by name would
block such PRs. GitHub’s path matching also has a 300-file comparison limit.
Use manual runs for large changes if expected workflows are missing.

Rust uses 1.96.0; Node uses 24; pnpm comes from packageManager. The Web job pins
wasm-bindgen CLI 0.2.126 and the lockfile pins Playwright/Chromium. Screenshot checks
stay on macOS. Apple builds require arm64 and select Xcode 26.2; Android uses JDK 17,
SDK 35, NDK 28.2.13676358, cargo-ndk 4.1.2 and the checked-in Gradle wrapper.
The selected Xcode path is listed in the
[macOS 15 arm64 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).
Runner image updates are not immutable; review environment changes and screenshot
differences rather than regenerating baselines in CI.

## Candidate artifacts and failures

Successful jobs retain candidates for 14 days:

- Rust: seven `.crate` archives and the CLI candidate.
- SDK versions: the version dry-run plan.
- Web: npm tarball and isolated-consumer verification metadata.
- Apple: XCFramework ZIP, SHA-256 file, matching generated Swift sources,
  Package.swift, package tests and consumer verification metadata. To use the
  downloaded local package, extract `dist/CubeginFFI.xcframework.zip` into `dist/`.
- Android: AAR, staged Maven repository with POM/sources and consumer verification.

Each candidate comes from its own job/checkout. None is publicly published.
Browser failures retain the HTML report, screenshots and traces; Android failures
retain Gradle XML/results and reports. Unit/build logs remain in the workflow run.

Native tests use the host library. Cross-compilation, archive checks and host tests
are required here; native GPU rendering, physical-device execution and registry
publication are separate acceptance layers. See [verification](testing.md),
[local SDK integration](../DEVELOPMENT.md#build-artifacts-and-consume-them-in-products)
and [releasing](releasing.md).

## Validation status

The workflow was checked locally with actionlint 1.7.7, and the aggregate gate
was exercised against success/failure/cancelled/skipped results. Underlying unit,
E2E and package-consumer commands have local evidence in [status.md](status.md).
`CI=true` browser tests were also exercised on a separate local port.

Hosted runners were first exercised in [PR #46](https://github.com/deweyou/cubegin/pull/46).
The first run exposed setup-android's default request for the retired SDK `tools`
package; the workflow now requests `platform-tools` explicitly and installs the
pinned platform/build-tools/NDK separately. Hosted Rust, Web, Swift and Android jobs
have each completed successfully during that PR's iterations. Consult the latest
PR commit's workflow results for acceptance; individual
successes from different commits are not a substitute. Repository branch protection
is not configured by these files.

## Artifact metadata

Candidate uploads retain common manifests/checksums described in [artifacts.md](artifacts.md),
including the complete versioned Apple SDK ZIP. The Rust check also runs metadata
integrity/path tests. CLI uses the packaging entry point, not a bare cargo build.
The iOS simulator job retains its result bundle for 14 days when available.
The Apple SDK build retains the matching framework and bindings for 14 days.
