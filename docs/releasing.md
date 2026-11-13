# Release process

Core Rust crates and Web/Swift/Android SDKs share `0.1.0`. No package has been
published by this rebuild. Registry ownership and final package names remain unverified.

For executable local product setup, see the development guide sections for
[iOS Swift Package](../DEVELOPMENT.md#ios-local-swift-package) and
[Android Maven](../DEVELOPMENT.md#android-local-maven-repository), or the
[Chinese instructions](../DEVELOPMENT_ZH.md#构建产物与产品接入).
They cover prerequisites, artifact paths, dependency configuration and SDK calls.
`build-sdk native` only builds host libraries/bindings; it does not replace the
platform builds. Bindings and their binary must come from the same build.

## Build and verify

1. Run `cargo xtask check`, build Web, run SDK and browser tests.
2. Run `cargo xtask build-sdk native` and `node scripts/test-swift.mjs` on macOS.
3. Build Apple XCFramework with `cargo xtask build-sdk ios`; it also extracts the zip
   into an isolated SwiftPM consumer and tests that package. The iOS app picks up
   the resulting XCFramework through the root Swift Package. Run the
   [iOS app build and tests](../apps/ios/docs/testing.md).
4. On Android build hosts set JAVA_HOME (JDK 17 or 21), ANDROID_HOME and ANDROID_NDK_HOME
   (currently NDK 28.2.13676358), install `cargo-ndk` 4.1.2 and Rust targets `aarch64-linux-android`,
   `armv7-linux-androideabi`, `x86_64-linux-android`, then run
   `cargo xtask build-sdk android`. It stages Maven artifacts locally, verifies the three native ABI entries, and
   runs `examples/android` against the Maven artifact (host-native test runtime).
   It does not publish remotely or replace Android-device runtime verification.
5. `cargo xtask verify-packages` packs npm and installs it in an isolated consumer.
6. `cargo xtask verify-rust-packages` builds all seven crate archives through Cargo's
   temporary registry, including unpublished path dependencies. Each run uses a fresh
   temporary registry path to prevent same-version Cargo cache reuse; verified
   archives are copied into `dist/rust/`.
7. `cargo xtask release --version 0.1.0 --dry-run` verifies versions and writes a
   release plan. This command intentionally cannot publish.

## Public release (not wired yet)

- Prepare a release PR with aligned versions, changelog, API compatibility review,
  license inventory and all consumer checks. Commit generated Swift sources so the
  Swift package tag is self-contained; generated Rust/C headers belong to XCFramework.
- Build once from the approved commit and retain checksums, commit ID and evidence.
- Upload XCFramework to an immutable release asset URL. Set `sdk/swift/Artifact.json`
  to `{ "url": "…", "checksum": "…" }`, commit the release metadata and re-test
  remote SwiftPM consumption before tagging. Without this file SwiftPM uses local dist.
- Publish `cubegin-tnoodle` first, then puzzle → solver/diagram/playback →
  scramble → `cubegin`; SDK binding
  crates remain internal (`publish=false`). Verify each crate tarball first.
- Publish npm using trusted publishing/OIDC; publish signed AAR/POM/sources through
  Maven Central Portal after namespace setup. Registry publication is not atomic.
- Record each registry status separately; retry missing outputs without overwriting
  an existing version. Mark release complete only after remote consumer verification.

The initial CI uploads candidate artifacts only. Signing, credentials, registry
publication, remote SPM metadata generation and complete transitive notices are
explicitly unfinished. No `git tag`, push or registry upload is performed by xtask.

## Candidate metadata

All artifact pipelines use the shared schema and inventory rules in
[artifacts.md](artifacts.md). Build-time platform/package outputs and archive
sidecars retain version, packaging-time source observation and file checksums.
The iOS build also stages a self-contained Swift package for copying into product
repositories. These files do not replace clean approved sources, consumer checks,
license review or immutable publication. Version alone never identifies a dirty
candidate. CLI packaging uses `cargo xtask build-sdk cli`.
