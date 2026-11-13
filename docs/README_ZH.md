<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../apps/ios/Design/LegacyIcons/brand/svg/cubegin-lockup-dark.svg">
  <img src="../apps/ios/Design/LegacyIcons/brand/svg/cubegin-lockup.svg" alt="Cubegin logo" width="260">
</picture>

# Cubegin

[![English](https://img.shields.io/badge/English-blue)](https://github.com/deweyou/cubegin/blob/main/docs/README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](https://github.com/deweyou/cubegin/blob/main/docs/README_ZH.md)

Cubegin 是一个魔方速拧计时和训练项目，包含原生 iPhone、iPad App 和可复用的 Rust 魔方引擎。

## iPhone 和 iPad App

记录还原用时，按项目和训练类型练习打乱，分组管理成绩，查看滚动平均和统计图表，也可以导入 DCTimer 的历史成绩。App 使用 SwiftUI，支持 iOS 和 iPadOS 26 及以上版本。

[了解 iOS App](https://github.com/deweyou/cubegin/blob/main/apps/ios/README.md)

## 魔方引擎

Rust 引擎提供标准打乱、训练打乱、完整求解和辅助求解、SVG 展开图与 3D 转动回放。应用可通过 Swift、Kotlin 或 Web/WASM 使用这些能力。

[Swift SDK](https://github.com/deweyou/cubegin/blob/main/sdk/swift/README.md) · [Android SDK](https://github.com/deweyou/cubegin/blob/main/sdk/android/README.md) · [Web SDK](https://github.com/deweyou/cubegin/blob/main/sdk/web/README.md)

[开发指南](https://github.com/deweyou/cubegin/blob/main/DEVELOPMENT_ZH.md) · [GPL-3.0-only](https://github.com/deweyou/cubegin/blob/main/LICENSE)
