# 验证

| 层级 | 可复现的验证 |
| --- | --- |
| 状态 | 22 个原三阶样例和 223 个旧版多魔方样例，覆盖 Clock 面板旋转、合法性和逆操作 |
| 标准项目 | 真实 WASM 验证 17 个单魔方项目及显式多盲批次，回放可用的完整求解 |
| 训练 | 188 个独立验证状态，94 类 × 种子 42 和 7，覆盖末尾案例、自然权重、朝向和无效输入 |
| 辅助求解 | 40 组样例、200 条解法，覆盖 20 种方法和不同长度打乱，由旧版目标验证器检查 |
| 回放 | 12 种模型的拼块位置与四元数逆向往返、任意定位、元组合法性和无效位置 |
| Web | 真实 WASM、训练、案例、批次、FMC、辅助求解和回放，以及 Worker 浏览器消费 |
| Swift/Kotlin | 生成的绑定与宿主库，共享样例、错误、打乱、求解、训练、辅助求解和 SVG 帧 |
| 包 | 七个 Rust crate、独立 npm 安装、解压 XCFramework 的 SwiftPM 消费、Maven AAR 消费及三种 ELF 架构 |
| E2E | Chromium 测试和截图基线，覆盖展开图、回放、目录、训练案例与朝向、辅助求解、错误恢复和窄屏 |

运行 `cargo xtask check` 后，按[开发指南](../DEVELOPMENT.md)构建 SDK 并验证。`cargo test --release -p cubegin-solver -- --ignored` 单独执行 4×4/FTO 冷启动求解回放。`cargo xtask verify-rust-packages` 使用全新的临时 registry 验证归档，避免同版本 Cargo 源缓存复用。触发规则见 [CI 验收](ci.md)。

`node scripts/verify-legacy.mjs` 将[旧版实现](provenance.md)提取到临时目录，独立验证状态和求解目标并输出数量，结束时删除临时文件。该步骤需要旧提交及 Web 构建依赖。Rust 测试重新生成结果并与样例比较，Web 还检查实际绑定和回放。

Kotlin 冒烟测试需将 JNA 5.17.0 JVM jar 放到 `target/kotlin-test/jna.jar`，设置 JAVA_HOME 和可选 KOTLINC，生成原生绑定后运行 `node scripts/test-kotlin.mjs`。

仅在视觉变更明确时运行 `pnpm test:e2e --update-snapshots`，并检查生成图像。现有基线面向 macOS Chromium。其他系统的栅格结果需独立评审。

产物清单测试用 `node --test scripts/artifact-metadata.test.mjs`，也由 `cargo xtask check` 执行。覆盖独立 SHA-256 样例、内容变化以及缺失路径、越界路径和软链。打包改动后重建对应平台，并运行独立消费验证。

这些检查覆盖样例和回归约定。真机运行、原生 GPU 渲染、性能、模糊测试、随机性审计和远程发布需分别验收。
