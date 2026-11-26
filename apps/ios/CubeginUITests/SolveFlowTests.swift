import CoreGraphics
import SQLite3
import XCTest

final class SolveFlowTests: XCTestCase {
    @MainActor
    func testFirstTabLoadingRevealsContentAndSubsequentVisitsReuseIt() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchEnvironment["CUBEGIN_UI_TEST_SHOW_TAB_LOADING"] = "1"
        app.launchArguments = ["-app.language", "en", "-scramble.standard", "333",
                               "-timer.entryMethod", "timer", "-timer.wcaInspection", "NO", "-timer.startDelayTenths", "2"]
        app.launch()

        let elements = app.descendants(matching: .any)
        let timer = elements["timer.readout"].firstMatch
        XCTAssertTrue(elements["timer.scramble"].firstMatch.waitForExistence(timeout: 20))
        let touch = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        touch.press(forDuration: 0.45)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        touch.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))

        let settings = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "side-nav.settings", "Settings"
        )).firstMatch
        let results = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "side-nav.results", "Results"
        )).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["settings.title"].firstMatch.exists)
        XCTAssertTrue(elements["settings.loading"].firstMatch.exists)
        captureScreen("Settings loading")
        let theme = elements["settings.theme"].firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertFalse(elements["settings.loading"].firstMatch.exists)

        results.tap()
        XCTAssertTrue(app.buttons["Group"].firstMatch.exists)
        XCTAssertTrue(elements["results.loading"].firstMatch.exists)
        captureScreen("Results loading")
        let newest = elements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "solve-row-")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertFalse(elements["results.loading"].firstMatch.exists)

        settings.tap()
        XCTAssertTrue(theme.exists)
        XCTAssertFalse(elements["settings.loading"].firstMatch.exists)
        results.tap()
        XCTAssertTrue(newest.exists)
        XCTAssertFalse(elements["results.loading"].firstMatch.exists)
    }

    @MainActor
    func testFeedbackOpensNativeFormWithOptionalEmail() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_KEEP_FEEDBACK_NOTICE"] = "1"
        app.launchArguments = ["-app.language", "en", "-feedback.replyEmail", "cached@example.com"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let feedback = app.buttons["settings.about.feedback"]
        for _ in 0..<4 where !feedback.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(feedback.isHittable)
        feedback.tap()

        XCTAssertTrue(app.navigationBars["Feedback & Reviews"].waitForExistence(timeout: 5))
        let screenshots = app.buttons["settings.feedback.screenshots"]
        let send = app.buttons["settings.feedback.send"]
        let message = app.descendants(matching: .any)["settings.feedback.message"].firstMatch
        let email = app.textFields["settings.feedback.email"]
        let count = app.staticTexts["settings.feedback.characterCount"]
        XCTAssertEqual(email.value as? String, "cached@example.com")
        XCTAssertEqual(count.label, "0 of 200 characters")
        XCTAssertTrue(screenshots.exists)
        XCTAssertEqual(screenshots.frame.width, screenshots.frame.height, accuracy: 1)
        XCTAssertEqual(screenshots.frame.minX, message.frame.minX, accuracy: 2)
        XCTAssertEqual(screenshots.frame.maxY, count.frame.maxY, accuracy: 2)
        XCTAssertGreaterThan(count.frame.minX, screenshots.frame.maxX)
        XCTAssertGreaterThan(screenshots.frame.midY, message.frame.midY)
        XCTAssertLessThan(screenshots.frame.midY, email.frame.midY)
        XCTAssertEqual(email.frame.minX, message.frame.minX, accuracy: 2)
        let validation = app.descendants(matching: .any).matching(identifier: "settings.feedback.validation").firstMatch
        send.tap()
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Enter your feedback first."].exists)

        message.tap()
        message.typeText("A suggestion")
        XCTAssertFalse(validation.exists)
        XCTAssertEqual(count.label, "12 of 200 characters")
        XCTAssertFalse(app.buttons["settings.feedback.clearMessage"].exists)
        message.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(count.label, "11 of 200 characters")

        app.buttons["settings.feedback.clearEmail"].tap()
        XCTAssertEqual(email.value as? String, "Email (optional)")
        email.tap()
        email.typeText("invalid-email")
        for _ in 0..<2 where !send.isHittable { app.swipeUp() }
        send.tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 10))
    }

    @MainActor
    func testAboutShowsChangelogAndAppStoreUpdate() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["-app.language", "zh-Hans", "-cubegin-preview-app-update"]
        app.launch()

        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let changelog = app.buttons["settings.about.changelog"]
        for _ in 0..<4 where !changelog.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(changelog.isHittable)
        changelog.tap()
        let navigation = app.navigationBars["更新记录"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let back = navigation.buttons.firstMatch
        XCTAssertTrue(back.exists)
        let version = app.staticTexts["1.0.0"]
        XCTAssertTrue(version.exists)
        XCTAssertEqual(version.frame.minX, back.frame.minX, accuracy: 1)
        XCTAssertTrue(app.staticTexts["支持触屏和实体键盘计时，可开启 WCA 观察并自定义轻扫手势。"].exists)
        let changelogScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        changelogScreenshot.name = "Changelog content insets"
        changelogScreenshot.lifetime = .keepAlways
        add(changelogScreenshot)
        back.tap()

        app.buttons["settings.about.checkForUpdates"].tap()
        let alert = app.alerts["Cubegin 1.1.0 已发布"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Improved timer gestures")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["前往 App Store"].exists)
        alert.buttons["稍后"].tap()
        XCTAssertTrue(changelog.isHittable)
    }

    @MainActor
    func testVersionCopiesHiddenDeviceIDOnFifthTap() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        // The hosted runner can spend most of the normal toast lifetime taking AX snapshots.
        app.launchEnvironment["CUBEGIN_UI_TEST_EXTENDED_DEVICE_ID_TOAST"] = "1"
        app.launchArguments = ["-app.language", "en"]

        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let version = app.buttons["settings.about.version"]
        let privacy = app.buttons["settings.about.privacy"]
        for _ in 0..<4 where !privacy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(version.isHittable)
        let feedback = app.buttons["settings.about.feedback"]
        let checkForUpdates = app.buttons["settings.about.checkForUpdates"]
        let changelog = app.buttons["settings.about.changelog"]
        let importResults = app.buttons["settings.results.import"]
        let clearResults = app.buttons["settings.results.clear"]
        let includeDNF = app.switches["settings.results.includeDNFInWorst"]
        XCTAssertTrue(checkForUpdates.exists && changelog.exists && privacy.exists && feedback.exists)
        XCTAssertTrue(importResults.exists && clearResults.exists && includeDNF.exists)
        XCTAssertLessThan(checkForUpdates.frame.midY, version.frame.midY)
        XCTAssertLessThan(version.frame.midY, changelog.frame.midY)
        XCTAssertLessThan(changelog.frame.midY, privacy.frame.midY)
        XCTAssertLessThan(privacy.frame.midY, feedback.frame.midY)
        XCTAssertLessThan(importResults.frame.midY, clearResults.frame.midY)
        XCTAssertLessThan(clearResults.frame.midY, includeDNF.frame.midY)
        XCTAssertFalse(app.descendants(matching: .any)["settings.deviceID"].exists)
        let copied = app.descendants(matching: .any)["settings.deviceID.copied"].firstMatch
        for _ in 0..<4 { version.tap() }
        XCTAssertFalse(copied.exists)
        version.tap()
        XCTAssertTrue(copied.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCelebrationReplaysOnlyWhileTheLatestSolveQualifies() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        // On hosted simulators, accessibility snapshots can outlast the normal toast.
        app.launchEnvironment["CUBEGIN_UI_TEST_EXTENDED_CELEBRATION"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.entryMethod", "timer", "-timer.startDelayTenths", "0", "-timer.wcaInspection", "NO"]
        app.launch()

        let replay = app.buttons["timer.celebration-replay"]
        let hints = app.buttons["timer.formula-hints"]
        let readout = app.descendants(matching: .any)["timer.readout"]
        let toast = app.descendants(matching: .any)["timer.celebration-toast.first"]
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 20))
        XCTAssertTrue(readout.exists)
        XCTAssertFalse(app.buttons["timer.confetti-preview"].exists)
        XCTAssertFalse(replay.exists)
        XCTAssertFalse(toast.exists)

        let foldedPrompt = app.staticTexts["timer.folded-prompt"]
        let target = (foldedPrompt.exists ? foldedPrompt : readout)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        target.tap()
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        target.tap()
        XCTAssertTrue(toast.wait(for: \.label, toEqual: "First result", timeout: 2))
        let toastFrame = toast.frame
        captureScreen("First result toast")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 12))
        XCTAssertEqual(toastFrame.midX, readout.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(toastFrame.minY, readout.frame.maxY)
        let delete = app.buttons["Delete this solve"]
        XCTAssertTrue(replay.exists)
        XCTAssertGreaterThan(replay.frame.midX, delete.frame.midX)
        XCTAssertEqual(replay.frame.midY, delete.frame.midY, accuracy: 2)
        captureScreen("Post-solve controls")

        let dnf = app.buttons["timer.penalty.dnf"]
        dnf.tap()
        XCTAssertTrue(replay.waitForNonExistence(timeout: 3))
        dnf.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        XCTAssertFalse(toast.waitForExistence(timeout: 2))
        replay.tap()
        XCTAssertTrue(toast.wait(for: \.label, toEqual: "First result", timeout: 2))
        delete.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(replay.waitForNonExistence(timeout: 3))
        XCTAssertTrue(toast.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testPersonalBestToastsStackAtTheBottom() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        // On hosted simulators, accessibility snapshots can outlast the normal toast.
        app.launchEnvironment["CUBEGIN_UI_TEST_EXTENDED_CELEBRATION"] = "1"
        app.launchEnvironment["CUBEGIN_UI_TEST_CELEBRATION_HISTORY"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.entryMethod", "timer", "-timer.startDelayTenths", "0", "-timer.wcaInspection", "NO"]
        app.launch()

        let elements = app.descendants(matching: .any)
        let readout = elements["timer.readout"]
        let scramble = elements["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        XCTAssertTrue(readout.exists)
        let foldedPrompt = app.staticTexts["timer.folded-prompt"]
        let target = (foldedPrompt.exists ? foldedPrompt : readout)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        target.tap()
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        target.tap()

        let single = elements["timer.celebration-toast.single"]
        let ao5 = elements["timer.celebration-toast.ao5"]
        let ao12 = elements["timer.celebration-toast.ao12"]
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        let singleFrame = single.frame
        let ao5Frame = ao5.frame
        let ao12Frame = ao12.frame
        XCTAssertFalse(ao12Frame.isEmpty)
        XCTAssertGreaterThanOrEqual(ao5Frame.minY - singleFrame.maxY, 6)
        XCTAssertGreaterThanOrEqual(ao12Frame.minY - ao5Frame.maxY, 6)
        XCTAssertEqual(singleFrame.midX, ao5Frame.midX, accuracy: 1)
        XCTAssertEqual(ao5Frame.midX, ao12Frame.midX, accuracy: 1)
        let readoutCenterY = readout.frame.midY
        if foldedPrompt.exists {
            let replayFrame = app.buttons["timer.celebration-replay"].frame
            XCTAssertTrue(singleFrame.minY > replayFrame.maxY || singleFrame.minX > replayFrame.maxX)
            XCTAssertLessThan(ao12Frame.maxY, app.frame.midY)
        } else {
            XCTAssertGreaterThan(singleFrame.minY, readout.frame.maxY)
            XCTAssertGreaterThan(ao12Frame.midY, app.frame.minY + app.frame.height * 2 / 3)
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.frame.minY > app.frame.midY {
            XCTAssertLessThan(ao12Frame.maxY, tabBar.frame.minY)
            if !foldedPrompt.exists {
                XCTAssertLessThan(tabBar.frame.minY - ao12Frame.maxY, 32)
            }
        }
        XCTAssertTrue(ao12.waitForNonExistence(timeout: 12))
        XCTAssertEqual(readout.frame.midY, readoutCenterY, accuracy: 2)
        XCTAssertTrue(app.buttons["timer.celebration-replay"].exists)
        captureScreen("Record scores after the toast fades")
    }

    @MainActor
    func testTimerHeaderButtonsRespondAtTheirInnerEdges() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["-app.language", "en", "-scramble.mode", "standard", "-scramble.standard", "333"]
        app.launch()

        let project = app.buttons["Event"]
        let hints = app.buttons["timer.formula-hints"]
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 20))
        XCTAssertTrue(project.isHittable)
        XCTAssertGreaterThanOrEqual(project.frame.width, 64)
        XCTAssertGreaterThanOrEqual(hints.frame.width, 64)
        XCTAssertEqual(project.frame.midY, hints.frame.midY, accuracy: 1)

        project.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let threeByThree = app.buttons["event.choice.333"]
        XCTAssertTrue(threeByThree.waitForExistence(timeout: 5))
        threeByThree.tap()

        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 20))
        hints.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testFormulaHintsShowSolutionsForCurrentScramble() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()

        let hints = app.buttons["timer.formula-hints"]
        XCTAssertTrue(hints.waitForExistence(timeout: 20))
        XCTAssertTrue(hints.wait(for: \.isEnabled, toEqual: true, timeout: 20))
        hints.tap()

        let sheet = app.navigationBars["Formula hints"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let method = app.buttons["assist.method"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["Two-Phase Full Solve"].exists)
        XCTAssertFalse(app.buttons["Goal Presets"].exists)
        app.buttons["Cross"].tap()
        XCTAssertTrue(app.staticTexts["Cross(D)"].waitForExistence(timeout: 20))
        method.tap()
        app.buttons["XCross"].tap()
        XCTAssertTrue(app.staticTexts["XCross(D)"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Cross(D)"].exists)

        let down = app.staticTexts["XCross(D)"]
        let up = app.staticTexts["XCross(U)"]
        XCTAssertTrue(up.exists)
        let upRow = app.cells.containing(.staticText, identifier: "XCross(U)").firstMatch
        XCTAssertTrue(upRow.staticTexts.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "z2", "z2 "))
            .firstMatch.exists)
        let startsWithDown = down.frame.minY < up.frame.minY
        let firstLabel = startsWithDown ? "XCross(D)" : "XCross(U)"
        let firstCell = app.cells.containing(.staticText, identifier: firstLabel).firstMatch
        XCTAssertTrue(firstCell.exists)
        let secondText = startsWithDown ? up : down
        let handle = firstCell.descendants(matching: .any)[startsWithDown ? "assist.reorder.D" : "assist.reorder.U"]
        XCTAssertTrue(handle.exists)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let drop = start.withOffset(CGVector(dx: 0, dy: secondText.frame.midY - firstCell.frame.minY))
        start.press(forDuration: 0.4, thenDragTo: drop, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertNotEqual(down.frame.minY < up.frame.minY, startsWithDown)

        sheet.buttons["Done"].tap()
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertFalse(sheet.exists)
        hints.tap()
        XCTAssertTrue(down.waitForExistence(timeout: 20))
        XCTAssertTrue(up.exists)
        XCTAssertNotEqual(down.frame.minY < up.frame.minY, startsWithDown)
    }

    @MainActor
    func testTrainingShowsHintsOnlyForSupportedStages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString

        for (event, expected) in [("333.easy_xcross", "XCross(D)"), ("333.pll", nil)] {
            app.launchArguments = ["-app.language", "en", "-scramble.standard", "333", "-scramble.training", event]
            app.launch()

            let project = app.buttons["Event"]
            XCTAssertTrue(project.waitForExistence(timeout: 20))
            XCTAssertTrue(project.wait(for: \.isEnabled, toEqual: true, timeout: 20))
            project.tap()
            let training = app.buttons["event.mode.training"]
            XCTAssertTrue(training.waitForExistence(timeout: 5))
            if event == "333.easy_xcross" { captureScreen("Standard projects") }
            training.tap()
            XCTAssertTrue(training.isSelected)
            if event == "333.easy_xcross" { captureScreen("Training projects") }
            let group = app.buttons["3x3x3 CFOP"]
            XCTAssertTrue(group.waitForExistence(timeout: 5))
            group.tap()
            let projectName = event == "333.easy_xcross" ? "easy xcross" : "PLL"
            let row = app.buttons["event.choice.\(event)"]
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: group.frame.midX - app.frame.minX,
                                                    dy: group.frame.midY - app.frame.minY + 120))
            let end = start.withOffset(CGVector(dx: 0, dy: -185))
            for _ in 0..<8 where !row.isHittable {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            XCTAssertTrue(row.isHittable)
            row.tap()
            XCTAssertEqual(project.value as? String, "3x3x3 CFOP · \(projectName)")

            let hints = app.buttons["timer.formula-hints"]
            if let expected {
                XCTAssertTrue(hints.wait(for: \.isEnabled, toEqual: true, timeout: 20))
                hints.tap()
                XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 20))
                XCTAssertFalse(app.staticTexts["XCross(U)"].exists)
            } else {
                XCTAssertFalse(hints.exists)
            }
        }
    }

    @MainActor
    private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLanguageCanReturnToFollowingTheSystem() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()

        let settings = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "设置"])).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let language = app.buttons["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        let chinese = app.buttons["简体中文"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 5))
        chinese.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))

        language.tap()
        let system = app.buttons["跟随系统"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        system.tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testResultsSyncShowsRetryAfterAnOptInError() {
        continueAfterFailure = false
        let app = openSyncPreview("--preview-icloud-error")
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertEqual(toggle.label, "iCloud 同步")
        tapSyncToggle(toggle)
        let error = app.staticTexts["settings.sync.cloudSyncError"]
        let retry = app.buttons["settings.sync.refresh"]
        let syncing = app.staticTexts["settings.sync.inProgress"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.exists)
        XCTAssertLessThan(error.frame.maxX, retry.frame.minX)
        XCTAssertEqual(error.frame.midY, retry.frame.midY, accuracy: 2)
        // The switch's accessibility frame covers the card. Its control is inset by the card row padding.
        XCTAssertEqual(retry.frame.maxX, toggle.frame.maxX - 24, accuracy: 1)
        captureScreen("Settings — iCloud sync error")
        retry.tap()
        XCTAssertTrue(syncing.waitForExistence(timeout: 3))
        XCTAssertFalse(retry.exists)
        captureScreen("Settings — iCloud syncing")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)
        XCTAssertFalse(error.exists)
    }

    @MainActor
    func testResultsSyncShowsTheLastSuccessfulTimeAndCanRefresh() {
        continueAfterFailure = false
        let app = openSyncPreview("--preview-icloud-success")
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)

        let lastSync = app.staticTexts["settings.sync.lastCloudSync"]
        let refresh = app.buttons["settings.sync.refresh"]
        XCTAssertTrue(lastSync.waitForExistence(timeout: 5))
        XCTAssertTrue(lastSync.label.hasPrefix("上次同步："))
        XCTAssertLessThan(lastSync.frame.maxX, refresh.frame.minX)
        captureScreen("Settings — iCloud sync success")
        refresh.tap()
        XCTAssertTrue(app.staticTexts["settings.sync.inProgress"].waitForExistence(timeout: 3))
        XCTAssertFalse(refresh.exists)
        XCTAssertTrue(lastSync.waitForExistence(timeout: 5))
    }

    @MainActor
    func testBackgroundSyncFillsAnEmptyResultsListWithoutSwitchingAway() {
        continueAfterFailure = false
        let app = openSyncPreview("--preview-icloud-late-results", language: "en",
                                  arguments: ["-scramble.mode", "standard", "-scramble.standard", "333"])
        let results = app.tabBars.buttons["Results"]
        let settings = app.tabBars.buttons["Settings"]
        let empty = app.staticTexts["No results yet"]
        results.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 5))

        settings.tap()
        let sync = app.buttons["settings.general.sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        tapCardRowEdge(sync)
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)

        results.tap()
        let solve = app.buttons["solve-row-1"]
        XCTAssertTrue(solve.waitForExistence(timeout: 15))
        XCTAssertTrue(solve.label.contains("12.345"))
        XCTAssertFalse(empty.exists)
    }

    @MainActor
    func testCloudSyncKeepsExistingResultRowsUntilTheUserRefreshes() {
        continueAfterFailure = false
        let app = openSyncPreview("--preview-icloud-late-results", language: "en",
                                  arguments: ["-scramble.mode", "standard", "-scramble.standard", "333"],
                                  environment: ["CUBEGIN_UI_TEST_LONG_SOLVE": "1"])
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)

        app.tabBars.buttons["Results"].tap()
        let existingSolve = app.buttons["solve-row-12"]
        let cloudSolve = app.buttons["solve-row-13"]
        XCTAssertTrue(existingSolve.waitForExistence(timeout: 5))
        let refresh = app.buttons["results.refreshCloudResults"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        XCTAssertTrue(existingSolve.exists)
        XCTAssertFalse(cloudSolve.exists)
        captureScreen("Results — iCloud update notice")

        refresh.tap()
        XCTAssertTrue(cloudSolve.waitForExistence(timeout: 5))
        XCTAssertTrue(cloudSolve.label.contains("12.345"))
        XCTAssertFalse(refresh.exists)
    }

    @MainActor
    func testResultsSyncShowsUploadProgress() {
        continueAfterFailure = false
        let app = openSyncPreview("--preview-icloud-upload", environment: ["CUBEGIN_UI_TEST_LONG_SOLVE": "1"])
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)

        let uploading = app.staticTexts["settings.sync.uploading"]
        let progress = app.staticTexts["settings.sync.uploadProgress"]
        XCTAssertTrue(uploading.waitForExistence(timeout: 8))
        XCTAssertEqual(uploading.label, "正在上传到 iCloud…")
        XCTAssertTrue(progress.exists)
        XCTAssertNotNil(progress.label.range(of: #"^\d+/\d+$"#, options: .regularExpression))
        XCTAssertGreaterThan(progress.frame.minX, uploading.frame.maxX)
        XCTAssertEqual(progress.frame.midY, uploading.frame.midY, accuracy: 2)
        XCTAssertFalse(app.buttons["settings.sync.refresh"].exists)
        captureScreen("Settings — iCloud upload progress")

        tapSyncToggle(toggle)
        XCTAssertTrue(uploading.waitForNonExistence(timeout: 5))
        XCTAssertFalse(progress.exists)
    }

    @MainActor
    func testResultsSyncKeepsRefreshAtTheTopOfAMultilineError() {
        continueAfterFailure = false
        let normal = openSyncPreview("--preview-icloud-account-error", language: "en")
        let normalToggle = normal.switches["settings.sync.icloudSync"]
        XCTAssertTrue(normalToggle.waitForExistence(timeout: 5))
        tapSyncToggle(normalToggle)
        let normalError = normal.staticTexts["settings.sync.cloudSyncError"]
        XCTAssertTrue(normalError.waitForExistence(timeout: 5))
        let normalToggleHeight = normalToggle.frame.height
        let normalErrorHeight = normalError.frame.height
        normal.terminate()

        let app = openSyncPreview("--preview-icloud-account-error", language: "en", largeText: true)
        let toggle = app.switches["settings.sync.icloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapSyncToggle(toggle)
        let error = app.staticTexts["settings.sync.cloudSyncError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let refresh = app.buttons["settings.sync.refresh"]
        XCTAssertEqual(toggle.frame.height, normalToggleHeight, accuracy: 1)
        XCTAssertEqual(error.frame.height, normalErrorHeight, accuracy: 1)
        XCTAssertGreaterThan(error.frame.height, 20)
        XCTAssertEqual(refresh.frame.midY, error.frame.minY + 8, accuracy: 2)
        captureScreen("Settings — iCloud multiline error")
    }

    @MainActor
    private func tapSyncToggle(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        if toggle.frame.width < 100 {
            toggle.tap()
        } else {
            // Some runtimes expose the entire card as the switch's accessibility frame.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -48, dy: 0)).tap()
            if (toggle.value as? String) == before { toggle.tap() }
        }
        XCTAssertNotEqual(toggle.value as? String, before)
    }

    @MainActor
    private func openSyncPreview(_ preview: String, language: String = "zh-Hans", largeText: Bool = false,
                                 arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = environment
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", language, preview, "-app.icloudSync", "NO"]
        app.launchArguments += arguments
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let settings = app.tabBars.buttons[language == "en" ? "Settings" : "设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let sync = app.buttons["settings.general.sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        tapCardRowEdge(sync)
        XCTAssertTrue(app.navigationBars[language == "en" ? "Sync" : "同步"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testDCTimerImportOpensFilesAndCanBeCancelled() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let imports = app.descendants(matching: .any)["settings.results.import"].firstMatch
        XCTAssertTrue(imports.waitForExistence(timeout: 5))
        tapCardRowEdge(imports)
        XCTAssertTrue(app.navigationBars["Import"].waitForExistence(timeout: 5))
        let entry = app.buttons["settings.results.importDCTimer"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let browseHelp = app.staticTexts["settings.import.dctimerBrowseHelp"]
        XCTAssertTrue(browseHelp.exists)
        XCTAssertTrue(browseHelp.label.contains("Browse") && browseHelp.label.contains("Locations"))
        XCTAssertLessThan(browseHelp.frame.maxY, entry.frame.minY)
        let backupPath = app.staticTexts["settings.import.dctimerBackupPath"]
        XCTAssertTrue(backupPath.label.contains("DCTimer²") && backupPath.label.contains("spdcube.sqlite"))
        tapCardRowEdge(entry)
        let cancel = app.buttons["Cancel"].firstMatch
        // Cold Files launches can exceed 10 seconds on hosted simulators.
        guard cancel.waitForExistence(timeout: 45) else {
            XCTFail("The system file picker did not show its Cancel button")
            return
        }
        cancel.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDCTimerImportPreviewsAppendsAndCanBeUndoneAfterRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_DCTIMER_BACKUP"] = try dctimerFixture()
        app.launchArguments += ["-app.language", "en"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let imports = app.descendants(matching: .any)["settings.results.import"].firstMatch
        XCTAssertTrue(imports.waitForExistence(timeout: 5))
        imports.tap()
        let entry = app.buttons["settings.results.importDCTimer"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let confirm = app.buttons["dctimer.confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2-7"].exists)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Imported 1 result."].waitForExistence(timeout: 5))

        entry.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["dctimer.preview.duplicates"].firstMatch.exists)
        app.terminate()
        app.launch()

        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        XCTAssertTrue(imports.waitForExistence(timeout: 5))
        imports.tap()
        let undo = app.buttons["settings.import.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        let alert = app.alerts["Undo last import?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["This will remove 1 result from the last import."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["settings.import.confirmUndo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed 1 result."].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)

        entry.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.isEnabled)
    }

    @MainActor
    func testPrivacySharingSwitchIsVisibleOnSimulatorByDefault() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["-app.language", "zh-Hans"]
        app.launch()

        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let privacy = app.buttons["settings.about.privacy"]
        XCTAssertFalse(app.alerts["帮助改进 Cubegin"].exists)
        for _ in 0..<4 where !privacy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(privacy.isHittable)
        privacy.tap()
        let sharing = app.switches["settings.telemetry.sharing"]
        XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertEqual(sharing.value as? String, "0")
    }

    @MainActor
    func testFirstLaunchSharingChoiceAndPrivacySettings() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "zh-Hans", "-cubegin-show-telemetry-consent"]
        app.launch()

        let prompt = app.alerts["帮助改进 Cubegin"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 20))
        XCTAssertTrue(prompt.buttons["同意"].exists)
        prompt.buttons["暂不共享"].tap()
        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        XCTAssertFalse(prompt.exists)
        settings.tap()
        let privacy = app.buttons["settings.about.privacy"]
        for _ in 0..<4 where !privacy.isHittable {
            app.swipeUp()
        }
        privacy.tap()
        XCTAssertTrue(app.navigationBars["隐私"].waitForExistence(timeout: 5))
        let sharing = app.switches["settings.telemetry.sharing"]
        XCTAssertEqual(sharing.value as? String, "0")
        let policyText = app.descendants(matching: .any)["settings.privacyPolicy"].firstMatch
        XCTAssertTrue(policyText.label.contains("开启后会发送崩溃报告"))
        XCTAssertTrue(policyText.label.contains("查看隐私政策"))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Privacy settings (zh-Hans)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let sharingControl = sharing.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
        sharingControl.tap()
        XCTAssertEqual(sharing.value as? String, "1")
        sharingControl.tap()
        XCTAssertEqual(sharing.value as? String, "0")

        let privacyPolicy = app.links["查看隐私政策"].firstMatch
        if privacyPolicy.isHittable {
            privacyPolicy.tap()
        } else {
            policyText.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.76)).tap()
        }
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["成绩和设置"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(sharing.exists)
    }

    @MainActor
    func testClearingResultsRequiresCountdownAndResetsSettingsNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_DCTIMER_BACKUP"] = try dctimerFixture(includeSecondGroup: true)
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.descendants(matching: .any)["settings.results.import"].firstMatch.tap()
        app.buttons["settings.results.importDCTimer"].tap()
        let confirmImport = app.buttons["dctimer.confirmImport"]
        XCTAssertTrue(confirmImport.waitForExistence(timeout: 10))
        confirmImport.tap()
        XCTAssertTrue(app.staticTexts["Imported 3 results."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.import.lastImportDetails"].exists)

        app.tabBars.buttons["Results"].tap()
        settings.tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        let clearPage = app.descendants(matching: .any)["settings.results.clear"].firstMatch
        app.swipeUp()
        tapCardRowEdge(clearPage)
        let clearAll = app.buttons["settings.results.clearAll"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()

        let confirm = app.buttons["settings.results.confirmClearAll"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["Clear all results?"].exists)
        XCTAssertTrue(app.staticTexts["This will permanently delete 3 results."].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(clearAll.isEnabled)

        let group = app.buttons["settings.clear.group.dctimer:333:1:Practice"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        tapCardRowEdge(group)
        XCTAssertFalse(clearAll.exists)
        app.buttons["settings.results.clearSelected"].tap()
        XCTAssertTrue(app.staticTexts["This will permanently delete 1 result."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clear selected groups?"].exists)
        XCTAssertTrue(confirm.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Deleted 1 result."].waitForExistence(timeout: 5))
        XCTAssertTrue(clearAll.isEnabled)
        XCTAssertTrue(app.buttons["settings.clear.group.dctimer:222:3:Keep"].exists)
        XCTAssertFalse(group.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.swipeUp()
        XCTAssertTrue(clearPage.waitForExistence(timeout: 5))
        tapCardRowEdge(clearPage)
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        XCTAssertTrue(clearAll.isEnabled)
        XCTAssertTrue(app.buttons["settings.clear.group.dctimer:222:3:Keep"].exists)
        XCTAssertFalse(group.exists)
    }

    @MainActor
    func testDCTimerImportCanSkipGroups() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_DCTIMER_BACKUP"] = try dctimerFixture(includeSecondGroup: true)
        app.launchArguments += ["-app.language", "en"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.descendants(matching: .any)["settings.results.import"].firstMatch.tap()
        let entry = app.buttons["settings.results.importDCTimer"]
        entry.tap()
        let confirm = app.buttons["dctimer.confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))

        let groups = app.buttons
        let keep = groups["dctimer.preview.group.1"].firstMatch
        let skip = groups["dctimer.preview.group.3"].firstMatch
        if !skip.isHittable { app.swipeUp() }
        XCTAssertTrue(skip.isSelected)
        tapCardRowEdge(skip)
        keep.tap()
        XCTAssertFalse(confirm.isEnabled)
        keep.tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Imported 1 result."].waitForExistence(timeout: 5))

        entry.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Imported 2 results."].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapCardRowEdge(_ button: XCUIElement) {
        // Accessibility frames may be rounded to device pixels.
        XCTAssertGreaterThanOrEqual(button.frame.height, 47.5)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
    }

    private func dctimerFixture(includeSecondGroup: Bool = false) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        let openStatus = sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        guard openStatus == SQLITE_OK, sqlite3_exec(db, """
            CREATE TABLE sessiontb (rowid integer, name text);
            CREATE TABLE scrtypetb (sesid integer, type integer);
            CREATE TABLE resulttb (id integer, sesid integer, rest integer, resp integer, scr text, date text);
            INSERT INTO sessiontb VALUES (1, 'Practice'), (2, '2-7');
            INSERT INTO scrtypetb VALUES (1, -32), (2, 32);
            INSERT INTO resulttb VALUES
                (1, 1, 12000, 0, 'R U', '2024-02-02 11:12:10'),
                (2, 2, 12001, 0, 'U R', '2024-02-02 11:12:11');
            """, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
        if includeSecondGroup {
            guard sqlite3_exec(db, """
                INSERT INTO sessiontb VALUES (3, 'Keep');
                INSERT INTO scrtypetb VALUES (3, -29);
                INSERT INTO resulttb VALUES
                    (3, 3, 13000, 0, 'R U', '2024-02-02 11:12:12'),
                    (4, 3, 14000, 0, 'U R', '2024-02-02 11:12:13');
                """, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        }
        return try Data(contentsOf: url).base64EncodedString()
    }

    @MainActor
    func testStatisticsPublishesRollingAveragesWhenOpened() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.mode", "standard", "-scramble.standard", "333"]
        app.launch()

        let results = app.tabBars.buttons["Results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        XCTAssertTrue(app.buttons["solve-row-12"].waitForExistence(timeout: 5))
        app.buttons["results.view"].tap()
        app.buttons["Statistics"].tap()

        let average = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND value CONTAINS %@ AND NOT (value CONTAINS %@)", "ao12", "best ", "…"
        )).firstMatch
        XCTAssertTrue(average.waitForExistence(timeout: 10))
    }

    @MainActor
    func testPortraitSolveListKeepsPickersFixedWhileScrolling() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launchArguments += ["-timer.entryMethod", "timer"]
        app.launch()

        let event = app.buttons["Event"]
        XCTAssertTrue(event.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["timer.scramble"].waitForExistence(timeout: 10))
        recordPortraitPage("Home", frames: [event.frame])

        // The 12 seeded rows fit on a 17 Pro in portrait. Add a solve to make the list scroll.
        let timer = app.descendants(matching: .any)["timer.readout"]
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        center.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        let actions = app.buttons["timer.penalty.dnf"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        recordPortraitPage("Stopped timer", frames: [timer.frame, actions.frame])

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        let haptics = app.switches["settings.timer.haptics"]
        XCTAssertTrue(haptics.waitForExistence(timeout: 5))
        let originalHapticsValue = try XCTUnwrap(haptics.value as? String)
        let updatedHapticsValue = originalHapticsValue == "1" ? "0" : "1"
        let hapticsThumb = haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        hapticsThumb.tap()
        XCTAssertEqual(haptics.value as? String, updatedHapticsValue)
        hapticsThumb.tap()
        XCTAssertEqual(haptics.value as? String, originalHapticsValue)
        let worst = app.switches["settings.results.includeDNFInWorst"]
        XCTAssertTrue(worst.waitForExistence(timeout: 5))
        recordPortraitPage("Settings", frames: [worst.frame])

        app.tabBars.buttons["Results"].tap()
        let row = app.buttons["solve-row-13"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let group = app.buttons["Group"]
        let view = app.buttons["results.view"]
        let groupFrame = group.frame
        let viewFrame = view.frame
        let rowFrame = row.frame
        recordPortraitPage("Results before scroll", frames: [event.frame, groupFrame, viewFrame, rowFrame])

        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: rowFrame.midX, dy: rowFrame.midY + 45))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -88)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        recordPortraitPage("Results after scroll", frames: [group.frame, view.frame, row.frame])
        XCTAssertLessThan(row.frame.minY, groupFrame.maxY)
        XCTAssertEqual(group.frame, groupFrame)
        XCTAssertEqual(view.frame, viewFrame)
        view.tap()
        let statistics = app.buttons["Statistics"]
        XCTAssertTrue(statistics.waitForExistence(timeout: 5))
        statistics.tap()

        let metric = app.staticTexts["Valid / Total"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let statisticsGroupFrame = group.frame
        let statisticsViewFrame = view.frame
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -76)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(metric.exists)
        XCTAssertLessThan(metric.frame.minY, statisticsGroupFrame.maxY)
        XCTAssertEqual(group.frame, statisticsGroupFrame)
        XCTAssertEqual(view.frame, statisticsViewFrame)
        recordPortraitPage("Statistics after scroll", frames: [group.frame, view.frame, metric.frame])
    }

    @MainActor
    private func recordPortraitPage(_ page: String, frames: [CGRect]) {
        print("Portrait \(page): \(frames)")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Portrait \(page)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLandscapeResultsKeepPickersFixedWhileScrolling() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()

        let results = app.tabBars.buttons["Results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        let viewPicker = app.buttons["results.view"]
        XCTAssertTrue(viewPicker.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["side-nav.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(viewPicker.wait(for: \.isHittable, toEqual: true, timeout: 5))
        viewPicker.tap()
        app.buttons["Statistics"].tap()

        let groupPicker = app.buttons["Group"]
        let home = app.buttons["side-nav.home"]
        let metric = app.staticTexts["Valid / Total"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let groupFrame = groupPicker.frame
        let viewFrame = viewPicker.frame
        let homeFrame = home.frame
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        XCTAssertTrue(metric.exists)
        XCTAssertLessThan(metric.frame.minY, groupFrame.maxY)
        XCTAssertEqual(groupPicker.frame, groupFrame)
        XCTAssertEqual(viewPicker.frame, viewFrame)
        XCTAssertTrue(groupPicker.isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Landscape Overview Scroll Edge"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        groupPicker.tap()
        let defaultGroup = app.buttons["Default"]
        XCTAssertTrue(defaultGroup.waitForExistence(timeout: 5))
        defaultGroup.tap()

        let mode = app.segmentedControls["charts.mode"]
        let range = app.buttons["charts.range"]
        let averages = app.buttons["charts.average"]
        let settings = app.buttons["side-nav.settings"]
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
        // A full swipe can skip the controls in the short landscape viewport.
        for _ in 0..<8 {
            if mode.exists && mode.isHittable { break }
            scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd,
                              withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTAssertTrue(mode.isHittable)
        XCTAssertTrue(range.isHittable)
        XCTAssertTrue(averages.isHittable)
        XCTAssertEqual(home.frame, homeFrame)
        XCTAssertLessThan(mode.frame.maxX, settings.frame.minX)
        XCTAssertEqual(groupPicker.frame, groupFrame)
        XCTAssertEqual(viewPicker.frame, viewFrame)
        captureLandscapePage("Statistics chart controls", cutout: "left")

        mode.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Time distribution"].waitForExistence(timeout: 5))
        XCTAssertFalse(averages.exists)
        XCTAssertTrue(range.isHittable)

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(mode.wait(for: \.isHittable, toEqual: true, timeout: 5))
        mode.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["Solve trend"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThan(mode.frame.maxX, settings.frame.minX)
        captureLandscapePage("Statistics chart controls", cutout: "right")

        viewPicker.tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Results", "side-nav.results")).firstMatch.tap()
        let solveRow = app.buttons["solve-row-12"]
        XCTAssertTrue(solveRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(viewPicker.frame.maxX, settings.frame.minX)
        XCTAssertLessThan(solveRow.frame.maxX, settings.frame.minX)
        XCTAssertFalse(mode.exists)

        let listScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listScreenshot.name = "Landscape Results Right Cutout"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)
    }

    @MainActor
    func testDuoCoverTabsAlignWithUpperLeftCamera() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en"]
        app.launchEnvironment["CUBEGIN_UI_TEST_DUO_TAB_SIDE"] = "left"
        app.launch()
        try XCTSkipUnless(app.frame.width > app.frame.height && app.frame.width < 750,
                          "Run with the Duo cover display active in landscape.")

        let home = app.buttons["side-nav.home"]
        let results = app.buttons["side-nav.results"]
        let settings = app.buttons["side-nav.settings"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        let leftTabs = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            home.frame.midX < app.frame.midX
        }, object: home)
        XCTAssertEqual(XCTWaiter.wait(for: [leftTabs], timeout: 5), .completed)
        XCTAssertEqual(home.frame.midX - app.frame.minX, 48, accuracy: 3)
        let event = app.buttons["Event"]
        let timerHeader = event.frame
        XCTAssertGreaterThan(timerHeader.minX, home.frame.maxX)
        captureLandscapePage("Duo cover", cutout: "left")

        results.tap()
        let group = app.buttons["Group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(group.frame.minX, results.frame.maxX)
        let resultsHeader = event.frame
        settings.tap()
        let title = app.staticTexts["settings.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.minX, resultsHeader.minX, accuracy: 2)
        XCTAssertEqual(title.frame.midY, resultsHeader.midY, accuracy: 2)
        XCTAssertEqual(title.frame.midY, timerHeader.midY, accuracy: 2)
        captureLandscapePage("Duo settings header", cutout: "left")
        home.tap()
        XCTAssertTrue(app.buttons["Event"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDuoFoldedPortraitKeepsFormulaAndTimerAboveDiagram() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.wcaInspection", "NO", "-timer.startDelayTenths", "2"]
        app.launch()
        try XCTSkipUnless(app.frame.width > 550 && app.frame.width < app.frame.height,
                          "Run with the Duo inner display active in portrait.")

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 20))
        let event = app.buttons["Event"]
        let scramble = app.descendants(matching: .any)["timer.scramble"]
        let diagram = app.descendants(matching: .any)["timer.scramble-diagram"]
        let summary = app.descendants(matching: .any)["timer-summary.count"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        try XCTSkipUnless(timer.frame.midY < app.frame.minY + app.frame.height * 0.44,
                          "Run with the Duo partially unfolded.")
        XCTAssertTrue(diagram.exists)
        XCTAssertFalse(summary.exists)
        XCTAssertGreaterThan(event.frame.midY, app.frame.midY)
        XCTAssertLessThan(event.frame.maxY, diagram.frame.minY)
        XCTAssertLessThan(scramble.frame.maxY, timer.frame.minY)
        XCTAssertLessThan(timer.frame.maxY, app.frame.midY)
        XCTAssertGreaterThan(diagram.frame.minY, app.frame.midY)
        let prompt = app.staticTexts["timer.folded-prompt"]
        XCTAssertEqual(prompt.label, "Hold to start")
        XCTAssertLessThan(diagram.frame.maxY, prompt.frame.minY)
        XCTAssertGreaterThan(prompt.frame.midY, app.frame.minY + app.frame.height * 0.77)

        let touch = prompt.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let cancel = diagram.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        touch.press(forDuration: 0.5, thenDragTo: cancel, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(timer.label, "Start timer")
        XCTAssertEqual(prompt.label, "Hold to start")

        let idleReadout = timer.frame
        let idlePromptY = prompt.frame.midY
        touch.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        XCTAssertLessThan(timer.frame.midY, idleReadout.midY)
        XCTAssertEqual(timer.frame.midY, app.frame.minY + app.frame.height / 4, accuracy: 12)
        XCTAssertFalse(event.exists)
        XCTAssertFalse(scramble.exists)
        XCTAssertEqual(prompt.label, "Tap to stop")
        XCTAssertLessThan(prompt.frame.midY, idlePromptY)
        touch.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(diagram.exists)
        XCTAssertTrue(summary.exists)
        let plusTwo = app.buttons["timer.penalty.plusTwo"]
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(plusTwo.frame.minY, timer.frame.maxY)
        XCTAssertLessThan(plusTwo.frame.maxY, app.frame.midY)
        plusTwo.tap()
        XCTAssertTrue(plusTwo.isSelected)
        XCTAssertEqual(timer.label, "Start timer")
    }

    @MainActor
    func testDuoFoldedPortraitKeepsInspectionAndSolveReadoutsInPlace() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.wcaInspection", "YES", "-timer.startDelayTenths", "20"]
        app.launch()
        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 20))
        try XCTSkipUnless(app.frame.width > 550 && app.frame.width < app.frame.height
                          && timer.frame.midY < app.frame.minY + app.frame.height * 0.44,
                          "Run with the Duo partially unfolded in portrait.")

        let prompt = app.staticTexts["timer.folded-prompt"]
        XCTAssertTrue(prompt.wait(for: \.label, toEqual: "Tap to inspect", timeout: 5))
        let idlePromptY = prompt.frame.midY
        let touch = prompt.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        touch.tap()
        let inspection = app.descendants(matching: .any).matching(identifier: "timer.inspection").firstMatch
        XCTAssertTrue(inspection.waitForExistence(timeout: 5))
        let readoutY = inspection.frame.midY
        XCTAssertEqual(readoutY, app.frame.minY + app.frame.height / 4, accuracy: 12)
        XCTAssertEqual(prompt.label, "Press to start")
        XCTAssertLessThan(prompt.frame.midY, idlePromptY)

        let cancel = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        touch.press(forDuration: 0.4, thenDragTo: cancel, withVelocity: .fast, thenHoldForDuration: 0.1)
        XCTAssertTrue(inspection.exists)
        XCTAssertEqual(inspection.frame.midY, readoutY, accuracy: 1)
        XCTAssertEqual(prompt.label, "Press to start")

        touch.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        XCTAssertEqual(timer.frame.midY, readoutY, accuracy: 1)
        touch.tap()
        XCTAssertTrue(prompt.wait(for: \.label, toEqual: "Tap to inspect", timeout: 5))
    }

    @MainActor
    func testDuoInnerRightStatusColumnTabsAreUsable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchEnvironment["CUBEGIN_UI_TEST_UNRECOGNIZED_DUO"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()
        try XCTSkipUnless(app.frame.width >= 750 && app.frame.width > app.frame.height,
                          "Run with the Duo inner display active in landscape.")

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertLessThan(timer.frame.midX - app.frame.minX, app.frame.width * 0.58)

        let results = app.buttons["side-nav.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(results.frame.midX - app.frame.minX, app.frame.width * 0.9)
        XCTAssertTrue(results.isHittable)
        results.tap()
        XCTAssertTrue(app.buttons["solve-row-12"].waitForExistence(timeout: 5))
        app.buttons["side-nav.settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDuoCoverFormsLeaveRoomForRightTabs() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launchEnvironment["CUBEGIN_UI_TEST_DUO_TAB_SIDE"] = "right"
        app.launch()
        try XCTSkipUnless(app.frame.width > app.frame.height && app.frame.width < 750,
                          "Run with the Duo cover display active in landscape.")

        let settings = app.buttons["side-nav.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        let rightTabs = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            settings.frame.midX > app.frame.midX
        }, object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [rightTabs], timeout: 5), .completed)
        let event = app.buttons["Event"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        let timerEventFrame = event.frame
        captureLandscapePage("Duo timer header", cutout: "right")
        app.buttons["side-nav.results"].tap()
        let picker = app.buttons["results.view"]
        let group = app.buttons["Group"]
        let firstRow = app.buttons["solve-row-12"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertEqual(event.frame.minX, timerEventFrame.minX, accuracy: 2)
        XCTAssertEqual(event.frame.midY, timerEventFrame.midY, accuracy: 2)
        let groupFrame = group.frame
        let pickerFrame = picker.frame
        let firstRowY = firstRow.frame.midY
        let listDrag = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        listDrag.press(forDuration: 0.05, thenDragTo: listDrag.withOffset(CGVector(dx: 0, dy: -72)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(!firstRow.exists || firstRow.frame.midY < firstRowY)
        XCTAssertEqual(group.frame, groupFrame)
        XCTAssertEqual(picker.frame, pickerFrame)
        captureLandscapePage("Duo results scrolled", cutout: "right")
        picker.tap()
        app.buttons["Statistics"].tap()
        let overview = app.staticTexts["Valid / Total"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        captureLandscapePage("Duo statistics", cutout: "right")
        let initialOverviewY = overview.frame.midY
        app.swipeUp()
        XCTAssertTrue(!overview.exists || overview.frame.midY < initialOverviewY)
        captureLandscapePage("Duo statistics scrolled", cutout: "right")

        settings.tap()
        let settingsTitle = app.staticTexts["settings.title"]
        let theme = app.buttons["settings.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        let titleFrame = settingsTitle.frame
        let themeY = theme.frame.midY
        app.swipeUp()
        XCTAssertTrue(!theme.exists || theme.frame.midY < themeY)
        XCTAssertEqual(settingsTitle.frame, titleFrame)

        let dnf = app.switches["settings.results.includeDNFInWorst"]
        for _ in 0..<3 where !dnf.isHittable { app.swipeUp() }
        XCTAssertTrue(dnf.isHittable)
        XCTAssertLessThan(dnf.frame.maxX, settings.frame.minX)
        captureLandscapePage("Duo settings", cutout: "right")
        XCTAssertEqual(settingsTitle.frame, titleFrame)
        captureLandscapePage("Duo settings scrolled", cutout: "right")
    }

    @MainActor
    func testLandscapePageEdgesAlignInBothDirections() {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.mode", "standard", "-scramble.standard", "333"]

        for (orientation, cutout) in [(UIDeviceOrientation.landscapeLeft, "left"), (.landscapeRight, "right")] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let event = app.buttons["Event"]
            let hints = app.buttons["timer.formula-hints"]
            let home = app.buttons["side-nav.home"]
            let results = app.buttons["side-nav.results"]
            let settings = app.buttons["side-nav.settings"]
            XCTAssertTrue(home.waitForExistence(timeout: 10))
            home.tap()
            XCTAssertTrue(event.waitForExistence(timeout: 10))
            XCTAssertTrue(hints.waitForExistence(timeout: 20))
            let leading = event.frame.minX
            let trailing = hints.frame.maxX
            XCTAssertGreaterThanOrEqual(leading - app.frame.minX, 42)
            XCTAssertEqual(settings.frame.minX - trailing, 20, accuracy: 2) // Includes the capsule's 4pt inset.
            captureLandscapePage("Home", cutout: cutout)

            results.tap()
            let group = app.buttons["Group"]
            let picker = app.buttons["results.view"]
            let row = app.buttons["solve-row-12"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let groupFrame = group.frame
            let pickerFrame = picker.frame
            XCTAssertEqual(groupFrame.minX, leading, accuracy: 2)
            XCTAssertEqual(pickerFrame.maxX, trailing, accuracy: 2)
            captureLandscapePage("Results", cutout: cutout)
            XCTAssertLessThan(row.frame.maxX, settings.frame.minX)

            app.buttons["results.average-type.ao5"].tap()
            let average = app.buttons["average-row-0"]
            XCTAssertTrue(average.waitForExistence(timeout: 10))
            XCTAssertLessThan(average.frame.maxX, settings.frame.minX)
            captureLandscapePage("Average results", cutout: cutout)
            app.buttons["results.average-type.single"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))

            picker.tap()
            app.buttons["Statistics"].tap()
            let overview = app.staticTexts["Valid / Total"]
            XCTAssertTrue(overview.waitForExistence(timeout: 10))
            XCTAssertEqual(event.frame.minX, leading, accuracy: 2)
            XCTAssertEqual(group.frame.minX, groupFrame.minX, accuracy: 2)
            XCTAssertEqual(picker.frame.maxX, pickerFrame.maxX, accuracy: 2)
            XCTAssertLessThan(overview.frame.maxX, settings.frame.minX)
            captureLandscapePage("Statistics", cutout: cutout)

            settings.tap()
            XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.switches["settings.timer.keepScreenOn"].exists)
            captureLandscapePage("Settings", cutout: cutout)
            app.terminate()
        }
    }

    @MainActor
    private func captureLandscapePage(_ page: String, cutout: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Aligned \(page) - Cutout \(cutout)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLandscapeEventPickerCanSelectFirstEventAfterScrolling() {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "222"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["side-nav.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["timer.scramble"].waitForExistence(timeout: 20))

        let picker = app.buttons["Event"]
        picker.tap()
        let firstEvent = app.buttons["3x3x3"]
        XCTAssertTrue(firstEvent.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Landscape Event Picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(firstEvent.isHittable, "The top event must be visible when the picker opens")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.exists)
        XCTAssertLessThanOrEqual(list.frame.maxY, app.frame.maxY, "The scroll viewport must fit on screen")
        let initialFirstEventY = firstEvent.frame.minY
        let viewport = list.frame.intersection(app.frame)
        XCTAssertFalse(viewport.isEmpty)
        // XCTest can report an empty hittable frame for the collection in landscape.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let top = origin.withOffset(CGVector(
            dx: viewport.midX - app.frame.minX,
            dy: viewport.minY + viewport.height * 0.25 - app.frame.minY
        ))
        let bottom = origin.withOffset(CGVector(
            dx: viewport.midX - app.frame.minX,
            dy: viewport.minY + viewport.height * 0.75 - app.frame.minY
        ))
        bottom.press(forDuration: 0.05, thenDragTo: top)
        if firstEvent.exists {
            XCTAssertLessThan(firstEvent.frame.minY, initialFirstEventY)
        }
        for _ in 0..<4 {
            top.press(forDuration: 0.05, thenDragTo: bottom)
            if firstEvent.isHittable && abs(firstEvent.frame.minY - initialFirstEventY) <= 1 { break }
        }
        XCTAssertTrue(firstEvent.isHittable)
        XCTAssertEqual(firstEvent.frame.minY, initialFirstEventY, accuracy: 1)
        firstEvent.tap()
        XCTAssertEqual(picker.value as? String, "3x3x3")
    }

    @MainActor
    func testLandscapeNavigationAndCenteredTimer() async throws {
        continueAfterFailure = false

        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2", "-timer.wcaInspection", "NO", "-timer.entryMethod", "timer"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let scramble = app.descendants(matching: .any)["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let timer = app.descendants(matching: .any)["timer.readout"]
        let diagram = app.descendants(matching: .any)["timer.scramble-diagram"]
        let count = app.descendants(matching: .any)["timer-summary.count"]
        let mo3 = app.descendants(matching: .any)["timer-summary.mo3"]
        let ao12 = app.descendants(matching: .any)["timer-summary.ao12"]
        let home = app.buttons["side-nav.home"]
        let results = app.buttons["side-nav.results"]
        let settings = app.buttons["side-nav.settings"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertTrue(diagram.exists)
        XCTAssertFalse(count.exists)
        XCTAssertFalse(mo3.exists)
        XCTAssertFalse(ao12.exists)
        XCTAssertTrue(results.exists)
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)

        let idleTimer = timer.frame
        XCTAssertLessThan(scramble.frame.maxX, idleTimer.midX)
        XCTAssertLessThan(diagram.frame.maxX, idleTimer.midX)
        XCTAssertGreaterThan(home.frame.minX, idleTimer.maxX)
        XCTAssertEqual(home.frame.midX, results.frame.midX, accuracy: 2)
        XCTAssertEqual(home.frame.midX, settings.frame.midX, accuracy: 2)
        XCTAssertLessThan(home.frame.midY, results.frame.midY)
        XCTAssertLessThan(results.frame.midY, settings.frame.midY)
        // The 44pt button sits 4pt inside the 52pt capsule.
        let edgeGap = app.frame.maxX - settings.frame.maxX - 4
        XCTAssertEqual(edgeGap, 21, accuracy: 2)
        let hintsFrame = app.buttons["timer.formula-hints"].frame
        XCTAssertLessThan(hintsFrame.maxX, settings.frame.minX - 4)
        let columnTop = hintsFrame.maxY + 8
        let columnBottom = settings.frame.maxY + 4
        // On iOS 26.2, XCTest reports the selectable text's AX frame beyond
        // its visible glyphs. Check the rendered formula and diagram instead.
        let appFrame = app.frame
        // Exclude the physical display cutout at the left edge.
        let leading = max(scramble.frame.minX, appFrame.minX + appFrame.width * 0.08)
        let column = CGRect(x: leading, y: columnTop,
                            width: scramble.frame.maxX - leading, height: columnBottom - columnTop)
        // WebKit can finish painting the diagram after its AX element appears.
        let deadline = ContinuousClock.now + .seconds(20)
        var screen: XCUIScreenshot
        var renderedFrames: (formula: CGRect, diagram: CGRect)?
        repeat {
            screen = XCUIScreen.main.screenshot()
            renderedFrames = screen.image.cgImage.flatMap {
                renderedScrambleFrames($0, appFrame: appFrame, column: column)
            }
            if renderedFrames == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }
        } while renderedFrames == nil && ContinuousClock.now < deadline
        let attachment = XCTAttachment(screenshot: screen)
        attachment.name = "Landscape Timer Before Geometry Checks"
        attachment.lifetime = .keepAlways
        add(attachment)
        let rendered = try XCTUnwrap(renderedFrames, "The scramble formula and diagram must both be visible")
        XCTAssertGreaterThanOrEqual(rendered.diagram.minY - rendered.formula.maxY, 15)
        let scrambleGroup = rendered.formula.union(rendered.diagram)
        XCTAssertEqual(scrambleGroup.midY, (columnTop + columnBottom) / 2, accuracy: 3)

        let left = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: rendered.diagram.midX - appFrame.minX, dy: rendered.diagram.midY - appFrame.minY))
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: idleTimer.midX - appFrame.minX, dy: idleTimer.midY - appFrame.minY))
        start.press(forDuration: 0.5)
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        XCTAssertEqual(timer.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(timer.frame.midY, app.frame.midY, accuracy: 2)
        XCTAssertFalse(scramble.exists)
        XCTAssertFalse(count.exists)
        XCTAssertFalse(home.exists)

        left.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertEqual(timer.frame.midX, idleTimer.midX, accuracy: 2)
        XCTAssertEqual(timer.frame.midY, idleTimer.midY, accuracy: 2)
        XCTAssertTrue(app.buttons["timer.penalty.dnf"].waitForExistence(timeout: 5))
        XCTAssertEqual(count.value as? String, "1 / 1")
        XCTAssertGreaterThan(count.frame.minY, idleTimer.maxY)
        XCTAssertFalse(mo3.exists)
        XCTAssertFalse(ao12.exists)
        XCTAssertTrue(results.waitForExistence(timeout: 5))

        let formerRail = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: results.frame.midX - app.frame.minX, dy: results.frame.midY - app.frame.minY))
        start.press(forDuration: 0.5)
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        formerRail.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertEqual(count.value as? String, "2 / 2")

        results.tap()
        let solve = app.buttons["solve-row-2"]
        XCTAssertTrue(solve.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        solve.tap()
        let time = app.descendants(matching: .any)["solve-detail.time"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.tabBars.buttons["Results"].waitForExistence(timeout: 5))
        XCTAssertTrue(time.exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(time.exists)

        settings.tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.maxX - settings.frame.maxX - 4, edgeGap)
        home.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeLongestTimerAndSummary() {
        verifyLandscapeLongestTimerAndSummary(orientation: .landscapeRight, railOnLeft: false)
    }

    @MainActor
    func testDuoCoverLongestTimerWithLeftTabs() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        verifyLandscapeLongestTimerAndSummary(orientation: .landscapeLeft, railOnLeft: true)
    }

    @MainActor
    private func verifyLandscapeLongestTimerAndSummary(orientation: UIDeviceOrientation, railOnLeft: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        if railOnLeft {
            app.launchEnvironment["CUBEGIN_UI_TEST_DUO_TAB_SIDE"] = "left"
        }
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["timer.scramble"].waitForExistence(timeout: 20))
        let timer = app.buttons["timer.readout"]
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        XCTAssertEqual(timer.value as? String, "9:59:59.999")
        XCTAssertEqual(timer.frame.midX, app.frame.midX, accuracy: 2)
        let running = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        running.name = "long-timer-running"
        running.lifetime = .keepAlways
        add(running)

        center.tap()
        let plusTwo = app.buttons["timer.penalty.plusTwo"]
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 5))
        plusTwo.tap()
        let penalized = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "9:59:59.999+"), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [penalized], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["timer.penalty.dnf"].isHittable)
        XCTAssertTrue(app.buttons["Delete this solve"].isHittable)
        let summary = app.descendants(matching: .any)
        for id in ["mean", "mo3", "ao5", "ao12"] {
            XCTAssertEqual(summary["timer-summary.\(id)"].value as? String, "9:59:59.999", id)
        }
        XCTAssertEqual(summary["timer-summary.best"].value as? String, "9:59:59.999+")
        XCTAssertEqual(summary["timer-summary.count"].value as? String, "13 / 13")
        let stopped = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        stopped.name = "long-timer-stopped"
        stopped.lifetime = .keepAlways
        add(stopped)
        let rail = app.buttons["side-nav.settings"]
        if railOnLeft {
            XCTAssertLessThan(rail.frame.maxX, timer.frame.minX)
        } else {
            XCTAssertLessThan(timer.frame.maxX, rail.frame.minX)
        }
        XCTAssertLessThan(plusTwo.frame.maxY, summary["timer-summary.count"].frame.minY)
    }

    @MainActor
    func testTimerGesturesOverScrambleAndResultControls() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["-app.language", "en", "-scramble.mode", "standard", "-scramble.standard", "333",
                               "-timer.entryMethod", "timer", "-timer.startDelayTenths", "3",
                               "-timer.wcaInspection", "NO", "-timer.swipe.left", "manualEntry",
                               "-timer.swipe.right", "newScramble"]
        app.launch()

        let elements = app.descendants(matching: .any)
        let scramble = elements["timer.scramble"]
        let hints = app.buttons["timer.formula-hints"]
        let readout = elements["timer.readout"]
        let manual = app.textFields["manual-result.time"]
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 20))
        let original = scramble.label
        let center = scramble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let left = center.withOffset(CGVector(dx: -65, dy: 0))
        let right = center.withOffset(CGVector(dx: 65, dy: 0))
        left.press(forDuration: 0.01, thenDragTo: right, withVelocity: .fast, thenHoldForDuration: 0)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", original), object: scramble)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 15))
        right.press(forDuration: 0.01, thenDragTo: left, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(manual.waitForNonExistence(timeout: 5))
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 5))

        let diagram = elements["timer.scramble-diagram"]
        XCTAssertTrue(diagram.exists)
        diagram.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.55)
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        readout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 15))

        let dnf = app.buttons["timer.penalty.dnf"]
        XCTAssertTrue(dnf.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(dnf.frame.height, 44)
        dnf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(dnf.isSelected)
        XCTAssertEqual(readout.label, "Start timer")
        dnf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.55)
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        readout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertFalse(dnf.isSelected)

        XCTAssertTrue(hints.wait(for: \.isHittable, toEqual: true, timeout: 15))
        let summary = elements["timer-summary.count"]
        XCTAssertTrue(summary.exists)
        summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.55)
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
    }

    @MainActor
    func testTimerSwipeShortcutsPersistAndUseTheExistingSolveFlows() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
                      "The Duo has a separate touch surface.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-timer.entryMethod", "timer",
                                "-timer.wcaInspection", "NO", "-timer.startDelayTenths", "0"]
        app.launch()

        let scramble = app.descendants(matching: .any)["timer.scramble"]
        let readout = app.descendants(matching: .any)["timer.readout"]
        let diagram = app.descendants(matching: .any)["timer.scramble-diagram"]
        let gestures = app.buttons["settings.timer.gestures"]
        let form = app.scrollViews.firstMatch
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5))

        func openGestures() {
            app.tabBars.buttons["Settings"].tap()
            if !gestures.isHittable { form.swipeUp() }
            XCTAssertTrue(gestures.isHittable)
            gestures.tap()
        }

        func select(_ option: String, for direction: String) {
            let picker = app.descendants(matching: .any).matching(identifier: "settings.timer.swipe.\(direction)").firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            app.buttons[option].tap()
        }

        func swipe(to end: XCUICoordinate, hold: TimeInterval = 0.01) {
            center.press(forDuration: hold, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }

        func expectResult(_ result: String) {
            let value = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", result), object: readout)
            XCTAssertEqual(XCTWaiter.wait(for: [value], timeout: 5), .completed)
        }

        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        openGestures()
        let timerSettings = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        timerSettings.name = "Timer gesture settings"
        timerSettings.lifetime = .keepAlways
        add(timerSettings)
        select("Enter result manually", for: "left")
        select("Generate new scramble", for: "right")

        app.terminate()
        app.launch()
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let originalScramble = scramble.label
        let field = app.textFields["manual-result.time"]
        swipe(to: left, hold: 0.5)
        XCTAssertFalse(field.exists)
        XCTAssertEqual(readout.label, "Start timer")

        swipe(to: center.withOffset(CGVector(dx: 22, dy: 0)))
        XCTAssertEqual(scramble.label, originalScramble)
        XCTAssertEqual(readout.label, "Start timer")

        swipe(to: right)
        let newScramble = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND label != %@", originalScramble), object: scramble
        )
        XCTAssertEqual(XCTWaiter.wait(for: [newScramble], timeout: 20), .completed)
        XCTAssertTrue(diagram.exists)
        swipe(to: left)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("0012345")
        app.buttons["Save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        expectResult("12.345")
        XCTAssertEqual(readout.label, "Start timer")
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        XCTAssertTrue(diagram.exists)

        openGestures()
        select("Delete last result", for: "right")
        app.tabBars.buttons["Home"].tap()
        swipe(to: right)
        let confirmation = app.alerts["Delete this solve?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertFalse(confirmation.staticTexts["12.345"].exists)
        confirmation.buttons["Delete"].tap()
        expectResult("0.000")

        openGestures()
        select("None", for: "right")
        app.tabBars.buttons["Home"].tap()
        let unchangedScramble = scramble.label
        swipe(to: right)
        XCTAssertEqual(scramble.label, unchangedScramble)
        XCTAssertEqual(readout.label, "Start timer")
        XCTAssertFalse(confirmation.exists)
    }

    @MainActor
    func testManualEntryCanCancelAndSaveAPenalizedResult() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
                      "The Duo has a separate touch surface.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-timer.wcaInspection", "YES"]
        app.launch()
        let scramble = app.descendants(matching: .any)["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap()
        let method = app.descendants(matching: .any).matching(identifier: "settings.timer.entryMethod").firstMatch
        let display = app.descendants(matching: .any).matching(identifier: "settings.timer.display").firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        let originallyUsedTimer = display.exists
        if originallyUsedTimer {
            method.tap()
            app.buttons["Manual"].tap()
        }
        XCTAssertFalse(display.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let originalScramble = scramble.label
        let readout = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Enter result", timeout: 5))
        XCTAssertEqual(readout.value as? String, "0.000")
        let summary = app.descendants(matching: .any)
        XCTAssertFalse(summary["timer-summary.count"].exists)
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let idleScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        idleScreenshot.name = "Timer before manual entry"
        idleScreenshot.lifetime = .keepAlways
        add(idleScreenshot)
        center.tap()
        let field = app.textFields["manual-result.time"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(scramble.label, originalScramble)
        center.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let save = app.buttons["Save"]
        XCTAssertFalse(save.isEnabled)
        let lastDigit = app.buttons["manual-result.digit.6"]
        lastDigit.tap()
        field.typeText("1")
        XCTAssertEqual(lastDigit.value as? String, "1")
        XCTAssertTrue(save.isEnabled)
        lastDigit.tap()
        field.typeText("0")
        XCTAssertFalse(save.isEnabled)
        app.buttons["manual-result.digit.0"].tap()
        field.typeText("001234")
        let digitValues = (0..<7).map { app.buttons["manual-result.digit.\($0)"].value as? String ?? "" }
        XCTAssertEqual(digitValues.joined(), "0012340")
        let plusTwo = app.buttons["+2"]
        plusTwo.tap()
        XCTAssertTrue(plusTwo.isSelected)
        XCTAssertFalse(app.staticTexts["manual-result.preview"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Manual result entry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        field.typeText("5")
        XCTAssertEqual(lastDigit.value as? String, "5")
        let editedDigit = app.buttons["manual-result.digit.5"]
        editedDigit.tap()
        XCTAssertTrue(editedDigit.isSelected)
        field.typeText("9")
        XCTAssertEqual(editedDigit.value as? String, "9")
        XCTAssertEqual(lastDigit.value as? String, "5")
        app.buttons["Save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "14.395+"), object: readout
        )], timeout: 5), .completed)
        let newScramble = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND label != %@", originalScramble), object: scramble
        )
        XCTAssertEqual(XCTWaiter.wait(for: [newScramble], timeout: 20), .completed)
        XCTAssertEqual(summary["timer-summary.count"].value as? String, "1 / 1")
        XCTAssertFalse(summary["timer-summary.ao12"].exists)

        center.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        app.buttons["DNF"].tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let timerDNF = app.buttons["timer.penalty.dnf"]
        XCTAssertTrue(timerDNF.waitForExistence(timeout: 5))
        XCTAssertTrue(timerDNF.isSelected)
        XCTAssertFalse(timerDNF.isEnabled)
        XCTAssertFalse(app.buttons["timer.penalty.plusTwo"].isEnabled)

        app.tabBars.buttons["Results"].tap()
        app.buttons["solve-row-2"].tap()
        let noPenalty = app.buttons["solve-detail.no-penalty"]
        let detailPlusTwo = app.buttons["solve-detail.+2"]
        let detailDNF = app.buttons["solve-detail.DNF"]
        XCTAssertTrue(detailDNF.waitForExistence(timeout: 5))
        XCTAssertTrue(detailDNF.isSelected)
        XCTAssertFalse(noPenalty.isEnabled)
        XCTAssertFalse(detailPlusTwo.isEnabled)
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["solve-row-1"].tap()
        XCTAssertTrue(detailPlusTwo.waitForExistence(timeout: 5))
        XCTAssertTrue(detailPlusTwo.isSelected)
        noPenalty.tap()
        XCTAssertTrue(noPenalty.isSelected)
        XCTAssertFalse(detailPlusTwo.isSelected)
        noPenalty.tap()
        XCTAssertTrue(noPenalty.isSelected)
        detailDNF.tap()
        XCTAssertTrue(detailDNF.isSelected)
        XCTAssertFalse(noPenalty.isSelected)

        if originallyUsedTimer {
            app.tabBars.buttons["Settings"].tap()
            method.tap()
            app.buttons["Timer"].tap()
            XCTAssertTrue(display.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testObservationOnlyKeepsInspectionAndFinalTime() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
                      "The Duo has a separate touch surface.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-timer.display", "observation", "-timer.wcaInspection", "YES"]
        app.launchArguments += ["-timer.entryMethod", "timer"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["timer.scramble"].waitForExistence(timeout: 20))
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timer.inspection"].waitForExistence(timeout: 5))
        center.tap()
        let readout = app.descendants(matching: .any)["timer.readout"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Solving"), object: readout
        )], timeout: 5), .completed)
        center.tap()
        XCTAssertTrue(readout.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        let result = try XCTUnwrap(readout.value as? String)
        XCTAssertNotNil(result.range(of: #"^\d+\.\d{3}$"#, options: .regularExpression))
    }

    @MainActor
    func testQuickInspectionTapsUseTheSharedTimer() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
                      "Use the Duo-specific case for its separate touch surface.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.wcaInspection", "YES", "-timer.startDelayTenths", "20"]
        app.launchArguments += ["-timer.entryMethod", "timer"]
        app.launch()
        let scramble = app.descendants(matching: .any)["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        center.tap()
        let inspection = app.descendants(matching: .any).matching(identifier: "timer.inspection").firstMatch
        XCTAssertTrue(inspection.waitForExistence(timeout: 5))
        center.tap()
        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        center.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
    }

    @MainActor
    func testInspectionContinuesAfterSwipeCancellation() {
        continueAfterFailure = false

        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.mode", "standard", "-scramble.standard", "333",
                                "-timer.wcaInspection", "YES", "-timer.startDelayTenths", "2",
                                "-timer.entryMethod", "timer"]
        app.launch()

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(app.buttons["timer.formula-hints"].waitForExistence(timeout: 20))
        XCTAssertTrue(timer.waitForExistence(timeout: 20))
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()

        let inspection = app.descendants(matching: .any).matching(identifier: "timer.inspection").firstMatch
        XCTAssertTrue(inspection.waitForExistence(timeout: 5))
        let inspectionFrame = inspection.frame
        let readout = inspection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let cancelZone = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        readout.press(forDuration: 0.5, thenDragTo: cancelZone, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(inspection.exists)

        readout.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        XCTAssertFalse(inspection.exists)
        XCTAssertEqual(timer.frame.midX, inspectionFrame.midX, accuracy: 1)
        XCTAssertEqual(timer.frame.midY, inspectionFrame.midY, accuracy: 1)
    }

    @MainActor
    func testTimedSolveAndPenaltySurviveRelaunch() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launchArguments += ["-timer.entryMethod", "timer"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        let scramble = app.descendants(matching: .any)["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let originalScramble = scramble.label
        XCTAssertFalse(originalScramble.isEmpty)

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.5, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)),
                     withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertEqual(scramble.label, originalScramble)

        center.press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        center.tap()

        let dnf = app.buttons["timer.penalty.dnf"]
        XCTAssertTrue(dnf.waitForExistence(timeout: 5))
        dnf.tap()
        let markedDNF = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "DNF"), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [markedDNF], timeout: 5), .completed)

        app.terminate()
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        let results = app.tabBars.buttons["Results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        let solve = app.descendants(matching: .any).matching(identifier: "solve-row-1").firstMatch
        XCTAssertTrue(solve.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["solve-row-2"].exists)
        solve.tap()

        let time = app.descendants(matching: .any)["solve-detail.time"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        XCTAssertEqual(time.value as? String, "DNF")
        let savedScramble = app.staticTexts["solve-detail.scramble"]
        XCTAssertTrue(savedScramble.waitForExistence(timeout: 5))
        XCTAssertEqual(savedScramble.label, originalScramble)
    }
}

