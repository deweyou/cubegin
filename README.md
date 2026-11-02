# Cubegin Core

Core capability SDKs for Cubegin, written in Rust with Web/WASM, Swift and Kotlin bindings.
Product applications live in separate repositories. License: GPL-3.0-only.

The repository is `cubegin-core`; SDK package and import names remain `cubegin`
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

## Development

Rust 1.96.0, Node >=22.12 and pnpm 10 are required. Cargo orchestrates Rust builds;
Vite serves the diagnostic Web workbench.

```sh
cargo xtask check
pnpm install --frozen-lockfile
cargo install wasm-bindgen-cli --version 0.2.126 --locked
cargo xtask build-sdk web
pnpm check
pnpm test
pnpm exec playwright install chromium
pnpm test:e2e
pnpm dev
```

The Web workbench runs on http://127.0.0.1:4488. Its main page exposes all standard
events, training types/case selection, auxiliary solver methods, and shared SVG/animation
previews with playback and seeking.

```sh
cargo run -p cubegin-cli -- evaluate "R U R' U'"
cargo run -p cubegin-cli -- event-scramble fto 42
cargo run -p cubegin-cli -- training 333.pll 42
cargo run -p cubegin-cli -- assist 333 cross "R U F"
node scripts/verify-legacy.mjs # optional: independent old-implementation oracle
cargo xtask build-sdk native
node scripts/test-swift.mjs   # macOS: actual generated Swift + native library
cargo xtask verify-packages  # installs the npm tarball in an isolated consumer
cargo xtask release --version 0.1.0 --dry-run
```

## CI checks

Every PR and main-branch push runs Rust, Web, Swift and Android jobs. Unit tests, browser E2E and
artifact builds with isolated consumer tests must all pass for **CI passed**.
Candidates and failure reports are retained in Actions; public publishing is disabled.
See [CI acceptance](docs/ci.md) for the matrix, artifacts and branch-rule setup.

## Build artifacts and consume them in products

Run build commands from this repository's root. Rust is required on the SDK build
machine; product applications consume the resulting binaries and language bindings.
`build-sdk native` generates host bindings/libraries for smoke tests; use the iOS or
Android commands below for distributable mobile artifacts.

| Platform | Build and package | Outputs |
| --- | --- | --- |
| iOS | `cargo xtask build-sdk ios` | `dist/CubeginFFI.xcframework`, its `.zip`, and `sdk/swift/Generated/Cubegin.swift` |
| Android | `cargo xtask build-sdk android` | `dist/android/cubegin.aar` and the Maven repository at `dist/maven/` (AAR, POM, sources) |
| Web | `cargo xtask verify-packages` | `dist/cubegin-0.1.0.tgz`, containing JS, types and WASM |
| Rust | `cargo xtask verify-rust-packages` | Seven verified crate archives in `dist/rust/` |

### iOS: local Swift Package

Requires an Apple Silicon Mac, Xcode, Node and the pinned Rust toolchain:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
cargo xtask build-sdk ios
```

The build includes iOS arm64, simulator arm64/x86_64 and macOS arm64 slices, then
runs SwiftPM consumer tests. Intel macOS is not included. Minimum iOS version: 15.

In the separate product's Xcode project:

1. Choose **Add Package Dependencies → Add Local** and select this repository root.
2. Add the **Cubegin** product to the App target. The root [Package.swift](Package.swift)
   includes both the generated Swift wrapper and the local XCFramework.
3. Import the SDK and call it from an application-owned background task:

```swift
import Cubegin

let scramble = try generateEvent(event: "333", seed: 42)
let snapshot = try evaluateEvent(event: "333", algorithm: scramble.algorithm)
print(scramble.algorithm)
```

After changing Rust, rebuild the SDK before rebuilding the App. Keep generated
bindings and their binary from the same build. SVG results are strings; native view
widgets/renderers remain the product's responsibility.

### Android: local Maven repository

Set `JAVA_HOME` to JDK 17 or 21 and `ANDROID_HOME` to the Android SDK directory.
Install SDK Platform 35, Build Tools 35.0.0 and NDK 28.2.13676358 with the SDK Manager.
The following environment paths are a macOS / Android Studio example:

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
cargo xtask build-sdk android
```

The AAR includes Kotlin bindings and `arm64-v8a`, `armeabi-v7a`, `x86_64` native
libraries. Minimum Android API: 23. The build also verifies a separate Maven consumer.

Assuming the product repository and `cubegin-core` are sibling directories, add the
repository to the product's existing `settings.gradle.kts` repositories:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("../cubegin-core/dist/maven") }
    }
}
```

In the App module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.deweyou:cubegin:0.1.0")
}
```

Then call the SDK from an application-owned background task:

```kotlin
import io.github.deweyou.cubegin.*

val scramble = generateEvent("333", 42u)
val snapshot = evaluateEvent("333", scramble.algorithm)
println(scramble.algorithm)
```

Maven metadata brings in JNA 5.17.0 automatically. If distributing only the AAR,
the consumer must also declare `net.java.dev.jna:jna:5.17.0@aar` explicitly.
Rebuild/restage the SDK after Rust changes. See the [Android consumer example](examples/android/build.gradle.kts).

### Local artifacts versus public releases

`dist/` is ignored by Git. Current integration uses a local Swift Package and local
Maven repository; no registry package or remote Swift binary has been published.
A Git URL dependency alone does not supply the local XCFramework. For remote SwiftPM,
upload the XCFramework ZIP and configure `sdk/swift/Artifact.json` with an immutable
URL/checksum, then version the package and matching bindings. Android needs the
versioned AAR/POM/sources published to a Maven repository. The product can then pin
those release versions. See [release instructions](docs/releasing.md) for the remaining steps.

CPU-bound SDK operations are synchronous. Native products own background scheduling;
Web apps can use `createWorkerClient` from `cubegin/worker`. Animation computation is
available on all SDKs through `playerTimeline`, `playerFrame` and `playerSvg`; the Web
workbench has a player, while native UI components and device rendering acceptance
remain separate work.

See [API examples](docs/sdk.md), [architecture](docs/architecture.md), [verification](docs/testing.md),
[provenance](docs/provenance.md) and [delivery status](docs/status.md).
The old implementation remains at Git commit `79a1e4c`.

### Versioned artifact metadata

All SDK/package build pipelines share version, source, packaging-time and SHA-256
metadata. See [artifact identity and installation](docs/artifacts.md) for manifest
locations for Web/npm, host-native, iOS, Android, Rust crates and CLI. The workspace
version is defined in Cargo.toml; app versions are independent. CLI candidates can
be staged with `cargo xtask build-sdk cli` in `dist/cli/`.

The iOS build also produces `dist/CubeginSDK-0.1.0/`, its `.zip` and `.sha256`.
Copy the complete package into a product's `Vendor/CubeginSDK` and add that directory
as a local Swift Package (**Cubegin** product). It includes matching bindings,
binaries, tests and notices, and no longer requires the core checkout to build.
Verify checksums and replace the whole package on upgrades. Local candidates are
not published releases; manifests explicitly record packaging-time source state.
