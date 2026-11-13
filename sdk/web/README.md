# Cubegin Core — Web SDK

Web/WASM SDK from [cubegin](https://github.com/deweyou/cubegin), published as `cubegin`: 18 standard event IDs, 94 training types, applicable full
solvers, 20 auxiliary methods, FMC validation, SVG nets and 3D geometry/SVG frames.
GPL-3.0-only. This is a new API, not a drop-in replacement for the old TS packages.

Full solvers cover 2x2/3x3/4x4/Pyraminx/Skewb/Square-1/FTO; Clock uses inverse
notation. No full 5x5–7x7 or Megaminx solver. Scrambles are not WCA certified.

Use `eventCatalog`, `typeCatalog`, `trainingCases` and `assistMethods` to discover
IDs. `playerFrame` returns platform-neutral piece geometry; `playerSvg` returns a
projected frame. View widgets and product controls belong to the consumer.

[Development guide](DEVELOPMENT.md)
