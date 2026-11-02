# Cubegin Core — Web SDK

Web/WASM SDK from [cubegin-core](https://github.com/deweyou/cubegin-core), published as `cubegin`: 18 standard event IDs, 94 training types, applicable full
solvers, 20 auxiliary methods, FMC validation, SVG nets and 3D geometry/SVG frames.
GPL-3.0-only. This is a new API, not a drop-in replacement for the old TS packages.

```ts
import {createWorkerClient} from 'cubegin/worker';
const client = createWorkerClient();
const s = await client.engine.generateEvent('fto', 42);
const image = await client.engine.evaluateEvent('fto', s.algorithm);
const solution = await client.engine.solveEvent('fto', s.algorithm);
const training = await client.engine.generateTraining('333.pll', 42);
const timeline = await client.engine.playerTimeline('sq1', '(1,0) /');
const frame = await client.engine.playerSvg('sq1', '(1,0) /', 1, 0.5);
client.dispose();
```

For direct synchronous calls, initialize `createCubegin` from `cubegin`; provide
WASM bytes or a module URL where automatic asset resolution is unavailable.
Schedule heavy searches on a Worker. `dispose` terminates pending Worker calls.
Full solvers cover 2x2/3x3/4x4/Pyraminx/Skewb/Square-1/FTO; Clock uses inverse
notation. No full 5x5–7x7 or Megaminx solver. Scrambles are not WCA certified.

Use `eventCatalog`, `typeCatalog`, `trainingCases` and `assistMethods` to discover
IDs. `playerFrame` returns platform-neutral piece geometry; `playerSvg` returns a
projected frame. View widgets and product controls belong to the consumer.
See repository docs/sdk.md, docs/testing.md and docs/provenance.md for contracts,
validation and attribution.
