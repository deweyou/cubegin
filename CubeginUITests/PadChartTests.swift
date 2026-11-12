import UIKit
import XCTest

final class PadChartTests: XCTestCase {
    @MainActor
    func testPadTimerKeepsItsCenterThroughLongSolve() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This layout uses the iPad window.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333", "-timer.startDelayTenths", "2"]
        let timer = app.buttons["timer.readout"]
        let formula = app.descendants(matching: .any)["timer.scramble"].firstMatch
        let diagram = app.descendants(matching: .any)["timer.scramble-diagram"].firstMatch
        let summary = app.descendants(matching: .any)["timer-summary.count"].firstMatch

        for (orientation, name) in [(UIDeviceOrientation.landscapeLeft, "Landscape"), (.portrait, "Portrait")] {
            XCUIDevice.shared.press(.home)
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(formula.waitForExistence(timeout: 20))
            XCTAssertEqual(app.frame.width > app.frame.height, orientation.isLandscape)
            let idle = timer.frame
            print("iPad \(name) bounds: window=\(app.frame), timer=\(idle), formula=\(formula.frame), diagram=\(diagram.frame), summary=\(summary.frame)")
            attachScreenshot("iPad \(name) Timer Idle")

            let center = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(forDuration: 0.5)
            XCTAssertTrue(timer.wait(for: \.label, toEqual: "Stop timer", timeout: 5))
            XCTAssertEqual(timer.value as? String, "9:59:59.999")
            XCTAssertEqual(timer.frame.midX, idle.midX, accuracy: 2)
            XCTAssertEqual(timer.frame.midY, idle.midY, accuracy: 2)
            XCTAssertEqual(timer.frame.height, idle.height, accuracy: 2)
            attachScreenshot("iPad \(name) Timer Long")

            center.tap()
            XCTAssertTrue(timer.wait(for: \.label, toEqual: "Start timer", timeout: 5))
            XCTAssertEqual(timer.frame.midY, idle.midY, accuracy: 2)
            let plusTwo = app.buttons["timer.penalty.plusTwo"]
            XCTAssertTrue(plusTwo.isHittable)
            plusTwo.tap()
            XCTAssertEqual(timer.value as? String, "9:59:59.999+")
            let average = app.staticTexts["timer-recent.ao5.0"]
            let single = app.staticTexts["timer-recent.single.0"]
            XCTAssertTrue(average.waitForExistence(timeout: 5))
            XCTAssertEqual(average.label, "9:59:59.999")
            XCTAssertEqual(single.label, "9:59:59.999+")
            XCTAssertEqual(app.staticTexts["timer-recent.ao5.4"].label, "9:59:59.999")
            XCTAssertEqual(app.staticTexts["timer-recent.single.4"].label, "9:59:59.999+")
            XCTAssertGreaterThanOrEqual(timer.frame.minX - average.frame.maxX, 24)
            XCTAssertGreaterThanOrEqual(single.frame.minX - timer.frame.maxX, 24)
            print("iPad \(name) maximum results: average=\(average.frame), timer=\(timer.frame), single=\(single.frame)")
            attachScreenshot("iPad \(name) Maximum Results With Penalty")
            app.terminate()
        }
    }

    @MainActor
    func testMegaminxScrambleFillsPadFormulaRegion() throws {
        try checkFullWidthScramble(event: "minx", name: "Megaminx", expectedRows: 7)
    }

    @MainActor
    func testSevenBySevenScrambleFillsPadFormulaRegion() throws {
        try checkFullWidthScramble(event: "777", name: "7x7")
    }

    @MainActor
    private func checkFullWidthScramble(event: String, name: String, expectedRows: Int? = nil) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This layout uses the iPad window.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-app.language", "en", "-scramble.standard", event]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let formula = app.descendants(matching: .any)["timer.scramble"].firstMatch
        let timer = app.descendants(matching: .any)["timer.readout"].firstMatch
        XCTAssertTrue(formula.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertEqual(formula.frame.midX, app.frame.midX, accuracy: 2)
        if let expectedRows {
            XCTAssertEqual(formula.label.components(separatedBy: .newlines).count, expectedRows)
            XCTAssertGreaterThan(formula.frame.height, 200)
        } else {
            XCTAssertGreaterThan(formula.frame.width, (app.frame.width - 48) * 0.9)
        }
        XCTAssertLessThan(formula.frame.maxY, timer.frame.minY)
        attachScreenshot("iPad Landscape \(name) Full Width")

        app.terminate()
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let portraitWindow = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.height > app.frame.width },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portraitWindow], timeout: 10), .completed)
        XCTAssertTrue(formula.waitForExistence(timeout: 10))
        XCTAssertTrue(formula.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertEqual(formula.frame.midX, app.frame.midX, accuracy: 2)
        if let expectedRows {
            XCTAssertEqual(formula.label.components(separatedBy: .newlines).count, expectedRows)
            XCTAssertGreaterThan(formula.frame.height, 200)
        } else {
            XCTAssertGreaterThan(formula.frame.width, (app.frame.width - 48) * 0.9)
        }
        XCTAssertLessThan(formula.frame.maxY, timer.frame.minY)
        attachScreenshot("iPad Portrait \(name) Full Width")
    }

    @MainActor
    func testChartFillsRegularWidthPadWindow() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This layout uses the iPad regular-width window.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchEnvironment["CUBEGIN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["CUBEGIN_UI_TEST_LONG_SOLVE"] = "1"
        app.launchArguments += ["-app.language", "en", "-scramble.standard", "333"]
        app.launch()
        let results = app.buttons.matching(identifier: "Results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        results.tap()
        let single = app.buttons["results.average-type.single"]
        let solve = app.buttons["solve-row-12"]
        XCTAssertTrue(solve.waitForExistence(timeout: 10))
        XCTAssertTrue(single.isSelected)
        attachScreenshot("iPad Single Results")

        let ao5 = app.buttons["results.average-type.ao5"]
        ao5.tap()
        let average = app.buttons["average-row-0"]
        XCTAssertTrue(average.waitForExistence(timeout: 5))
        XCTAssertTrue(ao5.isSelected)
        attachScreenshot("iPad Average Results")
        average.tap()
        XCTAssertTrue(app.staticTexts["Worst single"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(single.waitForExistence(timeout: 5))
        single.tap()
        XCTAssertTrue(solve.waitForExistence(timeout: 5))

        let view = app.buttons["results.view"]
        view.tap()
        app.buttons["Statistics"].tap()
        let overview = app.staticTexts["Valid / Total"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        attachScreenshot("iPad Statistics Overview")

        let mode = app.segmentedControls["charts.mode"]
        for _ in 0..<4 where !mode.isHittable { app.swipeUp() }
        XCTAssertTrue(mode.isHittable)
        let plot = app.descendants(matching: .any)["Solve trend"].firstMatch
        XCTAssertTrue(plot.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(plot.frame.width, app.frame.width * 0.8)
        XCTAssertLessThan(mode.frame.maxY, plot.frame.minY)
        XCTAssertTrue(app.buttons["charts.range"].isHittable)
        XCTAssertTrue(app.buttons["charts.average"].isHittable)
        let controlsY = mode.frame.minY
        attachScreenshot("iPad Statistics Trend")

        mode.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Time distribution"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["charts.range"].isHittable)
        XCTAssertFalse(app.buttons["charts.average"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["charts.distribution"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(mode.frame.minY, controlsY, accuracy: 1)
        attachScreenshot("iPad Statistics Distribution")
        mode.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(plot.waitForExistence(timeout: 10))
        let dailyPractice = app.staticTexts["Practice volume"]
        for _ in 0..<4 where !dailyPractice.isHittable { app.swipeUp() }
        XCTAssertTrue(dailyPractice.isHittable)
        XCTAssertLessThan(plot.frame.maxY, dailyPractice.frame.minY)
        attachScreenshot("iPad Statistics Daily Practice")
        app.buttons.matching(identifier: "Settings").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.results.includeDNFInWorst"].isHittable)
        attachScreenshot("iPad Settings")
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
