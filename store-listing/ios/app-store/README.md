# App Store 商店资料

这里保存 Cubegin iOS 的商店填写值和上传原图。当前基线是 1.0.0（build 8）。后续发布可以直接复用，改动时同步仓库与 App Store Connect，保存后按语言和设备回读。历次改动可从 Git 历史追溯。

| 资料 | 保存方式 |
| --- | --- |
| 名称、副标题、简介、关键词和公开链接 | [简体中文](zh-Hans.md) · [English (U.S.)](en-US.md) |
| 分类、定价、销售范围、审核信息、隐私和合规 | [当前填写记录](submission.md) |
| App 版本更新说明 | 从[中文](../../../apps/ios/CHANGELOG_ZH.md)和[英文](../../../apps/ios/CHANGELOG.md)更新记录提炼。 |

## 截图

每组依次展示计时首页、成绩列表、统计趋势、辅助公式。`iphone-timer.jpg` 和 `ipad-timer.jpg` 分别是各自组的第一张。iPhone Duo 先放外屏竖屏四张，再放内屏横屏四张。

| App Store Connect 分组 | 原图尺寸 | 简体中文 | English (U.S.) |
| --- | --- | --- | --- |
| 带灵动岛的 iPhone（中等显示屏） | 1206 × 2622 | [4 张](screenshots/zh-Hans/iphone/) | [4 张](screenshots/en-US/iphone/) |
| iPad 13 英寸显示屏 | 2064 × 2752 | [4 张](screenshots/zh-Hans/ipad/) | [4 张](screenshots/en-US/ipad/) |
| iPhone Duo | 外屏 1398 × 2034，内屏 2853 × 2007 | [8 张](screenshots/zh-Hans/iphone-duo/) | [8 张](screenshots/en-US/iphone-duo/) |

以上原图随 1.0.0（build 8）送审。尺寸为本次原图的实测值。重新出图时，按当前媒体管理分组确认规格，用候选 App 和测试数据截取受影响的页面。上传后检查处理完成、图数和顺序，再替换仓库对应原图。

## 更新时机

- 修改对外能力、术语或网址时，核对受影响的语言并更新相应文件。送审前打开公开支持和隐私链接，核对与候选构建一致。
- 修改隐私相关功能、生产 SDK 配置、价格或发行地区时，回读实际填写值并更新填写记录。隐私问卷同时核对保存与发布状态。
- 审核联系人的私密字段、登录凭据、私钥及签名文件保存在 App Store Connect 或受控的凭据存储中。发布流程见 [iOS 发包手册](../../../apps/ios/docs/releasing.md)。
