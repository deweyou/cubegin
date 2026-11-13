# 代码规范

遵循模块现有风格。需要一致执行的规则应由工具检查。Swift、Kotlin 和 WASM
绑定通过生成器维护，格式调整限于本次改动范围。

| 语言 | 约定 | 当前验证 |
| --- | --- | --- |
| Rust | 遵循 [Rust 风格指南](https://doc.rust-lang.org/style-guide/)和 [Clippy](https://doc.rust-lang.org/clippy/)。魔方语义放在 Rust，用独立样例、不变量或回放验证。 | `cargo xtask check` 检查格式，运行工作区 Clippy（警告视为错误）和测试。 |
| Swift | 遵循 [Swift API 设计指南](https://www.swift.org/documentation/api-design-guidelines/)和 [iOS 模块约定](../apps/ios/AGENTS.md)。保持 actor 隔离，将同步引擎调用移出 UI actor。 | `swiftlint lint --strict` 检查手写 Swift。App 改动构建并测试 `CubeginApp`，SDK 改动验证包和独立消费方。 |
| TypeScript / JavaScript | 使用严格 TypeScript，在外部接口保留明确类型，Node 脚本沿用仓库的 ESM 风格。 | `pnpm lint` 运行 ESLint 和 typescript-eslint，`pnpm check` 检查 Web SDK 与工作台类型，`pnpm test` 验证 SDK，`pnpm test:e2e` 验证工作台。 |

SwiftLint 使用仓库根目录的 `.swiftlint.yml`，CI 固定版本并验证下载校验和。
生成绑定由生成器维护。SwiftUI 实现和审查可按需加载项目级
[SwiftUI Pro](../.agents/skills/swiftui-pro/SKILL.md)，以项目的部署目标和 Xcode 版本为准。

- [Swift Concurrency Pro](../.agents/skills/swift-concurrency-pro/SKILL.md) 用于引擎后台调用、打乱预取和导入流程的并发审查。
- [Swift Testing Pro](../.agents/skills/swift-testing-pro/SKILL.md) 用于 `CubeginTests` 的 Swift Testing 单测。UI 测试继续用 XCUITest。


TS/JS 使用 [typescript-eslint 推荐配置](https://typescript-eslint.io/getting-started/)
和 ESLint 推荐规则。检查范围包括 SDK、工作台、浏览器测试和 Node 脚本，TypeScript 类型检查单独运行。

- [Rust Best Practices](../.agents/skills/rust-best-practices/SKILL.md) 用于 Rust 实现和审查时的所有权、借用、错误处理与 API 设计判断。以本仓库的模块边界和 Clippy 检查为准。
- [TypeScript Advanced Types](../.agents/skills/typescript-advanced-types/SKILL.md) 用于 SDK 公共类型、泛型和复杂类型推导。日常 JS/TS 检查用 ESLint 和 TypeScript 类型检查。
