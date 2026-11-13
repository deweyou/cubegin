# Artifact identity and installation

`Cargo.toml` `[workspace.package].version` is the core SDK version source (currently
0.1.0). Web and Android package declarations must remain aligned; the release dry
run checks them. App versions are independent. Builds produce local candidates,
not remote releases, and a dirty candidate is not uniquely identified by version.

All build/package scripts use `scripts/artifact-metadata.mjs` and schemaVersion 1:

- `artifact`: product/platform identity; `version`: Cargo workspace version.
- `sourceCommit`, `sourceDirty`: Git observation, including untracked files.
- `sourceObservation: packaging-time`: explicitly not a clean-build attestation.
- `packagedAt`: UTC packaging time; it is not necessarily compilation time.
- `license: GPL-3.0-only`; `files`: relative paths to SHA-256 file digests.

Paths resolve relative to the manifest's directory. The manifest excludes itself;
ZIP/tarball checksum sidecars cover the final archive including its inner manifest.
Symlinks and paths outside the inventory root are rejected. File hashes detect
corruption, not publisher authenticity; compare archive checksums with a trusted
build record before installation. Preserve the source snapshot of dirty candidates.

| Build/package command | Manifest and scope |
| --- | --- |
| `cargo xtask build-sdk web` | `sdk/web/SDK.json`: JS/types, WASM, package declaration and notices; included in npm package |
| `cargo xtask verify-packages` | `dist/npm-SDK.json`: actual npm tarball; `.tgz.sha256` alongside it |
| `cargo xtask build-sdk native` | `dist/native/SDK.json`: copied host library, Swift/Kotlin bindings and notices; host-specific diagnostic bundle |
| `cargo xtask build-sdk ios` | `dist/CubeginSDK-<version>/SDK.json`: self-contained Swift package; versioned ZIP and `.sha256`; `dist/xcframework-SDK.json` identifies the standalone XCFramework ZIP |
| `cargo xtask build-sdk android` | `dist/android-SDK.json`: `android/cubegin.aar` and Maven AAR/POM/sources inventory; copy this manifest with the dist-relative layout |
| `cargo xtask verify-rust-packages` | `dist/rust/SDK.json`: seven verified `.crate` archives; each archive gets `.sha256` |
| `cargo xtask build-sdk cli` | `dist/cli/SDK.json`: host CLI and notices |

These inventories identify candidates. Host, consumer, device and remote publication
results remain separate evidence. Building an arbitrary Rust target directly with
Cargo does not run packaging or generate these manifests. Existing artifact paths
and registry coordinates remain unchanged. Android metadata accompanies the staged
repository, rather than changing Maven's standard POM format. Rust metadata is a
sidecar, rather than changing Cargo's crate format.

## Apple product integration

The iOS app in this repository references the root Swift Package and consumes
`dist/CubeginFFI.xcframework` directly. For an external product:

Copy the complete extracted `CubeginSDK-<version>` directory into a product, e.g.
`Vendor/CubeginSDK`, and add that directory as a local Swift Package using its
**Cubegin** product. It includes matching generated bindings, XCFramework, package
consumer tests, LICENSE, NOTICE and provenance. It builds independently of a core
checkout. Never update just the wrapper or binary. `scripts/package-ios.mjs` stages
and tests the complete copied package; the iOS build invokes it automatically.
