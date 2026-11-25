# Cubegin for iPhone and iPad

[![English](https://img.shields.io/badge/English-blue)](README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](README_ZH.md)

Cubegin is a native SwiftUI speedcubing timer for iOS and iPadOS 26 or later. It supports system light and dark appearance and adapts to portrait, landscape and resizable iPad windows.

## Features

- **Timing and training** — Time solves with touch or a hardware keyboard. Choose from 16 standard events and 94 training types, and see each scramble with its diagram.
- **Timer display and manual entry** — In **Settings → Timer**, choose real time, whole seconds, or observation only. Finished results still show milliseconds. Choose manual entry to tap the timer page and enter a result, with optional +2 or DNF.
- **Swipe shortcuts** — While the timer is idle, swipe left to generate a new scramble or swipe right to confirm deletion of the latest result in the current group. In **Settings → Timer → Gestures**, you can reassign either direction to another action, manual entry, or None.
- **Formula hints** — Tap ✨ on the timer to choose a solution method for the current puzzle. Each event and solve group remembers its last method and the order of alternative solutions. Training hints are available for Easy Cross, Easy XCross and F2L.
- **Record celebrations** — Celebrate the first valid result and new single, Ao5, and Ao12 personal bests in the current solve group. Tap the celebration button next to the solve controls to replay while the result still qualifies.
- **Results and statistics** — Organize solves into groups, apply +2 or DNF, and review individual attempts, rolling averages, trend charts and time distributions.
- **Settings** — Choose the app language and theme, adjust the timer start delay, and turn timer haptics on or off.
- **DCTimer import** — Open **Settings → Import → Import from DCTimer**. In the file picker, tap Browse and go back to Locations. Open DCTimer² under On My iPhone or On My iPad, then select `spdcube.sqlite`. Preview the results, select the groups to import, and undo the latest import if needed.

In **Settings → About**, read the [changelog](CHANGELOG.md) offline or check for App Store updates.

[Development guide](DEVELOPMENT.md) · [GPL-3.0-only](LICENSE)

Optional WCA inspection includes 8- and 12-second voice calls and automatic inspection penalties. Release to enter inspection or start the solve without waiting for the configured hold delay.

On a partially folded iPhone Duo in portrait, read the scramble and time above the fold and use the lower half to start or stop the timer.

Use Settings → General → Sync to sync results, groups, and supported settings across devices signed into the same iCloud account. Supported settings include the selected puzzle event and formula hint preferences. The Sync screen shows upload progress for pending changes and the last successful sync time.

To copy the device ID and the shared user ID when available, tap **Version** five times under **Settings → About**. Choose whether to share diagnostics and usage data on first launch. Change your choice or open the [privacy policy](../../docs/privacy-policy.md#cubegin-privacy-policy) under **Settings → About → Privacy**.

Open **Settings → About → Feedback & Reviews** to send feedback from the app. You can include an email address and up to three screenshots. Tap **Review on the App Store** to leave a rating or review.
