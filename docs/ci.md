# CI acceptance

The contract is: unit tests pass, browser E2E passes, and distributable artifacts
build and work in isolated consumers. The executable workflow is
[check.yml](../.github/workflows/check.yml). Every main-branch push, pull request, merge-group
check and manual run executes all four jobs. Feature-branch pushes rely on the PR
run, avoiding duplicate full platform builds. There are no path-based skips or
`continue-on-error` exceptions for these gates.

| Job | Required tests | Required builds and consumers |
| --- | --- | --- |
| Rust tests and builds | `cargo xtask check`: fixture/license consistency, formatting, Clippy and workspace unit tests; release 4x4/FTO replay | Release CLI; seven crate archives unpacked and compiled through a fresh temporary registry; package version consistency dry run |
| Web unit tests, E2E and build | SDK/workbench type checks; actual WASM unit tests; all browser E2E and screenshot comparisons | WASM + JS/types bundled into npm tarball and installed in an isolated consumer |
| Swift tests and iOS build | Generated Swift host tests with shared puzzle fixtures and expanded capabilities; SwiftPM tests; committed binding drift check | iOS/simulator/macOS XCFramework; ZIP extracted and consumed by an isolated SwiftPM project |
| Kotlin tests and Android build | Gradle host unit tests: shared 3x3/event fixtures, errors/replay, training, auxiliary, FMC and player calls | Three-ABI AAR, POM and sources; ELF architecture checks; isolated local-Maven consumer |

`CI passed` always evaluates all four job results. Only four `success` results
pass; failure, cancellation or a skipped job fails the summary. Set **CI passed**
as a required check in the GitHub branch protection/ruleset after the workflow has
run. Adding the YAML does not itself configure repository protection.

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

- Rust: seven `.crate` archives and the version dry-run plan.
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
[local SDK integration](../README.md#build-artifacts-and-consume-them-in-products)
and [releasing](releasing.md).

## Validation status

The workflow has been checked locally with actionlint 1.7.7. Its underlying unit,
E2E and package-build/consumer commands have local evidence in [status.md](status.md).
`CI=true` browser tests were also exercised on a separate local port. The exact
GitHub Ubuntu/macOS images and selected Xcode version have not yet run remotely;
repository branch protection is not configured by this change.
