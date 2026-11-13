# Cubegin 开发指南

[![English](https://img.shields.io/badge/English-blue)](DEVELOPMENT.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](DEVELOPMENT_ZH.md)

## 开发

需要 Rust 1.96.0、Node >=22.12 和 pnpm 10。Rust 构建由 Cargo 编排，
Vite 用于启动诊断 Web 工作台。

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

Web 工作台地址：http://127.0.0.1:4488。首页直接提供全部标准项目、训练类型／案例选择、
辅助求解方法，以及共享的展开图、动画播放和进度拖动。

```sh
cargo run -p cubegin-cli -- evaluate "R U R' U'"
cargo run -p cubegin-cli -- event-scramble fto 42
cargo run -p cubegin-cli -- training 333.pll 42
cargo run -p cubegin-cli -- assist 333 cross "R U F"
node scripts/verify-legacy.mjs # 可选：调用旧实现做独立语义校验
cargo xtask build-sdk native
node scripts/test-swift.mjs   # macOS：真实 Swift 绑定与原生动态库
cargo xtask verify-packages  # 在独立消费项目安装 npm 压缩包
cargo xtask release --version 0.1.0 --dry-run
```

## CI 检查

各 workflow 根据自己声明的路径触发。Rust Core 改动会触发 Rust、Web、Apple 和
Android 检查，纯 Markdown 改动走文档检查。Apple SDK 和 iOS App 共用一次
XCFramework 构建。合入前确认受影响的检查已通过。参见 [CI 验收](docs/ci.md)。

## 构建产物与产品接入

以下构建命令均在本仓库根目录执行。SDK 构建机器需要 Rust；产品仓库消费构建好的
二进制和语言绑定。`build-sdk native` 用于生成宿主机绑定／库并做冒烟测试；
移动端产物使用下面的 iOS、Android 构建命令。

| 平台 | 构建与打包命令 | 产物 |
| --- | --- | --- |
| iOS | `cargo xtask build-sdk ios` | `dist/CubeginFFI.xcframework`、对应 `.zip`、`sdk/swift/Generated/Cubegin.swift` |
| Android | `cargo xtask build-sdk android` | `dist/android/cubegin.aar`、`dist/maven/` 本地 Maven 仓库（AAR、POM、源码包） |
| Web | `cargo xtask verify-packages` | `dist/cubegin-0.1.0.tgz`，包含 JS、类型声明和 WASM |
| Rust | `cargo xtask verify-rust-packages` | `dist/rust/` 下的 7 个已验证 crate 压缩包 |

### iOS：通过本地 Swift Package 接入

需要 Apple Silicon Mac、Xcode、Node 和仓库固定版本的 Rust：

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
cargo xtask build-sdk ios
```

构建包含 iOS arm64 真机、arm64／x86_64 模拟器及 macOS arm64，并运行 SwiftPM
消费测试；不包含 Intel macOS。最低支持 iOS 15。

仓库内的 [iOS App](apps/ios/DEVELOPMENT.md) 已引用根目录 Swift Package。
构建 SDK 后，打开 App 工程并选择 **CubeginApp**。
在外部 Xcode 工程中：

1. 选择 **Add Package Dependencies → Add Local**，选中本仓库根目录。
2. 给 App target 添加 **Cubegin** 产品。根目录的 [Package.swift](Package.swift)
   会同时引入生成的 Swift 封装和本地 XCFramework。
3. 导入 SDK，在应用自己的后台任务中调用：

```swift
import Cubegin

let scramble = try generateEvent(event: "333", seed: 42)
let snapshot = try evaluateEvent(event: "333", algorithm: scramble.algorithm)
print(scramble.algorithm)
```

修改 Rust 后，先重新构建 SDK，再构建 App。生成的绑定与二进制应来自同一次构建。
SVG 返回值是字符串，原生视图组件和渲染器由产品提供。Square-1 打乱图左右并排显示上下两层。项目 SVG 按图形边界裁切，四边各留 1 个 SVG 单位。

### Android：通过本地 Maven 仓库接入

将 `JAVA_HOME` 配置为 JDK 17 或 21，`ANDROID_HOME` 配置为 Android SDK 目录。
通过 SDK Manager 安装 SDK Platform 35、Build Tools 35.0.0 和 NDK 28.2.13676358。
以下环境路径是 macOS／Android Studio 示例：

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
cargo xtask build-sdk android
```

AAR 包含 Kotlin 绑定及 `arm64-v8a`、`armeabi-v7a`、`x86_64` 原生库。
最低支持 Android API 23。构建脚本还会验证独立 Maven 消费工程。

未来位于 `apps/android/` 的 App 可通过 `../../dist/maven` 使用产物。
对于外部项目，假设产品仓库与 `cubegin` 为同级目录，在产品现有 `settings.gradle.kts` 的仓库配置中添加：

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("../cubegin/dist/maven") }
    }
}
```

在 App 模块的 `build.gradle.kts` 中添加：

```kotlin
dependencies {
    implementation("io.github.deweyou:cubegin:0.1.0")
}
```

然后在应用自己的后台任务中调用：

```kotlin
import io.github.deweyou.cubegin.*

val scramble = generateEvent("333", 42u)
val snapshot = evaluateEvent("333", scramble.algorithm)
println(scramble.algorithm)
```

通过 Maven 接入会自动带上 JNA 5.17.0。若只分发 AAR，消费方还需显式声明
`net.java.dev.jna:jna:5.17.0@aar`。修改 Rust 后重新构建／暂存 SDK。
可参考 [Android 消费工程](examples/android/build.gradle.kts)。

### 本地构建与正式发布

`dist/` 不进入 Git。当前使用本地 Swift Package、本地 Maven 仓库接入，
尚未发布远程 Swift 二进制或注册表包；只填写 Git URL 不会提供本地 XCFramework。
正式远程接入需要上传 XCFramework ZIP，并在 `sdk/swift/Artifact.json` 配置固定 URL
和 checksum，再为 Package 及匹配的绑定建立版本；Android 将带版本的 AAR、POM、
源码包发布到 Maven 仓库。产品随后固定依赖版本，详见[发包说明](docs/releasing.md)。

SDK 中的生成、求解等计算是同步接口，原生产品负责移出 UI 线程；Web 可使用
`cubegin/worker` 的 `createWorkerClient`。各端均提供 `playerTimeline`、`playerFrame`、
`playerSvg` 动画接口。Web 工作台已有播放器；原生 UI 组件与真机渲染验收仍需另行完成。

详见[SDK 示例](docs/sdk.md)、[架构](docs/architecture.md)、[验证](docs/testing.md)、
[来源](docs/provenance.md)和[交付状态](docs/status.md)。
旧实现保留在 Git 提交 `79a1e4c`。

### 统一产物版本与来源信息

所有 SDK/包构建流程共用版本、来源、打包时间和 SHA-256 清单。Web/npm、宿主原生、
iOS、Android、Rust crate 与 CLI 的清单位置见[产物说明](docs/artifacts.md)。
核心版本由 Cargo.toml 管理，App 版本独立。CLI 可通过
`cargo xtask build-sdk cli` 安装到 `dist/cli/`。

iOS 构建还生成 `dist/CubeginSDK-0.1.0/`、对应 `.zip` 和 `.sha256`。将完整包复制到
产品的 `Vendor/CubeginSDK`，添加该目录为本地 Swift Package，链接 **Cubegin**。
包内包含配套绑定、二进制、测试和归属文件，产品构建不再依赖 core 仓库。
安装前验证校验值，升级时整体替换。清单记录的是打包时观察到的源码状态，
本地候选产物不代表公开发布。
