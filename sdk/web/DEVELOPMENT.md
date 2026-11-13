# Web SDK development

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

Run `cargo xtask verify-packages` from the repository root to build and verify the npm package. See the [workspace verification guide](../../docs/testing.md).
