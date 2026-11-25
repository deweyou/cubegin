# Cubegin iOS 发包

从 [App 发布规范](../../../docs/app-releasing.md) 进入。正式 scheme 为 `CubeginApp`，Bundle ID 为 `io.github.deweyou.cubegin`。Xcode 工程以 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 维护公开版本与 build。中英文版本条目保留现有 `## X.Y.Z` 格式，App 内「关于」直接读取。

商店状态、TestFlight、商店资料和审核操作默认走 [App Store Connect CLI](app-store-cli.md)。调用前确认本轮目标和已获授权。App Store Connect 用于账号授权、隐私问卷以及 CLI 暂时不可用时的状态核对。CloudKit 生产部署在 CloudKit Console 确认。

## 出包前

1. 用 CLI 对齐 iOS 版本草稿、正式 Bundle ID 和版本号。查看跨版本的上传历史，以已上传的最高 build 和远端已预留编号为下限。首发说明写产品能力，后续更新再写「此版本的新功能」。
2. 从[商店资料目录](../../../store-listing/ios/app-store/README.md)复用各语言填写值、设备截图及顺序。只更新受候选或发行策略影响的内容。每次更改后回读后台，将实填字段和上传原图同步回仓库。审核联系人从后台复用。送审前核对支持和隐私链接、价格、地区、分级、内容权利，以及适用的出口和地区声明。
3. 逐项比对正式包内隐私清单、公开隐私政策、商店隐私问卷和生产 Firebase、GA4、Sentry 的数据做法。按实际核对用途、安装标识关联、粗略位置、广告共享及适用的 Tracking 定义。保存隐私问卷后回读它的发布状态。

## 预留、归档和登记

- 在候选分支更新 Xcode 版本设置并提交。用 `git fetch origin --tags` 和 `git ls-remote --tags --refs origin 'refs/tags/app-build/ios/*'` 核对预留编号和提交。用 `app-build/ios/N` 轻量 tag 标记候选 SHA，将分支与该 tag 一起推送，例如 `git push --atomic origin HEAD:refs/heads/release/ios/0.1 refs/tags/app-build/ios/1`。如果编号被别的候选占用，获取最新状态再递增。远端已记录同一 SHA 时继续使用原编号。
- 从已预留的 SHA 开始，运行 `node scripts/build-ios.mjs --app-only` 构建同一 checkout 的 SDK。核对生成绑定、正式团队签名和 CloudKit entitlement，并按 [真机诊断文档](testing.md#真机验证故障诊断) 配置正式诊断文件。
- 用 Xcode Release Archive 归档。读归档里的 `CFBundleIdentifier`、`CFBundleShortVersionString`、`CFBundleVersion`，与商店草稿和候选记录互相核对。保留原始 `.xcarchive` 和匹配的 dSYM。将归档压成 ZIP 存入有权限控制的持久位置，用 `shasum -a 256 <archive.zip>` 生成校验和。若单独导出并上传 IPA，也保存该文件与校验和。
- 用附注 tag `app-candidate/ios/N` 指向候选 SHA。注释记录 bundle ID、版本、build、完整 SHA、归档 ZIP 的 SHA-256、归档和 dSYM 的存放位置标识，以及适用的 IPA SHA-256。推送该 tag 前核对预留 tag 指向同一 SHA。重试前检查远端是否已有同一记录。已有记录冲突时保留现场，正式 tag 和候选记录禁止移动或覆盖。
- 导出用于 App Store Connect 分发的签名 IPA，关闭分发选项里的自动管理版本和构建号。按 [TestFlight CLI 工作流](app-store-cli.md#预留构建号及-testflight)校验登记的 IPA、上传、等待处理并核对内部测试组。若显示 `Missing Compliance`，根据候选及其实际依赖核对加密出口问卷，再继续 TestFlight。
- CLI 上传遇到账号错误时，先核对后台有无该 build。若确认尚未收包且无法及时恢复 CLI 认证，可用已登录的 Transporter 交付同一份 IPA。1.0.0（8）曾因 `rsync` 的 `--extended-attributes` 选项不兼容而导出失败，将导出命令的 `PATH` 设为 `/usr/bin:/bin:/usr/sbin:/sbin` 后，同一个归档导出成功。

## 送测、提审和上线

- 核对正式 CloudKit 容器的 Production schema 已部署 `CubeginResult`（`payload` 为 Bytes）和 `CubeginAnalyticsIdentity`（`uuid` 为 String）。
- 将候选分配给内部测试组，从 TestFlight 安装。记录设备、iOS 版本和实际 build。验收计时、保存及重启重读、DCTimer 导入、iCloud 生产环境双机同步、诊断同意和隐私入口。可以安装和启动之后，再核对核心功能是否通过。
- 用 `asc workflow run ios-status VERSION:X.Y.Z` 回读版本、build 和审核记录。查询失败或 build 缺记录时，先回到上传记录核对来源。

| 本轮目标 | 以此状态验收 |
| --- | --- |
| 上传到 TestFlight | App Store Connect 显示上传处理完成，相同 build 在已有内部测试组显示 `Testing`。如果仍为 `Processing`，继续回读并处理能并行的商店资料。 |
| 准备提审 | CLI 已绑定验收的 build，隐私问卷已发布，审核草稿已包含该版本且可提交。需要用户从页面确认时，直达同一草稿。 |
| 正式提审 | 按已获授权通过 CLI 送审，或把页面交给用户点击 `Submit for Review`。回读同一版本与 build 状态为 `Waiting for Review` 或 Apple 已进入后续审核状态。 |
| 正式上线 | 首发采用手动发布。首发审核通过后在授权范围内推进上线。从 App Store Connect 核对正式分发状态及实际 build，再按远端候选记录打 `ios/vX.Y.Z` 并回合。 |

送审后若只需修改商店资料，先看当前状态下对应字段是否开放。1.0.0（8）在 `Waiting for Review` 时可以直接编辑两种语言的 Description。保存后回读文本、审核状态和 build。需要换包时走候选返工流程，先确认是否涉及撤回当前审核。
