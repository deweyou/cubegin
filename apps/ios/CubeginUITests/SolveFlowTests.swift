import CoreGraphics
import SQLite3
import XCTest

final class SolveFlowTests: XCTestCase {
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
            if event == "333.easy_xcross" { captureProjectPicker("Standard projects") }
            training.tap()
            XCTAssertTrue(training.isSelected)
            if event == "333.easy_xcross" { captureProjectPicker("Training projects") }
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
    private func captureProjectPicker(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()
        try XCTSkipUnless(app.frame.width >= 750 && app.frame.width > app.frame.height,
                          "Run with the Duo inner display active in landscape.")

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
        let dnf = app.switches["settings.results.includeDNFInWorst"]
        XCTAssertTrue(dnf.waitForExistence(timeout: 5))
        XCTAssertLessThan(dnf.frame.maxX, settings.frame.minX)
        captureLandscapePage("Duo settings", cutout: "right")
        let settingsTitle = app.staticTexts["settings.title"]
        let titleFrame = settingsTitle.frame
        let toggleY = dnf.frame.midY
        app.swipeUp()
        XCTAssertTrue(!dnf.exists || dnf.frame.midY < toggleY)
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
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]

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
            let leading = event.frame.minX
            XCTAssertTrue(hints.exists)
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
        XCTAssertEqual(field.value as? String, "0012340")
        let plusTwo = app.buttons["+2"]
        plusTwo.tap()
        XCTAssertTrue(plusTwo.isSelected)
        XCTAssertFalse(app.staticTexts["manual-result.preview"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Manual result entry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        field.typeText("5")
        XCTAssertEqual(field.value as? String, "0012345")
        let editedDigit = app.buttons["manual-result.digit.5"]
        editedDigit.tap()
        XCTAssertTrue(editedDigit.isSelected)
        field.typeText("9")
        XCTAssertEqual(field.value as? String, "0012395")
        app.buttons["Save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "14.395+"), object: readout
        )], timeout: 5), .completed)
        XCTAssertTrue(scramble.waitForExistence(timeout: 20))
        XCTAssertNotEqual(scramble.label, originalScramble)
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

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333",
                                "-timer.wcaInspection", "YES", "-timer.startDelayTenths", "2"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        let timer = app.descendants(matching: .any)["timer.readout"]
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
