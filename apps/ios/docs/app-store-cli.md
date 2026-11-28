# App Store Connect CLI

从 [iOS 发包手册](releasing.md) 进入，在仓库根目录运行。商店操作默认走开源 `asc` 的 App Store Connect API。此流程按 [`asc` 7.4.0](https://github.com/rorkai/App-Store-Connect-CLI/releases/tag/7.4.0) 核对。归档、签名和导出继续用 Xcode，Git 标签记录候选来源。

## 认证和状态查询

用 `asc version` 检查工具。若 App Store Connect API 尚未开通，由 Account Holder 在「用户和访问 → 集成」申请访问。复用已获授权且能访问 Cubegin 的 API Key，按 `asc auth login --help` 配置本机 profile。团队 key 需要 Issuer ID，个人 key 使用 `--key-type individual`。私钥放在凭据存储或仓库外的受控目录。

```sh
asc auth status --validate
asc workflow run ios-status VERSION:1.0.0
```

`ios-status` 查询 iOS 版本的当前 build 和该版本的审核记录。需要缩小输出时，可单独执行 `asc versions view --app 6838818301 --version 1.0.0 --platform IOS --include build` 和 `asc review history --app 6838818301 --version 1.0.0 --platform IOS`。认证失败时区分凭据缺失、权限不足和服务不可用。需要用户认证时给出[集成页面](https://appstoreconnect.apple.com/access/integrations/api)，明确缺少哪一步，之后先复跑只读状态查询。

## 预留构建号及 TestFlight

用 `asc builds list --app 6838818301 --platform IOS --paginate --output json` 查看跨版本已处理的构建，再用 `asc builds uploads list --app 6838818301 --platform IOS --paginate` 核对仍在处理的上传。与远端 `app-build/ios/*` 一起取最高已占用编号。`asc builds next-build-number` 可以辅助查询当前版本序列。按[发包手册](releasing.md#预留归档和登记)预留、归档、签名及登记后，再运行传输流程。

```sh
asc workflow run ios-testflight VERSION:1.0.0 BUILD_NUMBER:8 "IPA_PATH:$ipa_path"
```

这个工作流校验 IPA 与 Git 候选的 SHA-256，上传后保存 Apple build ID，等待处理、分配至 Cubegin Internal，再回读内测组访问状态。仅在确认同版本、同构建号尚未收包时启动上传。若上传已成功但处理或分组失败，先从结果取得 run ID，再用 `asc workflow run ios-testflight --resume RUN_ID` 继续。若上传回执丢失，先用 `asc builds wait --app 6838818301 --platform IOS --version VERSION --build-number BUILD --timeout 50s --report-pending` 查找，查到 build 后按 ID 等待并加入内测组。用 `asc testflight groups list --build-id BUILD_ID` 确认 Cubegin Internal 有访问权。

## 商店资料

[仓库资料目录](../../../store-listing/ios/app-store/README.md)维护实填字段和原图。更新受影响的范围，复用其余资料。先生成 CLI 文件并预览，实际保存后再回读。

```sh
metadata_dir=$(mktemp -d)
node scripts/ios-store.mjs metadata "$version" "$metadata_dir"
asc metadata validate --dir "$metadata_dir" --check-urls
asc metadata push --app 6838818301 --version "$version" --platform IOS \
  --dir "$metadata_dir" --dry-run
```

生成文件包含两种语言的名称、副标题、公开链接、简介和关键词。标记为留空的推广文本不产生覆盖值。如需清空后台字段，单独确认该项。版本更新说明从本版中英文 changelog 提炼，经确认后用 `asc localizations update` 填入相应本地化。实际保存时去掉 `--dry-run`，根据已确认差异使用 `--confirm`，完成后用 `asc metadata pull` 到新的临时目录核对。

### 截图

从 `asc localizations list --version VERSION_ID` 取 `zh-Hans`、`en-US` 的 App Store 版本本地化 ID。`asc localizations placements list --localization-id LOCALE_ID --sort placementGroupPosition` 检查现有内容、设备分组及顺序。新增或重拍时，用仓库原图生成按上传顺序命名的副本。

```sh
screenshots_dir=$(mktemp -d)
node scripts/ios-store.mjs screenshots "$screenshots_dir"
asc screenshots upload --version-localization "$locale_id" \
  --path "$screenshots_dir/zh-Hans/iphone-duo" \
  --device-type APP_IPHONE_DUO --asset-library --dry-run
```

当前 iPhone、iPad、Duo 的设备类型分别为 `APP_IPHONE_61`、`APP_IPAD_PRO_3GEN_129`、`APP_IPHONE_DUO`。每次核对素材库返回的 placement group 和容量。确认新增后去掉 `--dry-run`，保存回执，并用 `asc localizations placements list` 回读。有既有素材时只调整已确认变化的 placements，可用 `swap` 换图，用 `reorder --localization-id LOCALE_ID --placement-group GROUP --placement-ids ID1,ID2` 调整顺序。Duo 核对外屏竖屏在前、内屏横屏在后。

### 首发设置及合规

| 内容 | CLI 核对入口 |
| --- | --- |
| 定价和销售范围 | `asc pricing schedule view --app 6838818301`、`asc pricing availability view --app 6838818301`，再按 availability ID 查询各地区。确需修改时用 `schedule create` 或 `availability edit`。 |
| 分类、内容权利和年龄分级 | `asc apps info view --app 6838818301`、`asc age-rating view --app 6838818301`。按实际批准的字段用 `asc app-setup categories set`、`asc apps update` 或 `asc age-rating edit` 保存。 |
| 审核联系人、备注、附件 | `asc review details-for-version --version-id VERSION_ID`。按需用 `details-create`、`details-update` 或 `attachments-upload` 保存。联系人从受控位置取得，回读结果里的私密字段留在发布机。 |
| 出口合规 | `asc builds info --build-id BUILD_ID` 核对构建，并与 IPA 内 `ITSAppUsesNonExemptEncryption` 比对。适用时按实际签署的声明用 `asc builds update --build-id BUILD_ID --uses-non-exempt-encryption=false` 填报。 |

隐私问卷的填写、发布和协议确认沿用 Apple 页面。CloudKit 可用 `xcrun cktool export-schema --environment production` 配合 team、container 和已有管理凭据读回 schema。生产部署由授权用户在 CloudKit Console 确认。真机测试在设备上验证并记下实际版本和 build。

## 准备审核、送审和发布

用准确的 Apple build ID 准备版本。新版本可用 `asc versions create` 或 `asc release stage` 创建。需要同时套用本地商店资料时，给 `release stage` 传入 `--metadata-dir "$metadata_dir"`。首发和需要手动上架的版本，用 `asc versions update --app 6838818301 --version-id VERSION_ID --release-type MANUAL` 并回读 `releaseType`。

```sh
asc release stage --app 6838818301 --platform IOS --version "$version" \
  --build-id "$build_id" --dry-run
asc release stage --app 6838818301 --platform IOS --version "$version" \
  --build-id "$build_id" --confirm
asc validate --app 6838818301 --version "$version" --platform IOS --check-urls
```

准备审核草稿时，用 `asc review submissions list --app 6838818301 --platform IOS` 找到正在准备的 iOS 草稿，回读其 items。需要新草稿时用 `asc review submissions-create --app 6838818301 --platform IOS`，然后用 `asc review items-add --submission SUBMISSION_ID --item-type appStoreVersions --item-id VERSION_ID --if-exists skip` 加入该版本。用 `asc review items-list` 和 `ios-status` 核对版本、build 与待提交状态。

正式送审与上线是独立动作。收到本轮授权后，用 `asc review submissions-submit --id SUBMISSION_ID --confirm` 送审。Apple 审核通过、版本进入待开发者发布状态且用户授权上线后，用 `asc versions release --version-id VERSION_ID --confirm`。每次都用 `ios-status` 回读实际状态及关联 build。已正式上架后，再按发包手册打正式 tag 并回合。