private func renderedScrambleFrames(
    _ image: CGImage,
    appFrame: CGRect,
    column: CGRect
) -> (formula: CGRect, diagram: CGRect)? {
    guard let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ), let data = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = data.assumingMemoryBound(to: UInt8.self)

    // XCTest may supply the landscape-left screen as a portrait bitmap.
    let rotatesLeft = image.width < image.height
    let width = rotatesLeft ? image.height : image.width
    let height = rotatesLeft ? image.width : image.height
    let scaleX = CGFloat(width) / appFrame.width
    let scaleY = CGFloat(height) / appFrame.height
    let xStart = max(0, Int((column.minX - appFrame.minX) * scaleX))
    let xEnd = min(width, Int((column.maxX - appFrame.minX) * scaleX))
    let yStart = max(0, Int((column.minY - appFrame.minY) * scaleY))
    let yEnd = min(height, Int((column.maxY - appFrame.minY) * scaleY))
    guard xStart < xEnd, yStart < yEnd else { return nil }

    func channels(atX x: Int, y: Int) -> (darkest: Int, brightest: Int) {
        let imageX = rotatesLeft ? image.width - 1 - y : x
        let imageY = rotatesLeft ? x : y
        let index = (imageY * image.width + imageX) * 4
        let red = Int(pixels[index])
        let green = Int(pixels[index + 1])
        let blue = Int(pixels[index + 2])
        return (min(red, green, blue), max(red, green, blue))
    }

    func bounds(through end: Int, matching predicate: (Int, Int) -> Bool) -> CGRect? {
        var left = xEnd, top = end, right = xStart - 1, bottom = yStart - 1
        for y in yStart..<end {
            for x in xStart..<xEnd {
                let (darkest, brightest) = channels(atX: x, y: y)
                if predicate(darkest, brightest) {
                    left = min(left, x)
                    top = min(top, y)
                    right = max(right, x)
                    bottom = max(bottom, y)
                }
            }
        }
        guard left <= right, top <= bottom else { return nil }
        return CGRect(x: appFrame.minX + CGFloat(left) / scaleX,
                      y: appFrame.minY + CGFloat(top) / scaleY,
                      width: CGFloat(right - left + 1) / scaleX,
                      height: CGFloat(bottom - top + 1) / scaleY)
    }

    guard let diagram = bounds(through: yEnd, matching: { $1 >= 180 && $1 - $0 >= 100 }) else { return nil }
    // Leave the dark outline of the top cube stickers out of the text bounds.
    let formulaEnd = max(yStart, Int((diagram.minY - appFrame.minY - 2) * scaleY))
    let lightBackground = channels(atX: xStart, y: yStart).darkest >= 128
    guard let formula = bounds(through: formulaEnd, matching: {
        lightBackground ? $1 < 96 : $0 > 159
    }) else { return nil }
    return (formula, diagram)
}
