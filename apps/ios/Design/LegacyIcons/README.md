# Cubegin icon sources

[English](README.md) · [中文](README_ZH.md)

Copied from `deweyou/cubegin` commit
`79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`, `packages/icons/src`.
License: GPL-3.0-only; retain the repository LICENSE and NOTICE when distributing.

- `brand/svg`: eight original logo, wordmark, lockup and app icon SVGs.
- `events/index.ts`: original event icon geometry; `events/svg` contains its 18 generated SVGs.
- `react/index.tsx`: original logo animation reference, not an iOS runtime dependency.
- `reference`: historical design notes, not active development instructions.

The original files are preserved as design sources outside the app resource bundle.
The app uses `../../Cubegin/AppIcon.icon`, a native Icon Composer document with
two active SVG layers per appearance derived from the original mark. Yellow, Red and Green share
one Base.svg layer so they have no inter-layer stacking or cast shadows; Blue
is a separate foreground layer. Original colors, placement,
corner radii and the blue tile's 18-degree rotation are retained. Icon Composer
orders layers front-to-back, so Blue is listed first to match SVG painter order
(Blue drawn last, above the shared base plane). System Light and
System Dark backgrounds are explicitly configured; the system generates clear and
tinted appearances and Liquid Glass material effects. Do not bake outer icon masks,
shadows or glass highlights into the SVG layers.

Open AppIcon.icon in Icon Composer to preview Default, Dark and Mono. Xcode compiles
it through the app target's resource phase with `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`.

Verified on 2026-11-03: CubeginApp simulator build and installation; Default, Dark
and Mono previews in Icon Composer; default, dark and clear appearances on the
iPhone 17 Pro / iOS 26.3.1 simulator Home Screen. Physical-device acceptance remains
unverified. The original React animation is ported to Cubegin/LaunchView.swift for cold launch.

## Mono appearance

Mono (stored as `tinted` appearance by Icon Composer) uses Base-Mono.svg and
Blue-Mono.svg with tuned grayscale fills: yellow position #ffffff, red #d9d9d9,
green #ebebeb, blue #c9c9c9. The base tiles meet with zero gap in a single continuous compound silhouette, preserving
the original rounded-square geometry with grayscale boundaries but no transparent gaps or separate
glass edges along shared seams. Tone overlays are clipped to the continuous base
silhouette so its alpha contour stays seamless.
The original colored Base.svg and Blue.svg remain unchanged. Per-appearance
opacity enables only the matching pair of layers; the blue tile remains in front.
