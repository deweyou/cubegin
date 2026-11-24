# Cubegin iOS development

## Run

From the repository root on Apple Silicon with Xcode, Node and the pinned Rust toolchain:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
node scripts/build-ios.mjs --app-only
open apps/ios/Cubegin.xcodeproj
```

Build, install, and launch the latest **CubeginApp** on an iPhone simulator and leave it open where the change can be tested. Use the requested iPad, Duo, or physical device for device-specific review.
Use the separate [Cubegin Dev build](docs/testing.md#本地真机安装) for local debugging on a physical device.
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

`Engine.swift` is a thin background adapter for `generateEvent`, `evaluateEvent` (SVG net), and `solveAssist` (formula hints). Cube semantics stay in Rust. Swift owns timing, gestures, local JSON persistence, native layout and SVG display in a JavaScript-disabled WKWebView.

## 知识库

- [代理与协作规则](AGENTS.md)
- [架构与产品边界](docs/architecture.md)
- [Core SDK 接入、版本和调用](docs/sdk.md)
- [构建与验证](docs/testing.md)
- [当前状态与待办](docs/status.md)
- [打乱项目中英文名称对照](docs/scramble-names.md)

## 版本记录和更新检查

候选构建、商店资料、送审和回合见 [iOS 发包手册](docs/releasing.md)。

发版时在 [英文更新记录](CHANGELOG.md) 和 [中文更新记录](CHANGELOG_ZH.md) 顶部各增加一个 `## 版本号`，
每条变化用一行 Markdown 列表项。主工程和预览工程直接打包这两份文件。从第二个公开版本起，将本版本条目用于 App Store Connect 的「此版本的新功能」。

「检查更新」按 App Store 地区查询正式版。Lookup 默认使用正式版的 Bundle ID。
获得 App Store Connect 的数字 Apple ID 后，可通过 Xcode 构建设置 `CUBEGIN_APP_STORE_ID` 指定。
调试构建可加启动参数 `-cubegin-show-about -cubegin-preview-app-update`，启动时进入设置，再在「关于」用样例验证更新提示。
