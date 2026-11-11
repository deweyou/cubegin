import XCTest

final class SolveFlowTests: XCTestCase {
    @MainActor
    func testPortraitSolveListKeepsPickersFixedWhileScrolling() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launch()

        let event = app.buttons["Event"]
        let training = app.buttons["Training"]
        XCTAssertTrue(event.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["timer.scramble"].waitForExistence(timeout: 10))
        recordPortraitPage("Home", frames: [event.frame, training.frame])

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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
        recordPortraitPage("Results before scroll", frames: [event.frame, training.frame, groupFrame, viewFrame, rowFrame])

        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: rowFrame.midX, dy: rowFrame.midY + 45))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -36)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        recordPortraitPage("Results after scroll", frames: [group.frame, view.frame, row.frame])
        XCTAssertLessThan(row.frame.minY, groupFrame.maxY)
        XCTAssertEqual(group.frame, groupFrame)
        XCTAssertEqual(view.frame, viewFrame)
        view.tap()
        XCTAssertTrue(app.buttons["Overview"].waitForExistence(timeout: 5))
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
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()

        let results = app.buttons["side-nav.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        let viewPicker = app.buttons["results.view"]
        viewPicker.tap()
        app.buttons["Overview"].tap()

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

        viewPicker.tap()
        let charts = app.buttons["Charts"]
        XCTAssertTrue(charts.waitForExistence(timeout: 5))
        charts.tap()
        XCTAssertEqual(viewPicker.value as? String, "Charts")

        let trendButton = app.buttons["Trend"]
        let distributionButton = app.buttons["Time distribution"]
        let range = app.buttons["charts.range"]
        let averages = app.buttons["charts.average"]
        let trend = app.descendants(matching: .any)["Solve trend"].firstMatch
        let legend = app.staticTexts["Single"]
        XCTAssertTrue(trend.waitForExistence(timeout: 5))
        XCTAssertTrue(legend.isHittable)
        let settings = app.buttons["side-nav.settings"]
        // Both capsules inset their buttons by 4pt.
        XCTAssertEqual(trendButton.frame.minY - app.frame.minY, app.frame.maxY - settings.frame.maxY, accuracy: 2)
        XCTAssertEqual(home.frame, homeFrame)
        XCTAssertLessThan(trendButton.frame.maxY, distributionButton.frame.minY)
        XCTAssertLessThan(distributionButton.frame.maxY, home.frame.minY)
        XCTAssertEqual(trendButton.frame.midX, home.frame.midX, accuracy: 1)
        XCTAssertEqual(distributionButton.frame.midX, home.frame.midX, accuracy: 1)
        XCTAssertGreaterThan(trendButton.frame.minX, viewPicker.frame.maxX)
        XCTAssertEqual(range.frame.midY, viewPicker.frame.midY, accuracy: 2)
        XCTAssertLessThan(range.frame.maxX, averages.frame.minX)
        XCTAssertLessThan(averages.frame.maxX, viewPicker.frame.minX)
        XCTAssertLessThan(viewPicker.frame.maxY, trend.frame.minY)
        XCTAssertLessThan(legend.frame.maxY, app.frame.maxY)

        let chartScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        chartScreenshot.name = "Landscape Charts Fit"
        chartScreenshot.lifetime = .keepAlways
        add(chartScreenshot)

        distributionButton.tap()
        XCTAssertTrue(range.isHittable)
        XCTAssertFalse(averages.exists)
        XCTAssertTrue(distributionButton.isSelected)
        XCTAssertEqual(trendButton.frame.minY - app.frame.minY, app.frame.maxY - settings.frame.maxY, accuracy: 2)
        let distributionScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        distributionScreenshot.name = "Landscape Distribution Rail"
        distributionScreenshot.lifetime = .keepAlways
        add(distributionScreenshot)

        let railX = trendButton.frame.midX
        XCUIDevice.shared.orientation = .landscapeRight
        let rotatedRail = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = trendButton.frame
                return frame.midX < railX
                    && abs(frame.midX - home.frame.midX) < 1
                    && abs((frame.minY - app.frame.minY) - (app.frame.maxY - settings.frame.maxY)) < 2
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [rotatedRail], timeout: 10), .completed)
        let rotatedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        rotatedScreenshot.name = "Landscape Rotated Chart Controls"
        rotatedScreenshot.lifetime = .keepAlways
        add(rotatedScreenshot)
        XCTAssertTrue(trendButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        trendButton.tap()
        XCTAssertTrue(trendButton.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertTrue(trend.waitForExistence(timeout: 10))
        XCTAssertLessThan(viewPicker.frame.maxX, trendButton.frame.minX)
        XCTAssertLessThan(trend.frame.maxX, trendButton.frame.minX)
        XCTAssertEqual(app.buttons["Event"].frame.minX - app.frame.minX, 44, accuracy: 2)

        let oppositeScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        oppositeScreenshot.name = "Landscape Charts Right Cutout"
        oppositeScreenshot.lifetime = .keepAlways
        add(oppositeScreenshot)

        viewPicker.tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Results", "side-nav.results")).firstMatch.tap()
        let solveRow = app.buttons["solve-row-12"]
        XCTAssertTrue(solveRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(viewPicker.frame.maxX, settings.frame.minX)
        XCTAssertLessThan(solveRow.frame.maxX, settings.frame.minX)
        XCTAssertFalse(trendButton.exists)

        let listScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listScreenshot.name = "Landscape Results Right Cutout"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)
    }

    @MainActor
    func testLandscapePageEdgesAlignInBothDirections() {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]

        for (orientation, cutout) in [(UIDeviceOrientation.landscapeLeft, "left"), (.landscapeRight, "right")] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let event = app.buttons["Event"]
            let training = app.buttons["Training"]
            let home = app.buttons["side-nav.home"]
            let results = app.buttons["side-nav.results"]
            let settings = app.buttons["side-nav.settings"]
            XCTAssertTrue(home.waitForExistence(timeout: 10))
            home.tap()
            XCTAssertTrue(event.waitForExistence(timeout: 10))
            let leading = event.frame.minX
            let trailing = training.frame.maxX + 40 // Sparkles slot and spacing.
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

            for (page, content) in [
                ("Averages", app.buttons["average-row-0"]),
                ("Overview", app.staticTexts["Valid / Total"]),
                ("Charts", app.descendants(matching: .any)["Solve trend"].firstMatch)
            ] {
                picker.tap()
                app.buttons[page].tap()
                XCTAssertTrue(content.waitForExistence(timeout: 10))
                XCTAssertEqual(event.frame.minX, leading, accuracy: 2)
                XCTAssertEqual(training.frame.maxX, trailing, accuracy: 2)
                XCTAssertEqual(group.frame.minX, groupFrame.minX, accuracy: 2)
                XCTAssertEqual(picker.frame.maxX, pickerFrame.maxX, accuracy: 2)
                captureLandscapePage(page, cutout: cutout)
                XCTAssertLessThan(content.frame.maxX, settings.frame.minX)
            }

            settings.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.switches["settings.results.includeDNFInWorst"].exists)
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
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "222"]
        app.launch()
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
        list.swipeUp()
        if firstEvent.exists {
            XCTAssertLessThan(firstEvent.frame.minY, initialFirstEventY)
        }
        list.swipeDown()
        XCTAssertTrue(firstEvent.isHittable)
        XCTAssertEqual(firstEvent.frame.minY, initialFirstEventY, accuracy: 1)
        firstEvent.tap()
        XCTAssertEqual(picker.value as? String, "3x3x3")
    }

    @MainActor
    func testLandscapeNavigationAndCenteredTimer() {
        continueAfterFailure = false

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launch()

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
        XCTAssertTrue(diagram.exists)
        XCTAssertTrue(count.exists)
        XCTAssertTrue(mo3.exists)
        XCTAssertTrue(home.exists)
        XCTAssertTrue(results.exists)
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)

        let idleTimer = timer.frame
        XCTAssertLessThan(scramble.frame.maxX, idleTimer.midX)
        XCTAssertGreaterThanOrEqual(diagram.frame.minY - scramble.frame.maxY, 15)
        XCTAssertLessThan(diagram.frame.maxX, idleTimer.midX)
        XCTAssertGreaterThan(count.frame.minY, idleTimer.maxY)
        XCTAssertLessThanOrEqual(count.frame.maxX, mo3.frame.minX)
        XCTAssertGreaterThan(home.frame.minX, idleTimer.maxX)
        XCTAssertEqual(home.frame.midX, results.frame.midX, accuracy: 2)
        XCTAssertEqual(home.frame.midX, settings.frame.midX, accuracy: 2)
        XCTAssertLessThan(home.frame.midY, results.frame.midY)
        XCTAssertLessThan(results.frame.midY, settings.frame.midY)
        // The 44pt button sits 4pt inside the 52pt capsule.
        let edgeGap = app.frame.maxX - settings.frame.maxX - 4
        XCTAssertEqual(edgeGap, 21, accuracy: 2)
        // The 32pt sparkles slot and its 8pt spacing follow Training.
        let trainingFrame = app.buttons["Training"].frame
        XCTAssertLessThan(trainingFrame.maxX + 40, settings.frame.minX - 4)
        XCTAssertEqual(ao12.frame.maxY, settings.frame.maxY + 4, accuracy: 3)
        let columnTop = trainingFrame.midY + 22 + 8
        let columnBottom = settings.frame.maxY + 4
        let scrambleGroup = scramble.frame.union(diagram.frame)
        XCTAssertEqual(scrambleGroup.midY, (columnTop + columnBottom) / 2, accuracy: 3)

        let left = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: diagram.frame.midX - app.frame.minX, dy: diagram.frame.midY - app.frame.minY))
        timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5)
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
        XCTAssertTrue(results.waitForExistence(timeout: 5))

        let formerRail = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: results.frame.midX - app.frame.minX, dy: results.frame.midY - app.frame.minY))
        timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5)
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
        formerRail.tap()
        XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
        XCTAssertEqual(count.value as? String, "2 / 2")

        results.tap()
        let solve = app.buttons["solve-row-2"]
        XCTAssertTrue(solve.waitForExistence(timeout: 5))
        XCTAssertEqual(trainingFrame.maxX + 40, app.buttons["Training"].frame.maxX, accuracy: 3)
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.maxX - settings.frame.maxX - 4, edgeGap)
        home.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeLongestTimerAndSummary() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
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
        XCTAssertLessThan(timer.frame.maxX, app.buttons["side-nav.settings"].frame.minX)
        XCTAssertLessThan(plusTwo.frame.maxY, summary["timer-summary.count"].frame.minY)
        let stopped = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        stopped.name = "long-timer-stopped"
        stopped.lifetime = .keepAlways
        add(stopped)
    }

    @MainActor
    func testTimedSolveAndPenaltySurviveRelaunch() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        let scramble = app.descendants(matching: .any)["timer.scramble"]
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        let originalScramble = scramble.label
        XCTAssertFalse(originalScramble.isEmpty)

        let timer = app.descendants(matching: .any)["timer.readout"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
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
