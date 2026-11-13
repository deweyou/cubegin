# Cubegin 图标素材

[English](README.md) · [中文](README_ZH.md)

来自 `deweyou/cubegin` 提交 `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97` 的 `packages/icons/src`。许可证为 GPL-3.0-only，分发时须保留 LICENSE 和 NOTICE。

- `brand/svg` 保存八个原始 SVG，涵盖图形标志、字标、组合标志和 App 图标。
- `events/index.ts` 保存项目图标几何，`events/svg` 包含生成的 18 个 SVG。
- `react/index.tsx` 是原版标志动画参考，冷启动动画已移植到 `Cubegin/LaunchView.swift`。
- `reference` 保存历史设计笔记。

原始素材保存在 App 资源包之外。App 使用 `../../Cubegin/AppIcon.icon`，每种外观使用两个 SVG 图层。黄色、红色和绿色共享 `Base.svg`，蓝色单独作为前景层，并在 Icon Composer 列表中排在前面。保留原版颜色、位置、圆角和蓝色块的 18 度旋转。浅色和深色背景显式配置，透明、着色和 Liquid Glass 效果由系统生成。SVG 图层应保留原始几何。

用 Icon Composer 打开 AppIcon.icon 可预览默认、深色和 Mono 外观。Xcode 通过 `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` 编译图标。2026-11-03 已在 iPhone 17 Pro / iOS 26.3.1 模拟器验证构建、安装及主屏幕默认、深色和透明外观，尚未做真机验收。

## Mono 外观

Mono 在 Icon Composer 中存为 `tinted`，使用 `Base-Mono.svg` 和 `Blue-Mono.svg`。黄、红、绿、蓝的位置依次采用 #ffffff、#d9d9d9、#ebebeb 和 #c9c9c9。底层色块组成连续轮廓，灰度覆盖层裁切在轮廓内，使接缝没有透明间隙或独立玻璃边缘。各外观只启用对应的一对图层，蓝色块保持在前景。
