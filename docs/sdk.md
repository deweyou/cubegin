# SDK 示例

目录接口暴露所有项目和训练类型 ID。状态保留各魔方的布局，仅原三阶 API 使用单个 URFDLB 面片字符串。构建和接入参见[开发指南](../DEVELOPMENT.md#构建产物与产品接入)。

```ts
import {createWorkerClient} from 'cubegin/worker';
const client = createWorkerClient();
const api = client.engine;
const scramble = await api.generateEvent('fto', 42);
const solvedBy = await api.solveEvent('fto', scramble.algorithm);
const image = await api.evaluateEvent('fto', scramble.algorithm);
// image.svg 是 SVG 展开图，image.state 是该魔方的状态记录。
const cases = await api.trainingCases('333.pll');
const training = await api.generateTraining('333.pll', 42, {
  enabled_case_ids: [cases[0].id], natural: true,
  orientation: {bottomColor: 'white', frontColor: 'green'},
});
const batch = await api.generateBatch('333', 42, 5);
const assist = await api.solveAssist('333', ['cross', 'eoline'], 'R U F', {
  max_depth: 12,
});
const timeline = await api.playerTimeline('sq1', '(1,0) /');
const halfway = await api.playerSvg('sq1', '(1,0) /', 1, 0.5);
const geometry = await api.playerFrame('sq1', '(1,0) /', 1, 0.5);
// 在可信视图展示 SVG，或由应用的 GPU 渲染器绘制几何。
client.dispose();
```

`playerTimeline` 返回 `schemaVersion: 1`、初始拼块几何和操作。`playerFrame` 和 `playerSvg` 接收已完成步数及下一步进度（0 到 1）。终点是 `(steps.length, 0)`，无效位置会报错。展开图是示意图，回放 SVG 采用正交 3D 投影。颜色与相机沿用旧版默认值。

```swift
import Cubegin
// CPU 密集调用由 App 的后台执行器调度。
let s = try generateEvent(event: "pyram", seed: 42)
let result = try evaluateEvent(event: "pyram", algorithm: s.algorithm)
let solution = try solveEvent(event: "pyram", algorithm: s.algorithm)
let trainingJSON = try generateTraining(id: "333.pll", seed: 42, optionsJson: "{}")
let frameSVG = try playerSvg(event: "sq1", algorithm: "(1,0) /", completed: 1, progress: 0.5)
```

```kotlin
import io.github.deweyou.cubegin.*
// 在应用管理的后台 worker 或 dispatcher 调用。
val s = generateEvent("pyram", 42u)
val result = evaluateEvent("pyram", s.algorithm)
val solution = solveEvent("pyram", s.algorithm)
val trainingJson = generateTraining("333.pll", 42u, "{}")
val frameSvg = playerSvg("sq1", "(1,0) /", 1u, 0.5)
```

原生项目记录通过 `stateJson` 暴露状态，结构可变的训练、辅助求解和回放结果使用 JSON 字符串。Swift 和 Kotlin 名称由 UniFFI 生成。iOS App 使用根 Swift Package 的绑定，Kotlin 绑定随 AAR 交付。选项沿用 Web API 的 JSON 键名。`solveAssist` 接收方法名的 JSON 数组，错误通过绑定显式返回。

二、三、四阶、Pyraminx、Skewb、Square-1 和 FTO 支持完整求解。Clock 使用逆公式。大阶和 Megaminx 支持状态、打乱和渲染，调用未支持的完整求解会报错。多盲用 `generateMultiBlind` 并显式传入个数。API 和种子输出稳定性以版本为准。
