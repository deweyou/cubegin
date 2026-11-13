# Cubegin Core SDK workspace

This repository owns reusable cube capabilities, platform SDKs and Cubegin apps.
The iOS app lives in `apps/ios/`; use `apps/android/` when Android app development starts. The legacy TypeScript implementation is available at
`79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`.

- Work directly with repository tools; DDev is not required.
- Use Cargo for Rust; pnpm 10 / Node >=22.12 for Web; SwiftPM and Gradle for native SDKs.
- Keep domain crates independent of platform globals, UI, bindings, and products.
- Keep foreign-language adapters thin; implement cube semantics once in Rust.
- Test correctness using independent fixtures, invariants, and solution replay.
- Verify packaged SDKs as consumers, not only workspace source imports.
- Read docs/architecture.md and docs/provenance.md before changing boundaries or dependencies.
- Preserve GPL-3.0-only licensing and third-party attribution. Translation does not remove provenance.
- Update both READMEs for public capabilities and both development guides for setup changes.
- Do not publish, push, or commit without explicit delivery intent.

## Knowledge base

This knowledge base describes the current Rust capability workspace. Keep documents
for its crates, bindings, SDKs, diagnostic examples and active data provenance.
Legacy timer/H5/WeChat product documentation, old TypeScript package ownership,
superseded workflow instructions and historical implementation plans belong in Git
history. Do not restore them as current guidance. When extracting legacy source for
an oracle or port, use it as reference material, not as development instructions.
Preserve upstream attribution, license notices and migration evidence used by the
current implementation. Root documentation owns workspace-wide contracts. Each app, crate, binding and SDK
keeps a README for its purpose and an AGENTS.md for local contributor rules.
Use DEVELOPMENT.md for substantial build and validation workflows. For a module
with one validation command, document it in the local AGENTS.md. Keep detailed documentation next to the module that owns it.

| Document | Ownership and when to read |
| --- | --- |
| [README.md](README.md) / [README_ZH.md](README_ZH.md) | Product introduction, public capabilities and technology stack |
| [DEVELOPMENT.md](DEVELOPMENT.md) / [DEVELOPMENT_ZH.md](DEVELOPMENT_ZH.md) | Build prerequisites, CI, artifacts and iOS/Android integration |
| [Artifact identity](docs/artifacts.md) | Common version/source/checksum manifests and copied SDK installation |
| [Architecture](docs/architecture.md) | Rust crate boundaries, platform adapters, state and animation contracts |
| [SDK examples](docs/sdk.md) | Web/Swift/Kotlin calls, JSON options, playback positions and solver coverage |
| [CI acceptance](docs/ci.md) | Unit/E2E/build gates, required summary check, candidate artifacts and failure evidence |
| [Verification](docs/testing.md) | Independent fixtures, legacy oracle, SDK/package consumers and browser E2E |
| [Releasing](docs/releasing.md) | Build/verify sequence, local staging, future registry and remote SwiftPM release steps |
| [Provenance](docs/provenance.md) | Upstream sources, licenses and distribution attribution |
| [Delivery status](docs/status.md) | Observed local evidence, unfinished acceptance and publication status |

## SDK build and integration contract

- Read the DEVELOPMENT.md mobile integration sections, SDK examples and release instructions
  before changing packaging or consumer setup. Verify current values against
  [Package.swift](Package.swift), [Android library configuration](sdk/android/library/build.gradle.kts)
  and `scripts/build-{ios,android,native}.mjs`; these are the executable configuration.
- Run builds from the repository root. `cargo xtask build-sdk native` builds host
  libraries and generates bindings for smoke tests. Mobile artifacts require
  `cargo xtask build-sdk ios` or `cargo xtask build-sdk android`.
- iOS consumers use the **Cubegin** Swift Package product: generated Swift sources
  plus `dist/CubeginFFI.xcframework`. The iOS app references the root package directly.
  Use `node scripts/build-ios.mjs --app-only` for App development. Current minimum is iOS 15; slices cover iOS arm64, simulator arm64/x86_64,
  and macOS arm64. The build also writes `dist/CubeginFFI.xcframework.zip`.
- Android consumers use `io.github.deweyou:cubegin:0.1.0` from `dist/maven/`.
  `dist/android/cubegin.aar` contains Kotlin bindings and arm64-v8a/armeabi-v7a/x86_64
  libraries; current minimum is API 23. Maven metadata supplies JNA 5.17.0. A consumer
  copying only the AAR must explicitly add `net.java.dev.jna:jna:5.17.0@aar`.
- Rebuild/restage SDKs after Rust changes. Generate bindings through the build
  scripts, and keep bindings and binaries from the same build. Apps
  consume packaged SDKs and own background scheduling; they do not duplicate Rust
  semantics. CPU-bound SDK calls are synchronous.
- `playerTimeline`, `playerFrame` and `playerSvg` are available through all bindings.
  Web has a diagnostic player; native products own SVG/GPU rendering, views and
  controls. Binding tests and cross-compilation do not establish device rendering
  acceptance.
- `dist/` is ignored by Git. Local builds are not public releases. Remote SwiftPM
  requires an uploaded immutable XCFramework ZIP plus URL/checksum metadata in
  `sdk/swift/Artifact.json`, matching generated Swift sources and a versioned package.
  Remote Android consumption requires published AAR/POM/sources. Do not describe
  Git URL or registry integration as available until publication and consumer
  readback are verified.
- Changes to versions, supported targets, artifact locations or dependency metadata
  must update both development guides and the affected knowledge documents. Validate packaged
  consumers with `scripts/verify-swift-package.mjs` and
  `scripts/verify-android-package.mjs` after rebuilding mobile artifacts; record
  host tests, binary architecture checks, device acceptance and remote publication
  as separate outcomes.

## CI acceptance

- Keep unit tests, browser E2E, and artifact builds/isolated consumers as mandatory
  checks for Core and shared changes. For iOS-only changes, require the Apple SDK build and both iOS App jobs.
  `CI passed` requires success from all selected jobs and a successful scope check.
- Read [CI acceptance](docs/ci.md) before changing workflows. Keep it and the public
  development guides aligned with the executable `.github/workflows/check.yml`.
- Retain failure evidence and matching candidate binaries/bindings. CI builds local
  candidates only; it does not publish packages. Workflow validation, local command
  results, actual GitHub runs and required branch rules are separate evidence.
