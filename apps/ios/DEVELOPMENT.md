# Cubegin iOS development

## Run

From the repository root on Apple Silicon with Xcode, Node and the pinned Rust toolchain:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
node scripts/build-ios.mjs --app-only
open apps/ios/Cubegin.xcodeproj
```

Select **CubeginApp** and an iPhone/iPad simulator. For a physical device, select a development team in Signing & Capabilities.
The project links the **Cubegin** product from the root Swift Package, which uses
the generated Swift bindings and `dist/CubeginFFI.xcframework`. Rerun the build
command after Core changes. For SDK packaging and isolated consumer tests, run
`cargo xtask build-sdk ios` from the root.

Open `CubeginPreview.xcodeproj` for interface work without building the SDK. It reports an integration error where the real engine is required.

For iCloud settings verification, use a signing profile for the Cubegin App ID with
the iCloud key-value storage capability. Sign into the same iCloud account on two
devices, change a setting on either one, and verify that it reaches the other.
The simulator and preview project use local preferences.

## Tests and CI

Run the **CubeginApp** scheme’s Test action on an iOS simulator to execute the unit
and UI tests. Repository CI builds the App against the Core in the same checkout.
See [testing](docs/testing.md) and the [CI rules](../../docs/ci.md).

## Ownership

`Engine.swift` is a thin background adapter for `generateEvent` and `evaluateEvent` (SVG net). Cube semantics stay in Rust. Swift owns timing, gestures, local JSON persistence, native layout and SVG display in a JavaScript-disabled WKWebView.

## 知识库

- [代理与协作规则](AGENTS.md)
- [架构与产品边界](docs/architecture.md)
- [Core SDK 接入、版本和调用](docs/sdk.md)
- [构建与验证](docs/testing.md)
- [当前状态与待办](docs/status.md)
- [打乱项目中英文名称对照](docs/scramble-names.md)
