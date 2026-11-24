# Cubegin 隐私政策

## 成绩和设置

Cubegin 在设备上保存计时成绩、分组和打乱记录。从文件导入的 DCTimer 成绩也保存在设备上。计时和显示设置可通过你的 iCloud 账户在设备之间同步。支持 iCloud 成绩同步的版本也可同步成绩和分组。Cubegin 的诊断和使用统计不包含成绩明细、打乱内容或导入文件内容。

## 可选的诊断和使用数据

当你选择「同意」后，Cubegin 会使用两项服务修复问题并了解功能使用情况：

**Google Analytics for Firebase** 接收固定分类的操作失败事件、应用构建号，以及启动到计时页可操作、准备打乱和显示打乱图的耗时。打乱准备的记录包含当前魔方项目、是否切换项目和是否命中预加载。它也记录首次打开、应用版本、会话、前台活跃时长和设备信息等基础统计。如版本包含产品埋点，这些事件用于统计哪些功能被使用。

统计页会记录滚动平均结果就绪的耗时和分组成绩量区间。支持 iCloud 成绩同步的版本也会记录同步尝试的耗时、结果、网络类型和记录数量区间，并区分首次同步和后续同步。

**Sentry** 接收崩溃报告和部分需要排查的非致命错误。报告可能包含调用栈、系统及 App 版本、设备型号和错误分类。

Cubegin 为每次安装生成一个随机设备 ID，用于查找 Sentry 诊断。如需联系支持，可在「设置 → 关于」连点五次「版本」复制它。启用 iCloud 同步且同意共享时，Cubegin 会从 iCloud 私有数据库读取或创建一个独立的随机用户 ID，并将它用于 Google Analytics for Firebase 的跨设备统计。Apple 账户资料仅用于 iCloud 同步。诊断和使用数据用于改进 Cubegin。

更多信息见 [Google 如何处理合作伙伴应用的数据](https://policies.google.com/technologies/partner-sites)和 [Sentry 隐私政策](https://sentry.io/privacy/)。

## 管理共享与联系

通过「反馈与评价」主动发送反馈时，Cloudflare 会把你填写的内容、选填邮箱和你选择附上的截图发送到 Cubegin 的支持邮箱。网页反馈会注明来源。App 反馈还会附上设备型号、系统版本、App 版本、当前安装的设备 ID，以及已绑定的用户 ID（如有）。我们用这些信息处理反馈，并在你留下邮箱时与你联系。iOS App 在本机记住最近一次成功提交的邮箱，网页版将它保存在当前浏览器中，方便下次填写。点邮箱旁的清空按钮可删除记住的地址。即使关闭诊断和使用数据共享，你也可以发送反馈。

你可以在「设置 → 关于 → 隐私 → 帮助改进 Cubegin」随时开启或关闭。关闭后，Cubegin 停止发送新的诊断和使用数据。已发送的记录按各服务的保留设置保存。若对隐私有疑问，或希望请求删除此前的上报记录，可以通过 App Store 产品页的「App 支持」入口联系 Cubegin。设备 ID 可用于查找 Sentry 记录。

<!-- English -->

# Cubegin Privacy Policy

## Results and settings

Cubegin stores solve times, groups, and scrambles on your device. DCTimer results imported from a file are stored on your device as well. Timer and display settings can sync through your iCloud account. Builds with iCloud results sync can also sync results and groups. Diagnostic reports and usage analytics exclude solve details, scramble contents, and the contents of imported files.

## Optional diagnostics and usage data

If you choose **Agree**, Cubegin uses two services to fix issues and understand how features are used:

**Google Analytics for Firebase** receives categorized failures, the app build number, and timings for making the timer available at launch, preparing scrambles, and displaying scramble diagrams. Scramble preparation records include the current puzzle event, whether the event changed, and whether a prefetched scramble was ready. It also records basic statistics such as first opens, app versions, sessions, time in the foreground, and device information. When a version includes feature usage events, those events measure which features people use.

The statistics page records the time it takes for rolling averages to become available and the range of solve counts in the group. Versions with iCloud results sync also record the duration and outcome of sync attempts, the network type, and ranges for record counts. These records distinguish initial sync from later syncs.

**Sentry** receives crash reports and certain nonfatal errors for troubleshooting. These reports may include stack traces, OS and app versions, device models, and error categories.

Cubegin generates a random device ID for each installation so it can look up Sentry diagnostics. To copy it for support, tap **Version** five times under **Settings → About**. When iCloud sync is enabled and you agree to share data, Cubegin reads or creates a separate random user ID in its private iCloud database. Google Analytics for Firebase uses this ID to measure usage across devices. Apple Account information is used for iCloud sync. Cubegin uses diagnostics and usage data to improve the app.

See [how Google uses data from partner apps](https://policies.google.com/technologies/partner-sites) and the [Sentry privacy policy](https://sentry.io/privacy/).

## Manage sharing and contact us

When you send feedback through **Feedback & Reviews**, Cloudflare delivers your message, any email address you provide, and the screenshots you attach to Cubegin support. Web feedback is labeled with its source. App feedback also includes your device model, system and app versions, installation ID, and the currently bound user ID if available. We use this information to handle your feedback and contact you if you provide an email address. The iOS app remembers the email from your last successful submission on your device. The web form remembers it in your current browser. Tap the clear button next to the email field to remove the saved address. You can send feedback even when diagnostics and usage sharing is off.

You can change your choice under **Settings → About → Privacy → Help improve Cubegin**. Turning it off stops Cubegin from sending new diagnostics and usage data. Each service retains previously sent records according to its retention settings. For privacy questions or to request deletion of data already sent, contact Cubegin using **App Support** on the App Store listing. Your device ID can help locate Sentry records.
