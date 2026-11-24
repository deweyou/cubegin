# Cubegin iOS 发包

从 [App 发布规范](../../../docs/app-releasing.md) 进入。正式 scheme 为 `CubeginApp`，Bundle ID 为 `io.github.deweyou.cubegin`。Xcode 工程以 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 维护公开版本与 build。中英文版本条目保留现有 `## X.Y.Z` 格式，App 内「关于」直接读取。

## 出包前

1. 在 App Store Connect 对齐 iOS 版本草稿、正式 Bundle ID 和版本号。查看跨版本的上传历史，首次启用时以已上传的最高 build 和远端已预留编号为下限。首发说明写产品能力，后续更新再写「此版本的新功能」。
2. 根据 [商店资料目录](../../../store-listing/ios/app-store/README.md) 准备各语言文案和实际设备类别的截图。核对审核联系人、审核说明、支持链接、隐私链接、价格、地区、分级、内容权利，以及适用的出口和地区声明。
3. 逐项比对正式包内隐私清单、公开隐私政策、商店隐私问卷和生产 Firebase、GA4、Sentry 的数据做法。按实际核对用途、安装标识关联、粗略位置、广告共享及适用的 Tracking 定义。保存隐私问卷后回读它的发布状态。

## 预留、归档和登记

- 在候选分支更新 Xcode 版本设置并提交。用 `git fetch origin --tags` 和 `git ls-remote --tags --refs origin 'refs/tags/app-build/ios/*'` 核对预留编号和提交。用 `app-build/ios/N` 轻量 tag 标记候选 SHA，将分支与该 tag 一起推送，例如 `git push --atomic origin HEAD:refs/heads/release/ios/0.1 refs/tags/app-build/ios/1`。如果编号被别的候选占用，获取最新状态再递增。远端已记录同一 SHA 时继续使用原编号。
- 从已预留的 SHA 开始，运行 `node scripts/build-ios.mjs --app-only` 构建同一 checkout 的 SDK。核对生成绑定、正式团队签名和 CloudKit entitlement，并按 [真机诊断文档](testing.md#真机验证故障诊断) 配置正式诊断文件。
- 用 Xcode Release Archive 归档。读归档里的 `CFBundleIdentifier`、`CFBundleShortVersionString`、`CFBundleVersion`，与商店草稿和候选记录互相核对。保留原始 `.xcarchive` 和匹配的 dSYM。将归档压成 ZIP 存入有权限控制的持久位置，用 `shasum -a 256 <archive.zip>` 生成校验和。若单独导出并上传 IPA，也保存该文件与校验和。
- 用附注 tag `app-candidate/ios/N` 指向候选 SHA。注释记录 bundle ID、版本、build、完整 SHA、归档 ZIP 的 SHA-256、归档和 dSYM 的存放位置标识，以及适用的 IPA SHA-256。推送该 tag 前核对预留 tag 指向同一 SHA。重试前检查远端是否已有同一记录。已有记录冲突时保留现场，正式 tag 和候选记录禁止移动或覆盖。
- 通过 Organizer 上传登记的归档。由仓库分配 build，关闭分发选项里的自动管理版本和构建号。上传后回读 App Store Connect 的版本、build 和处理状态。若显示 `Missing Compliance`，根据候选及其实际依赖核对加密出口问卷，再继续 TestFlight。

## 送测、提审和上线

- 将候选分配给内部测试组，从 TestFlight 安装。记录设备、iOS 版本和实际 build。验收计时、保存及重启重读、DCTimer 导入、iCloud 生产环境同步、诊断同意和隐私入口。可以安装和启动之后，再核对核心功能是否通过。
- 选同一 build 提审。隐私问卷已保存和已发布分别核对。通过 `Add for Review` 只代表加入审核草稿。执行 `Submit for Review` 后回读状态，确认 Apple 已收到。
- 首发采用手动发布。审核通过但待发布时，继续等待上线动作。收尾前从 App Store Connect 核对正式分发状态和实际关联 build，再依据远端候选记录打 `ios/vX.Y.Z`。需要确认某地区可用时单独核对该地区。真实 App Store Connect API 查询可以替代后台人工核对，查询失败或 build 缺记录时先核对来源。
