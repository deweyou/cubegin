# Cubegin Web SDK

[English](https://github.com/deweyou/cubegin/blob/main/sdk/web/README.md) · [中文](https://github.com/deweyou/cubegin/blob/main/sdk/web/README_ZH.md)

Web/WASM 包名为 `cubegin`，提供 18 类标准项目、94 类训练、完整求解、20 种辅助求解、最少步校验、SVG 展开图以及 3D 几何和 SVG 回放帧。许可证为 GPL-3.0-only。新版 API 与旧 TypeScript 包不兼容。

二、三、四阶魔方、Pyraminx、Skewb、Square-1 和 FTO 支持完整求解。Clock 使用逆公式，五至七阶和 Megaminx 暂无完整求解。打乱未获得 WCA 认证。

用 `eventCatalog`、`typeCatalog`、`trainingCases` 和 `assistMethods` 查询 ID。 `playerFrame` 返回平台无关的拼块几何，`playerSvg` 返回投影后的帧。界面和控件由接入方提供。

[开发指南](https://github.com/deweyou/cubegin/blob/main/sdk/web/DEVELOPMENT.md)
