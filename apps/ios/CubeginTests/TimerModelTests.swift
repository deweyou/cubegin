import Foundation
import SQLite3
import Testing
import UIKit
import WebKit
@testable import CubeginApp

@MainActor
struct DuoTimerLayoutTests {
    @Test func usesTheActiveHorizontalFold() {
        let fold = CGRect(x: 0, y: 432, width: 669, height: 32)

        #expect(ContentView.horizontalFold(in: [fold], pageHeight: 900) == fold)
    }

    @Test func onlyUsesDivisionsThatSplitThePageHorizontally() {
        let verticalFold = CGRect(x: 324, y: 0, width: 24, height: 900)
        let offscreenFold = CGRect(x: 0, y: 884, width: 669, height: 32)
        let horizontalFold = CGRect(x: 0, y: 432, width: 669, height: 32)

        #expect(ContentView.horizontalFold(in: [], pageHeight: 900) == nil)
        #expect(ContentView.horizontalFold(in: [verticalFold, offscreenFold], pageHeight: 900) == nil)
        #expect(ContentView.horizontalFold(in: [verticalFold, horizontalFold], pageHeight: 900) == horizontalFold)
    }
}

struct AppLanguageTests {
    @Test func followsPreferredSystemLanguagesUnlessTheUserChoosesOne() {
        #expect(AppLanguage.resolve(nil, preferredLanguages: ["zh-Hant-TW", "en"]) == .chinese)
        #expect(AppLanguage.resolve(AppLanguage.systemPreference, preferredLanguages: ["fr", "en-GB"]) == .english)
        #expect(AppLanguage.resolve(AppLanguage.systemPreference, preferredLanguages: ["fr"]) == .english)
        #expect(AppLanguage.resolve("en", preferredLanguages: ["zh-Hans"]) == .english)
        #expect(AppLanguage.resolve("zh-Hans", preferredLanguages: ["en"]) == .chinese)
    }
}

@MainActor
struct AnalyticsIdentityStartupTests {
    @Test func usesAnExistingIdentityBeforeStartingWithoutOne() async throws {
        let startup = AnalyticsIdentityStartup()
        let id = UUID()
        let (events, continuation) = AsyncStream<UUID?>.makeStream()
        startup.start(lookup: { .found(id) }, create: { nil }, apply: { continuation.yield($0) })
        var updates = events.makeAsyncIterator()
        #expect(await updates.next() == .some(id))
        startup.cancel()
    }

    @Test func startsAfterTimeoutAndAttachesAnIdentityThatArrivesLater() async throws {
        let startup = AnalyticsIdentityStartup()
        let (lookup, response) = AsyncStream<CloudAnalyticsIdentityLookup>.makeStream()
        let (events, continuation) = AsyncStream<UUID?>.makeStream()
        startup.start(timeout: .milliseconds(10), lookup: {
            var responses = lookup.makeAsyncIterator()
            return await responses.next() ?? .unavailable
        }, create: { nil }, apply: { continuation.yield($0) })

        var updates = events.makeAsyncIterator()
        #expect(await updates.next() == .some(nil))
        let id = UUID()
        response.yield(.found(id))
        #expect(await updates.next() == .some(id))
        startup.cancel()
    }

    @Test func startsImmediatelyWhenTheRecordIsMissingAndThenAttachesTheCreatedIdentity() async throws {
        let startup = AnalyticsIdentityStartup()
        let (events, continuation) = AsyncStream<UUID?>.makeStream()
        let id = UUID()
        startup.start(lookup: { .missing }, create: { id }, apply: { continuation.yield($0) })
        var updates = events.makeAsyncIterator()
        #expect(await updates.next() == .some(nil))
        #expect(await updates.next() == .some(id))
        startup.cancel()
    }

    @Test func onlyRecordsTheNewIdentityAfterReplacingAnInFlightLookup() async throws {
        let startup = AnalyticsIdentityStartup()
        let (lookup, response) = AsyncStream<CloudAnalyticsIdentityLookup>.makeStream()
        let (events, continuation) = AsyncStream<UUID?>.makeStream()
        startup.start(lookup: {
            var responses = lookup.makeAsyncIterator()
            return await responses.next() ?? .unavailable
        }, create: { nil }, apply: { continuation.yield($0) })
        startup.cancel()
        response.yield(.found(UUID()))
        let newID = UUID()
        startup.start(lookup: { .found(newID) }, create: { nil }, apply: { continuation.yield($0) })
        var updates = events.makeAsyncIterator()
        #expect(await updates.next() == .some(newID))
        startup.cancel()
    }
}

@MainActor
struct TimerModelTests {
    @Test func productEventFieldsUseTheApprovedValues() {
        #expect(ProductEvent.solveSaved(project: "333.pll", entryMethod: .timer).fields ==
                ["cube_event": "event_333", "entry_method": "timer"])
        #expect(ProductEvent.solveSaved(project: "333.unknown", entryMethod: .timer).fields ==
                ["cube_event": "other", "entry_method": "timer"])
        #expect(ProductEvent.solveSaved(project: "minx", entryMethod: .manual).fields ==
                ["cube_event": "event_minx", "entry_method": "manual"])
        #expect(ProductEvent.wcaInspectionStarted(.off).fields == ["inspection_voice": "off"])
        #expect(ProductEvent.solveListViewed(includesDNF: false).fields == ["include_dnf_in_worst": "off"])
        #expect(ProductEvent.statisticsViewed.fields.isEmpty)
        #expect(ProductEvent.dctimerImportStarted.fields.isEmpty)
        #expect(ProductEvent.dctimerImportCompleted.fields.isEmpty)
        let setting = ProductEvent.featureUsed(.settingChanged(from: .swipe(.left, .newScramble), to: .swipe(.left, .none)))
        #expect(setting.name == "feature_used")
        #expect(setting.fields == ["feature": "settings", "action": "change", "setting": "swipe_left",
                                   "previous_value": "newScramble", "setting_value": "none"])
        #expect(ProductEvent.featureUsed(.assistMethodSelected(.xcross)).fields ==
                ["feature": "assist_formula", "action": "select_method", "method": "xcross"])
        #expect(ProductEvent.featureUsed(.chartSelected(.distribution)).fields ==
                ["feature": "statistics_chart", "action": "select", "chart_type": "distribution"])
        #expect(ProductEvent.featureUsed(.chartViewed(.trend)).fields ==
                ["feature": "statistics_chart", "action": "view", "chart_type": "trend"])
        #expect(ProductEvent.featureUsed(.assistMethodViewed(.cross)).fields ==
                ["feature": "assist_formula", "action": "view_method", "method": "cross"])
        #expect(ProductEvent.featureUsed(.resultsMoved(.batch)).fields ==
                ["feature": "result_group", "action": "move_results", "scope": "batch"])
        #expect(ProductEvent.featureUsed(.dctimerImportUndone).fields ==
                ["feature": "dctimer_import", "action": "undo"])
        #expect(ProductEvent.featureUsed(.resultsCleared(.selectedGroups)).fields ==
                ["feature": "settings", "action": "clear_results", "scope": "selected_groups"])
    }

    @Test func recordsGroupCreationAndOnlyChangedOrder() async throws {
        try await withFixture { fixture in
            var events: [ProductEvent] = []
            let model = fixture.model(recordProductEvent: { events.append($0) })
            #expect(!model.saveGroup(name: " ", isDefault: false))
            #expect(model.saveGroup(name: "Practice", isDefault: false))
            let groupID = try #require(model.currentGroup?.id)
            #expect(model.saveGroup(id: groupID, name: "Edited", isDefault: false))
            let order = model.eventGroups.map(\.id)
            #expect(!model.reorderGroups([]))
            #expect(model.reorderGroups(order))
            #expect(model.reorderGroups(Array(order.reversed())))
            #expect(events == [.featureUsed(.groupCreated), .featureUsed(.groupReordered)])
        }
    }

    @Test func recordsNewSolvesOnceAfterSavingAndCountsSilentInspection() async throws {
        try await withFixture { fixture in
            var events: [ProductEvent] = []
            let model = fixture.model(recordProductEvent: { events.append($0) })
            model.refresh()
            try await waitForGeneration(model)
            let context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: nil, penalty: .dnf, context: context) == nil)
            let saved = try #require(model.lastSolve)
            #expect(model.setPenalty(.plusTwo, for: saved.id) == false)
            #expect(events == [.solveSaved(project: "333", entryMethod: .manual)])

            try await waitForGeneration(model)
            let second = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 12_000, penalty: nil, context: second) == nil)
            let editable = try #require(model.lastSolve)
            #expect(model.setPenalty(.plusTwo, for: editable.id))
            #expect(events == [.solveSaved(project: "333", entryMethod: .manual), .solveSaved(project: "333", entryMethod: .manual)])

            try await waitForGeneration(model)
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            model.activateAccessibleTimer()
            #expect(model.inspectionStarted != nil)
            #expect(events == [.solveSaved(project: "333", entryMethod: .manual), .solveSaved(project: "333", entryMethod: .manual), .wcaInspectionStarted(.off)])
            model.interrupt()
        }
    }

    @Test
    func reviewInvitationRequiresTwelveValidResultsAcrossThreeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 0)
        let firstEleven = (0..<11).map { index in
            Solve(seconds: 10, event: "333", scramble: "", date: day.addingTimeInterval(Double(index % 2) * 86_400))
        }
        let thirdDay = day.addingTimeInterval(172_800)
        let dnf = Solve(seconds: 10, event: "333", scramble: "", date: thirdDay, penalty: .dnf)
        let sameDay = Solve(seconds: 10, event: "333", scramble: "", date: day)
        let qualifying = Solve(seconds: 10, event: "333", scramble: "", date: thirdDay, penalty: .plusTwo)

        #expect(!ResultsReviewEligibility.qualifies(firstEleven, calendar: calendar))
        #expect(!ResultsReviewEligibility.qualifies(firstEleven + [dnf, sameDay], calendar: calendar))
        #expect(ResultsReviewEligibility.qualifies(firstEleven + [qualifying], calendar: calendar))
    }

    @Test
    func savesAnExplicitSharingChoicePerInstallation() throws {
        let suite = "sharing-choice-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "telemetry.diagnosticsEnabled")
        #expect(AppTelemetry.sharingChoice(in: defaults) == .undecided)
        AppTelemetry.chooseSharing(.declined, in: defaults)
        #expect(AppTelemetry.sharingChoice(in: defaults) == .declined)
        AppTelemetry.chooseSharing(.allowed, in: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(AppTelemetry.sharingChoice(in: reopened) == .allowed)
    }

    @Test
    func createsOneInstallationIDPerDefaultsStore() throws {
        let firstSuite = "installation-test.\(UUID())"
        let secondSuite = "installation-test.\(UUID())"
        let first = try #require(UserDefaults(suiteName: firstSuite))
        let second = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }
        let id = AppTelemetry.deviceID(in: first)
        #expect(UUID(uuidString: id) != nil)
        let reopened = try #require(UserDefaults(suiteName: firstSuite))
        #expect(AppTelemetry.deviceID(in: reopened) == id)
        #expect(AppTelemetry.deviceID(in: second) != id)
    }

    @Test func formatsTheDiagnosticClipboardWithAnOptionalUserID() throws {
        let uid = try #require(UUID(uuidString: "A0B1C2D3-1074-4908-B6C0-96F36B31F36B"))
        #expect(AppTelemetry.formatSupportIdentifiers(deviceID: "sample", userID: nil) == "did: sample")
        #expect(AppTelemetry.formatSupportIdentifiers(deviceID: "sample", userID: uid)
                == "did: sample\nuid: a0b1c2d3-1074-4908-b6c0-96f36b31f36b")
    }

    @Test
    func sendsOnlyUnexpectedErrorsToSentry() {
        #expect(FailureReason.writeFailed.needsDiagnostic(for: .saveSolve))
        #expect(FailureReason.writeFailed.needsDiagnostic(for: .importDCTimer))
        #expect(FailureReason.decodeFailed.needsDiagnostic(for: .loadResults))
        #expect(FailureReason.engineFailed.needsDiagnostic(for: .generateScramble))
        #expect(!FailureReason.engineFailed.needsDiagnostic(for: .loadDiagram))
        #expect(!FailureReason.readFailed.needsDiagnostic(for: .importDCTimer))
        #expect(!FailureReason.invalidBackup.needsDiagnostic(for: .importDCTimer))
        #expect(!FailureReason.incompatibleBackup.needsDiagnostic(for: .importDCTimer))
        #expect(FailureReason.validationFailed.needsDiagnostic(for: .importDCTimer))
        #expect(FailureReason.webContentTerminated.needsDiagnostic(for: .renderDiagram))
        #expect(FailureReason.audioResourceMissing.needsDiagnostic(for: .playInspectionAudio))
        #expect(FailureReason.audioDecodeFailed.needsDiagnostic(for: .playInspectionAudio))
        #expect(!FailureReason.audioScheduleFailed.needsDiagnostic(for: .playInspectionAudio))
        let diskFull = CocoaError(.fileWriteOutOfSpace)
        #expect(FailureReason.writingResults(diskFull) == .diskFull)
        #expect(!FailureReason.writingResults(diskFull).needsDiagnostic(for: .saveSolve))
    }

    @Test
    func serializesTheSharedFailureSchema() {
        let failure = OperationFailure(operation: .renderDiagram, reason: .webContentTerminated, impact: .degraded)
        #expect(OperationFailure.eventName == "operation_failed")
        #expect(failure.fields == [
            "operation": "render_diagram",
            "reason": "web_content_terminated",
            "impact": "degraded"
        ])
    }

    @Test
    func addsTheInstalledBuildNumberToAnalyticsParameters() throws {
        let buildNumber = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        #expect(!buildNumber.isEmpty)
        let failure = OperationFailure(operation: .loadResults, reason: .readFailed, impact: .blocked)
        var expected = failure.fields
        expected["app_build"] = buildNumber
        #expect(AppTelemetry.analyticsParameters(failure.fields) as? [String: String] == expected)
    }

    @Test
    func discardsPerformanceMeasurementsFromPreviousConsent() {
        let start = ContinuousClock.now
        let measurement = AppTelemetry.PerformanceMeasurement(startedAt: start, consentGeneration: 1)
        let end = start.advanced(by: .milliseconds(42))
        #expect(measurement.duration(in: 1, endingAt: end) == .milliseconds(42))
        #expect(measurement.duration(in: 2, endingAt: end) == nil)
    }

    @Test
    func serializesTimerPerformanceWithNumericMilliseconds() {
        let launch = TimerPerformanceMetric.launchToTimerReady
        #expect(TimerPerformanceMetric.eventName == "operation_performance")
        let launchFields = launch.parameters(duration: .seconds(1) + .milliseconds(250))
        #expect(Set(launchFields.keys) == ["operation", "outcome", "duration_ms"])
        #expect(launchFields["operation"] as? String == "launch_to_timer_ready")
        #expect(launchFields["outcome"] as? String == "success")
        #expect(launchFields["duration_ms"] as? Double == 1_250)

        let preparation = TimerPerformanceMetric.scramblePreparation(
            trigger: .afterSolve, path: .prefetchPending, project: "333", projectChanged: false
        )
        let preparationFields = preparation.parameters(duration: .microseconds(500))
        #expect(Set(preparationFields.keys) == [
            "operation", "outcome", "duration_ms", "trigger", "preparation_path", "cache_hit",
            "project_changed", "scramble_project"
        ])
        #expect(preparationFields["operation"] as? String == "scramble_preparation")
        #expect(preparationFields["duration_ms"] as? Double == 0.5)
        #expect(preparationFields["trigger"] as? String == "after_solve")
        #expect(preparationFields["preparation_path"] as? String == "prefetch_pending")
        #expect(preparationFields["cache_hit"] as? String == "false")
        #expect(preparationFields["project_changed"] as? String == "false")
        #expect(preparationFields["scramble_project"] as? String == "event_333")

        let diagram = TimerPerformanceMetric.scrambleDiagram(.prefetchReady)
        let diagramFields = diagram.parameters(duration: .milliseconds(2))
        #expect(Set(diagramFields.keys) == ["operation", "outcome", "duration_ms", "preparation_path"])
        #expect(diagramFields["operation"] as? String == "scramble_diagram_ready")
        #expect(diagramFields["preparation_path"] as? String == "prefetch_ready")
    }

    @Test
    func serializesCacheHitsAndProjectChangesForScramblePreparation() {
        let cached = TimerPerformanceMetric.scramblePreparation(
            trigger: .manual, path: .prefetchReady, project: "222.cll", projectChanged: false
        ).parameters(duration: .zero)
        #expect(cached["cache_hit"] as? String == "true")
        #expect(cached["scramble_project"] as? String == "event_222.cll")

        let switched = TimerPerformanceMetric.scramblePreparation(
            trigger: .projectChange, path: .onDemand, project: "777", projectChanged: true
        ).parameters(duration: .zero)
        #expect(switched["cache_hit"] as? String == "false")
        #expect(switched["project_changed"] as? String == "true")
        #expect(switched["scramble_project"] as? String == "event_777")

        let unknown = TimerPerformanceMetric.scramblePreparation(
            trigger: .initial, path: .onDemand, project: "unknown", projectChanged: false
        ).parameters(duration: .zero)
        #expect(unknown["scramble_project"] as? String == "other")
    }

    @Test
    func serializesStatisticsAndCloudSyncPerformance() {
        let statistics = TimerPerformanceMetric.statisticsReady(trigger: .groupChange, solveCount: 100)
        let statisticsFields = statistics.parameters(duration: .milliseconds(15))
        #expect(statisticsFields["operation"] as? String == "statistics_ready")
        #expect(statisticsFields["trigger"] as? String == "group_change")
        #expect(statisticsFields["solve_count_bucket"] as? String == "100_to_999")

        let success = TimerPerformanceMetric.cloudSync(.init(
            phase: .initial, network: .wifi, localSolveCount: 99, remoteRecordCount: 10_000, failure: nil
        ))
        let successFields = success.parameters(duration: .seconds(2))
        #expect(successFields["operation"] as? String == "icloud_sync")
        #expect(successFields["sync_phase"] as? String == "initial")
        #expect(successFields["outcome"] as? String == "success")
        #expect(successFields["reason"] == nil)
        #expect(successFields["network_type"] as? String == "wifi")
        #expect(successFields["local_solve_count_bucket"] as? String == "1_to_99")
        #expect(successFields["remote_record_count_bucket"] as? String == "10000_or_more")

        let failure = TimerPerformanceMetric.cloudSync(.init(
            phase: .subsequent, network: .cellular, localSolveCount: 0,
            remoteRecordCount: nil, failure: .serviceUnavailable
        ))
        let failureFields = failure.parameters(duration: .seconds(1))
        #expect(failureFields["operation"] as? String == "icloud_sync")
        #expect(failureFields["sync_phase"] as? String == "subsequent")
        #expect(failureFields["outcome"] as? String == "failure")
        #expect(failureFields["reason"] as? String == "service_unavailable")
        #expect(failureFields["local_solve_count_bucket"] as? String == "empty")
        #expect(failureFields["remote_record_count_bucket"] as? String == "unknown")
    }

    @Test
    func retriesOnlyTheRequestedDiagramAndReportsTerminalFailureOnce() {
        var recovery = SVGView.RenderRecovery()
        recovery.request("current")
        #expect(recovery.failed("prefetched") == .ignore)
        #expect(recovery.failed("current") == .retry)
        recovery.displayed()
        #expect(recovery.failed("current") == .retry)
        #expect(recovery.failed("current") == .report)
        #expect(recovery.exhausted)
        #expect(recovery.failed("current") == .ignore)
        recovery.request("next")
        #expect(!recovery.exhausted)
        #expect(recovery.failed("current") == .ignore)
        #expect(recovery.failed("next") == .retry)
    }

    @Test
    func reportsRepeatedWebContentTerminationFromTheCurrentDiagram() throws {
        var captured: [FailureReason] = []
        let coordinator = SVGView.Coordinator { captured.append($0) }
        let container = UIView()
        coordinator.update(in: container, svg: "<svg xmlns=\"http://www.w3.org/2000/svg\"/>", nextSVG: nil)
        let webView = try #require(container.subviews.first as? WKWebView)
        coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(captured.isEmpty)
        coordinator.webViewWebContentProcessDidTerminate(webView)
        coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(captured == [.webContentTerminated])
        coordinator.stop()
    }

    @Test
    func reportsOneAudioFailurePerObservationAndStillAllowsTiming() async throws {
        try await withFixture { fixture in
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            fixture.defaults.set(InspectionVoice.female.rawValue, forKey: TimerModel.inspectionVoiceKey)
            var captured: [FailureReason] = []
            let model = TimerModel(storage: fixture.storage, defaults: fixture.defaults,
                                   loadInspectionPlayer: { _ in nil }, onInspectionAudioFailure: { captured.append($0) },
                                   generateScramble: { _ in Scramble(algorithm: "R", svg: "") })
            model.refresh()
            try await waitForGeneration(model)
            model.activateAccessibleTimer()
            #expect(model.inspectionStarted != nil)
            #expect(captured == [.audioResourceMissing])
            model.activateAccessibleTimer()
            #expect(model.started != nil)
            model.interrupt()
            #expect(captured == [.audioResourceMissing])
            model.activateAccessibleTimer()
            #expect(captured == [.audioResourceMissing, .audioResourceMissing])
        }
    }

    @Test
    func celebratesFirstValidResultOncePerSolveAndScopesRecordsToTheSelectedGroup() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            var context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 10_000, penalty: .dnf, context: context) == nil)
            #expect(model.lastSolveCelebration == nil)
            let first = try #require(model.lastSolve)
            #expect(model.setPenalty(nil, for: first.id))
            #expect(model.celebratedLastSolve == nil)
            #expect(model.takeAutomaticCelebration()?.achievements == [.init(kind: .first, result: "10.000")])
            #expect(model.celebratedLastSolve?.solveID == first.id)
            #expect(model.setPenalty(.dnf, for: first.id))
            #expect(model.lastSolveCelebration == nil)
            #expect(model.celebratedLastSolve == nil)
            #expect(model.setPenalty(nil, for: first.id))
            #expect(model.lastSolveCelebration?.solveID == first.id)
            #expect(model.takeAutomaticCelebration() == nil)
            #expect(model.celebratedLastSolve?.solveID == first.id)

            #expect(model.saveGroup(name: "Other group", isDefault: false))
            #expect(model.lastSolveCelebration == nil)
            #expect(model.celebratedLastSolve == nil)
            try await waitForGeneration(model)
            context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 30_000, penalty: .plusTwo, context: context) == nil)
            #expect(model.takeAutomaticCelebration()?.achievements == [.init(kind: .first, result: "32.000+")])
            let other = try #require(model.lastSolve)
            #expect(model.deleteSolve(other.id))
            #expect(model.lastSolveCelebration == nil)
        }
    }

    @Test
    func reevaluatesSingleAo5AndAo12AfterPenaltyWithoutReplayingAutomatically() async throws {
        try await withFixture { fixture in
            let history = [9.0, 10, 10, 10, 11, 11, 11, 11, 11, 11, 11, 11].enumerated().map { index, time in
                Solve(seconds: time, event: "333", scramble: "R U",
                      date: Date(timeIntervalSinceReferenceDate: Double(-index)))
            }
            try JSONEncoder().encode(history).write(to: fixture.storage)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            let context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 8_000, penalty: nil, context: context) == nil)
            let solve = try #require(model.lastSolve)
            #expect(model.takeAutomaticCelebration()?.achievements == [
                .init(kind: .single, result: "8.000"),
                .init(kind: .ao5, result: "9.666"),
                .init(kind: .ao12, result: "10.500")
            ])
            #expect(model.setPenalty(.plusTwo, for: solve.id))
            #expect(model.celebratedLastSolve?.achievements == [.init(kind: .ao12, result: "10.600")])
            #expect(model.takeAutomaticCelebration() == nil)
            #expect(model.setPenalty(.dnf, for: solve.id))
            #expect(model.lastSolveCelebration == nil)
            #expect(model.setPenalty(nil, for: solve.id))
            #expect(model.celebratedLastSolve?.achievements.count == 3)
            #expect(model.takeAutomaticCelebration() == nil)
            try await waitForGeneration(model)
            let nextContext = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 20_000, penalty: nil, context: nextContext) == nil)
            #expect(model.celebratedLastSolve == nil)
        }
    }

    @Test
    func includesFutureDatedHistoryAndMatchesTheDisplayedRollingWindows() async throws {
        try await withFixture { fixture in
            let tomorrow = Date().addingTimeInterval(86_400)
            let history = (0..<12).map { index in
                Solve(seconds: 8 + Double(index) * 0.25, event: "333", scramble: "R U",
                      date: tomorrow.addingTimeInterval(Double(-index)))
            }
            try JSONEncoder().encode(history).write(to: fixture.storage)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)

            var context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 10_000, penalty: nil, context: context) == nil)
            #expect(model.lastSolveCelebration == nil)

            try await waitForGeneration(model)
            context = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: 7_000, penalty: nil, context: context) == nil)
            #expect(model.takeAutomaticCelebration()?.achievements == [.init(kind: .single, result: "7.000")])
        }
    }

    @Test
    func firstAveragesAndDisplayedTiesDoNotQualify() {
        let history = (0..<11).map { _ in Solve(seconds: 10.0009, event: "333", scramble: "R U") }
        let solve = Solve(seconds: 10.0001, event: "333", scramble: "R U")
        #expect(SolveCelebration(solve: solve, history: Array(history.prefix(4))) == nil)
        #expect(SolveCelebration(solve: solve, history: history) == nil)
        let invalidBaseline = (0..<12).map { _ in
            Solve(seconds: 10, event: "333", scramble: "R U", penalty: .dnf)
        }
        #expect(SolveCelebration(solve: solve, history: invalidBaseline)?.achievements.map(\.kind) == [.first])
    }

    @Test
    func swipeDefaultsApplyOnlyWithoutAValidSavedAction() async throws {
        try await withFixture { fixture in
            let left = TimerSwipeDirection.left
            let right = TimerSwipeDirection.right
            #expect(left.action(in: fixture.defaults) == .none)
            #expect(right.action(in: fixture.defaults) == .none)

            fixture.defaults.set(TimerSwipeAction.none.rawValue, forKey: left.preferenceKey)
            fixture.defaults.set(TimerSwipeAction.manualEntry.rawValue, forKey: right.preferenceKey)
            #expect(left.action(in: fixture.defaults) == .none)
            #expect(right.action(in: fixture.defaults) == .manualEntry)

            fixture.defaults.set("unknown-action", forKey: right.preferenceKey)
            #expect(right.action(in: fixture.defaults) == .none)
        }
    }

    @Test
    func swipeDirectionRequiresClearHorizontalTravel() {
        #expect(TimerSwipeDirection(translation: CGSize(width: -70, height: 20)) == .left)
        #expect(TimerSwipeDirection(translation: CGSize(width: 70, height: -20)) == .right)
        #expect(TimerSwipeDirection(translation: CGSize(width: 43, height: 0)) == nil)
        #expect(TimerSwipeDirection(translation: CGSize(width: 60, height: 50)) == nil)
        #expect(TimerSwipeDirection(translation: CGSize(width: 0, height: -70)) == nil)
        #expect(TimerSwipeDirection(translation: CGSize(width: 0, height: 70)) == nil)
    }

    @Test
    func timerModeAllowsOneOffManualEntryOnlyWhileIdle() async throws {
        try await withFixture { fixture in
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            let context = try #require(model.manualSolveContext())

            model.press(.touch, delayTenths: 0)
            #expect(model.manualSolveContext() == nil)
            model.release(.touch)
            #expect(model.inspectionStarted != nil)
            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: nil, context: context) != nil)
            model.activateAccessibleTimer()
            #expect(model.started != nil)
            #expect(model.manualSolveContext() == nil)
            model.interrupt()

            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: nil, context: context) == nil)
            #expect(model.lastSolve?.resultText == "12.345")
            #expect(model.lastSolve?.scramble == context.scramble)
            #expect(model.usesInspection)
        }
    }

    @Test
    func manualTimeUsesLeftAlignedDigitsAndValidatesSeconds() {
        #expect(ManualSolveTime("0012345").milliseconds == 12_345)
        #expect(ManualSolveTime("01:02.345").milliseconds == 62_345)
        #expect(ManualSolveTime("99:59.999").milliseconds == ManualSolveTime.maximumMilliseconds)
        #expect(ManualSolveTime("0060").milliseconds == nil)
        #expect(ManualSolveTime("0012").milliseconds == 12_000)
        #expect(ManualSolveTime("00123").displayedDigits == "0012300")
        #expect(ManualSolveTime("").milliseconds == 0)
        #expect(ManualSolveTime("1").milliseconds == 600_000)
        var edited = ManualSolveTime("0012345")
        #expect(edited.insert("9", at: 5) == 6)
        #expect(edited.displayedDigits == "0012395")
        edited.clearDigit(at: 5)
        #expect(edited.displayedDigits == "0012305")
        #expect(TimerDisplay.wholeSeconds(.milliseconds(59_999)) == "59")
        #expect(TimerDisplay.wholeSeconds(.seconds(60)) == "1:00")
    }

    @Test
    func manualEntrySkipsInspectionAndSavesTheCurrentScramble() async throws {
        try await withFixture { fixture in
            fixture.defaults.set(SolveEntryMethod.manual.rawValue, forKey: TimerModel.entryMethodKey)
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            let context = try #require(model.manualSolveContext())
            model.press(.touch, delayTenths: 0)
            model.release(.touch)
            model.activateAccessibleTimer()
            #expect(model.started == nil)
            #expect(model.inspectionStarted == nil)
            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: .plusTwo, context: context) == nil)
            #expect(model.lastSolve?.resultText == "14.345+")
            #expect(model.lastSolve?.scramble == context.scramble)
            #expect(model.lastSolve?.groupID == context.groupID)
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm != context.scramble)
            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: nil, context: context) != nil)
            let next = try #require(model.manualSolveContext())
            #expect(model.saveManualSolve(milliseconds: nil, penalty: .dnf, context: next) == nil)
            #expect(model.lastSolve?.resultText == "DNF")
            let dnf = try #require(model.lastSolve)
            #expect(!dnf.allowsPenaltyChange)
            #expect(!model.setPenalty(.plusTwo, for: dnf.id))
            #expect(!model.setPenalty(nil, for: dnf.id))
            #expect(!model.togglePenalty(.dnf, for: dnf.id))
            #expect(fixture.model().solves.first?.penalty == .dnf)
            #expect(fixture.model().solves.count == 2)
        }
    }

    @Test
    func failedManualSaveKeepsTheScrambleForRetry() async throws {
        try await withFixture { fixture in
            fixture.defaults.set(SolveEntryMethod.manual.rawValue, forKey: TimerModel.entryMethodKey)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            let context = try #require(model.manualSolveContext())
            try FileManager.default.createDirectory(at: fixture.storage, withIntermediateDirectories: false)
            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: nil, context: context) != nil)
            #expect(model.solves.isEmpty)
            #expect(model.scramble?.algorithm == context.scramble)
            try FileManager.default.removeItem(at: fixture.storage)
            #expect(model.saveManualSolve(milliseconds: 12_345, penalty: nil, context: context) == nil)
            #expect(model.solves.count == 1)
        }
    }

    @Test
    func trainingHintsMatchThePracticedStage() async throws {
        #expect(AssistMethod.available(for: "333.easy_cross") == [.cross])
        #expect(AssistMethod.available(for: "333.easy_xcross") == [.xcross])
        #expect(AssistMethod.available(for: "333.f2l") == [.cfopF2L])
        #expect(AssistMethod.available(for: "333.pll").isEmpty)
        #expect(AssistMethod.available(for: "222.cll").isEmpty)

        for (event, method) in [("333.easy_cross", AssistMethod.cross), ("333.easy_xcross", .xcross)] {
            let solutions = try await Engine.assistSolutions(event: event, method: method, algorithm: "R U F")
            #expect(solutions.map(\.target) == ["D"])
            #expect(solutions.first?.setupRotation == "")
        }

        let scramble = "L' B U D F2 D2 B D' R B2 U B2 D' L2 U' R2 B2 D' L2 B2 D'"
        let f2l = try await Engine.assistSolutions(event: "333.f2l", method: .cfopF2L, algorithm: scramble)
        #expect(f2l.map(\.target) == ["F2L-1", "F2L-2", "F2L-3", "F2L-4"])

        let standard = try await Engine.assistSolutions(event: "333", method: .cfopF2L, algorithm: scramble)
        #expect(standard.first?.target == "Cross")
        #expect(standard.first?.solution == "")
    }

    @Test
    func formulaHintPreferencesAreScopedToEventGroupAndMethod() async throws {
        try await withFixture { fixture in
            let preferences = AssistPreferences(event: "333", groupID: "practice", defaults: fixture.defaults)
            let otherGroup = AssistPreferences(event: "333", groupID: "speed", defaults: fixture.defaults)
            let otherEvent = AssistPreferences(event: "333oh", groupID: "practice", defaults: fixture.defaults)
            let methods = AssistMethod.available(for: "333")
            preferences.saveMethod(.xcross)
            #expect(preferences.selectedMethod(from: methods) == .xcross)
            #expect(preferences.selectedMethod(from: [.cross]) == .cross)
            #expect(otherGroup.selectedMethod(from: methods) == .cross)
            #expect(otherEvent.selectedMethod(from: methods) == .cross)

            func solution(_ target: String, formula: String = "R") -> AssistSolution {
                AssistSolution(target: target, targetLabel: target, setupRotation: "", solution: formula, metric: nil)
            }
            preferences.saveOrder([solution("U"), solution("D"), solution("L")], for: .xcross)
            let next = [solution("D"), solution("U", formula: "F"), solution("R")]
            let restored = preferences.ordered(next, for: .xcross)
            #expect(restored.map(\.id) == ["U", "D", "R"])
            #expect(restored.first?.solution == "F")
            #expect(preferences.ordered(next, for: .cross).map(\.id) == ["D", "U", "R"])
            #expect(otherGroup.ordered(next, for: .xcross).map(\.id) == ["D", "U", "R"])
            #expect(otherEvent.ordered(next, for: .xcross).map(\.id) == ["D", "U", "R"])

            preferences.saveOrder([solution("U"), solution("D")], for: .cfopF2L)
            #expect(preferences.ordered(next, for: .cfopF2L).map(\.id) == ["D", "U", "R"])
        }
    }

    @Test(arguments: [0, 1])
    func readyPromptFeedbackFiresWhileHolding(delayTenths: Int) async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)

            var feedbackCount = 0
            model.press(.touch, delayTenths: delayTenths) {
                #expect(model.showsReadyFeedback)
                #expect(model.started == nil)
                feedbackCount += 1
            }

            try await waitUntil { model.showsReadyFeedback }
            #expect(feedbackCount == 1)
            model.release(.touch)
            #expect(model.started != nil)
            #expect(feedbackCount == 1)
        }
    }

    @Test(arguments: [14_999, 15_000, 16_999, 17_000])
    func inspectionUsesReleaseTimeAndPersistsPenalty(milliseconds: Int) async throws {
        try await withFixture { fixture in
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            var now = ContinuousClock.now
            let model = fixture.model(now: { now })
            model.refresh()
            try await waitForGeneration(model)

            model.press(.keyboard, delayTenths: 20)
            #expect(model.isReady)
            #expect(!model.isTouchReady)
            model.cancelPress(.keyboard)

            model.press(.touch, delayTenths: 20)
            #expect(model.isReady)
            #expect(model.isTouchReady)
            #expect(model.inspectionStarted == nil)
            model.release(.touch)
            let inspectionStart = try #require(model.inspectionStarted)
            #expect(inspectionStart == now)
            #expect(model.started == nil)

            model.press(.touch, delayTenths: 0)
            model.cancelPress(.touch)
            model.release(.touch)
            #expect(model.inspectionStarted == inspectionStart)

            now += .milliseconds(milliseconds)
            model.press(.touch, delayTenths: 20)
            #expect(model.isReady)
            model.release(.touch)
            #expect(model.started == now)
            #expect(model.inspectionStarted == nil)

            now += .seconds(3)
            model.press(.touch, delayTenths: 2)
            let solve = try #require(model.lastSolve)
            let expected: SolvePenalty? = switch milliseconds {
            case 15_000, 16_999: .plusTwo
            case 17_000: .dnf
            default: nil
            }
            #expect(solve.seconds == 3)
            #expect(solve.penalty == expected)
            #expect(fixture.model().solves == [solve])
        }
    }

    @Test func inspectionRequiresOptInForTrainingAndExcludesBlindfoldedEvents() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            #expect(!model.usesInspection)
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            #expect(model.usesInspection)

            for event in ["333bld", "444bld", "555bld"] {
                model.standardEvent = event
                #expect(!model.usesInspection)
            }

            model.mode = .training
            #expect(!model.usesInspection)
            fixture.defaults.set(true, forKey: TimerModel.trainingInspectionKey)
            #expect(model.usesInspection)
        }
    }

    @Test(arguments: [TimerInput.touch, .keyboard])
    func readyFeedbackWaitsWithoutDelayingRelease(_ input: TimerInput) async throws {
        try await withFixture { fixture in
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)

            model.press(input, delayTenths: 20)
            #expect(model.isReady)
            #expect(!model.showsReadyFeedback)
            model.release(input)
            #expect(model.inspectionStarted != nil)
            #expect(!model.showsReadyFeedback)

            model.press(input, delayTenths: 20)
            #expect(model.isReady)
            #expect(!model.showsReadyFeedback)
            try await waitUntil { model.showsReadyFeedback }
            model.release(input)
            #expect(model.started != nil)
            #expect(!model.showsReadyFeedback)
        }
    }

    @Test func holdReleaseAndStopPersistTheOriginalScrambleAndExactTime() async throws {
        try await withFixture { fixture in
            var now = ContinuousClock.now
            let model = fixture.model(now: { now })
            model.refresh()
            try await waitForGeneration(model)
            let original = try #require(model.scramble)
            try await waitForPrefetch(model)
            let prefetched = try #require(model.nextScramble)
            #expect(prefetched.algorithm != original.algorithm)
            #expect(model.saveGroup(name: "Practice", isDefault: false))
            let group = try #require(model.currentGroup)

            model.press(.touch, delayTenths: 2)
            now += .milliseconds(199)
            model.release(.touch)
            #expect(model.started == nil)

            model.press(.keyboard, delayTenths: 2)
            #expect(!model.isReady)
            #expect(!model.isTouchReady)
            now += .milliseconds(200)
            model.release(.touch)
            #expect(model.started == nil)
            model.release(.keyboard)
            #expect(model.started == now)
            now += .milliseconds(12_345)
            model.press(.touch, delayTenths: 2)
            #expect(model.started == nil)
            let solve = try #require(model.lastSolve)
            #expect(solve.seconds == 12.345)
            #expect(solve.event == "333")
            #expect(solve.groupID == group.id)
            #expect(solve.scramble == original.algorithm)
            #expect(model.scramble?.algorithm == prefetched.algorithm)
            #expect(model.scramble?.svg == prefetched.svg)
            try await waitForPrefetch(model)
            #expect(model.nextScramble?.algorithm != prefetched.algorithm)
            #expect(fixture.model().solves == [solve])
        }
    }

    @Test func interruptedAttemptAndCancelledHoldDoNotSave() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)

            model.press(.touch, delayTenths: 0)
            #expect(model.isReady)
            model.cancelPress(.touch)
            model.release(.touch)
            #expect(!model.isReady)
            #expect(model.started == nil)

            model.activateAccessibleTimer()
            #expect(model.started != nil)
            try await waitForPrefetch(model)
            let prefetched = try #require(model.nextScramble)
            model.interrupt()
            #expect(model.started == nil)
            #expect(model.nextScramble?.algorithm == prefetched.algorithm)
            #expect(model.error != nil)
            #expect(model.solves.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
        }
    }

    @Test func eventSwitchDiscardsPrefetchAndRestoresEachModeSelection() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            model.activateAccessibleTimer()
            try await waitForPrefetch(model)
            model.activateAccessibleTimer()

            model.eventSelection = "222"
            model.refresh()
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm.hasPrefix("222:") == true)
            try await waitForPrefetch(model)
            #expect(model.nextScramble?.algorithm.hasPrefix("222:") == true)
            #expect(model.lastSolve == nil)

            model.mode = .training
            model.eventSelection = "333.oll"
            model.refresh()
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm.hasPrefix("333.oll:") == true)
            #expect(model.currentGroup?.id == "default:333.oll")

            let reopened = fixture.model()
            #expect(reopened.mode == .training)
            #expect(reopened.event == "333.oll")
            reopened.mode = .standard
            #expect(reopened.event == "222")
        }
    }

    @Test func legacySolvesSurviveGroupEditsMovesAndPenalties() async throws {
        try await withFixture { fixture in
            let first = Solve(seconds: 13.25, event: "333", scramble: "R U", date: Date(timeIntervalSince1970: 100))
            let second = Solve(seconds: 15, event: "333", scramble: "F U", date: Date(timeIntervalSince1970: 90))
            let unrelated = Solve(seconds: 8, event: "222", scramble: "R2", date: Date(timeIntervalSince1970: 80))
            try JSONEncoder().encode([first, second, unrelated]).write(to: fixture.storage)
            var events: [ProductEvent] = []
            let model = fixture.model(recordProductEvent: { events.append($0) })
            let initial = try #require(model.currentGroup)
            #expect(initial.id == "default:333")
            #expect(model.groupSolves == [first, second])

            #expect(!model.saveGroup(name: "Line\nbreak", isDefault: false))
            #expect(model.saveGroup(name: "  Practice  ", isDefault: true))
            let practice = try #require(model.currentGroup)
            #expect(practice.name == "Practice")
            #expect(model.eventGroups.filter(\.isDefault).map(\.id) == [practice.id])
            #expect(!model.deleteGroup(practice.id))
            #expect(!model.reorderGroups([practice.id, practice.id]))
            #expect(model.moveGroup(practice.id, to: initial.id))
            model.selectGroup(initial.id)
            #expect(!model.moveSolves([first.id, unrelated.id], toGroup: practice.id))
            #expect(!model.moveSolve(first.id, toGroup: "default:222"))
            #expect(events == [.featureUsed(.groupCreated), .featureUsed(.groupReordered)])
            #expect(model.moveSolves([first.id, second.id], toGroup: practice.id))
            #expect(events.last == .featureUsed(.resultsMoved(.batch)))
            #expect(model.groupSolves.isEmpty)

            #expect(model.togglePenalty(.plusTwo, for: first.id))
            #expect(model.solves.first?.resultSeconds == 15.25)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == nil)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == first.seconds)

            let reopened = fixture.model(recordProductEvent: { events.append($0) })
            #expect(reopened.eventGroups.map(\.id) == [practice.id, initial.id])
            #expect(reopened.groupSolves.map(\.id) == [first.id, second.id])
            #expect(reopened.groupSolves.first?.scramble == first.scramble)
            #expect(reopened.groupSolves.first?.date == first.date)
            #expect(reopened.moveSolve(first.id, toGroup: initial.id))
            #expect(events.last == .featureUsed(.resultsMoved(.single)))
            #expect(reopened.deleteSolves([second.id]))
            #expect(reopened.saveGroup(id: initial.id, name: "Restored", isDefault: true))
            reopened.selectGroup(practice.id)
            #expect(reopened.deleteGroup(practice.id))
            #expect(reopened.currentGroup?.id == initial.id)
            #expect(fixture.model().solves.map(\.id) == [first.id, unrelated.id])
        }
    }

    @Test func groupDeletionRemovesOnlyItsOwnSolves() async throws {
        try await withFixture { fixture in
            let keep = Solve(seconds: 10, event: "333", scramble: "R")
            let remove = Solve(seconds: 11, event: "333", scramble: "U")
            try JSONEncoder().encode([keep, remove]).write(to: fixture.storage)
            let model = fixture.model()
            #expect(model.saveGroup(name: "Disposable", isDefault: false))
            let group = try #require(model.currentGroup)
            #expect(model.moveSolve(remove.id, toGroup: group.id))
            #expect(model.deleteGroup(group.id))
            #expect(model.currentGroup?.id == "default:333")
            #expect(fixture.model().solves == [keep])
        }
    }

    @Test func failedStorageWriteLeavesGroupAndSolveEditsUnapplied() async throws {
        try await withFixture { fixture in
            let solve = Solve(seconds: 10, event: "333", scramble: "R")
            try JSONEncoder().encode([solve]).write(to: fixture.storage)
            let model = fixture.model()
            try FileManager.default.removeItem(at: fixture.directory)
            #expect(!model.setPenalty(.plusTwo, for: solve.id))
            #expect(!model.deleteSolve(solve.id))
            #expect(!model.saveGroup(name: "Practice", isDefault: true))
            #expect(model.error != nil)
            #expect(model.solves == [solve])
            #expect(model.eventGroups.map(\.id) == ["default:333"])
        }
    }

    @Test func corruptHistoryReportsAReadError() async throws {
        try await withFixture { fixture in
            try Data("{invalid JSON".utf8).write(to: fixture.storage)
            let model = fixture.model()
            #expect(model.error != nil)
            #expect(model.solves.isEmpty)
            #expect(model.currentGroup?.id == "default:333")
        }
    }

    @Test func timerDisplayTruncatesAtMillisecondsAndFormatsBoundaries() {
        #expect(TimerModel.format(-1) == "0.000")
        #expect(TimerModel.format(59.9999) == "59.999")
        #expect(TimerModel.format(60.001) == "1:00.001")
        #expect(TimerModel.format(3_605.125) == "1:00:05.125")
        #expect(TimerModel.format(35_999.999) == "9:59:59.999")
        #expect(TimerModel.format(36_000) == "9:59:59.999")
        let penalized = Solve(seconds: 35_999, event: "333", scramble: "R U", penalty: .plusTwo)
        #expect(penalized.resultText == "9:59:59.999+")
    }

    private func waitForGeneration(_ model: TimerModel) async throws {
        try await waitUntil { !model.busy }
        _ = try #require(model.scramble)
    }

    private func waitForPrefetch(_ model: TimerModel) async throws {
        try await waitUntil { model.nextScramble != nil }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Scramble generation did not reach the expected state")
    }

    @Test func readsDCTimerBackupIncludingTheDefaultSessionAndPenalties() async throws {
        try await withFixture { fixture in
            let url = fixture.directory.appending(path: "spdcube.sqlite")
            try makeDatabase(url, sql: """
                CREATE TABLE sessiontb (rowid integer, name text, sorting integer);
                CREATE TABLE resulttb (id integer, sesid integer, rest integer, resp integer, scr text, date text, note text);
                INSERT INTO sessiontb VALUES (1, 'Practice', 1), (2, 'Empty', 2);
                INSERT INTO resulttb VALUES
                    (1, 0, 12345, 0, 'R U', '2024-02-02 11:12:10', NULL),
                    (2, 0, 12001, 1, 'R U2', '2024-02-02 11:12:11', NULL),
                    (3, 1, 14800, 2, 'U R', '2024-02-02 11:12:12', NULL);
                """)
            let original = try Data(contentsOf: url)
            let timezone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            let backup = try DCTimerBackup.read(url, timeZone: timezone)
            #expect(backup.sessions.map(\.id) == [0, 1, 2])
            #expect(backup.sessions.map { $0.entries.count } == [2, 1, 0])
            #expect(backup.sessions[1].name == "Practice")
            let plusTwo = backup.sessions[0].entries[1]
            #expect(plusTwo.milliseconds == 12_001)
            #expect(plusTwo.scramble == "R U2")
            #expect(plusTwo.penalty == .plusTwo)
            #expect(plusTwo.date == ISO8601DateFormatter().date(from: "2024-02-02T03:12:11Z"))
            #expect(backup.sessions[0].entries[0].penalty == nil)
            #expect(backup.sessions[1].entries[0].penalty == .dnf)
            #expect(try Data(contentsOf: url) == original)
            #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
        }
    }

    @Test func plansDCTimerImportWithClockConversionAndSeparateSkipReasons() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
            #expect(plan.compatibilityFailure == nil)
            let clock = try #require(plan.sessions.first { $0.id == 1 })
            #expect(clock.event == "clock")
            #expect(clock.converted == 1)
            #expect(clock.skipped == 1)
            let solve = try #require(clock.solves.first)
            #expect(solve.scramble == "UR3+ ALL0+ y2 ALL0+")
            #expect(solve.seconds == 12.001)
            #expect(solve.resultSeconds == 14.001)
            #expect(clock.solves.count == 1)
            let relay = try #require(plan.sessions.first { $0.id == 2 })
            #expect(relay.name == "2-7")
            #expect(relay.event == nil)
            #expect(relay.skipped == 1)
            let unknown = try #require(plan.sessions.first { $0.id == 3 })
            #expect(unknown.event == nil)
            #expect(unknown.skipped == 1)
        }
    }

    @Test func classifiesDCTimerBackupsWithNoCompatibleResults() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let rejectedScrambles = try DCTimerImportPlan(backup: backup) { _, _ in false }
            #expect(rejectedScrambles.compatibilityFailure == .incompatibleBackup)

            let unsupportedGroups = DCTimerBackup(sessions: backup.sessions.filter { $0.id == 2 || $0.id == 3 })
            let unsupportedPlan = try DCTimerImportPlan(backup: unsupportedGroups, validate: Engine.acceptsImportedScramble)
            #expect(!unsupportedPlan.sessions.isEmpty)
            #expect(unsupportedPlan.compatibilityFailure == .incompatibleBackup)
        }
    }

    @Test func separatesUnexpectedDCTimerValidationErrorsFromInvalidScrambles() async throws {
        struct InternalEngineError: Error {}
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            #expect(try !Engine.acceptsImportedScramble(event: "333", algorithm: "invalid"))
            #expect(throws: DCTimerImportPlan.ValidationFailure.self) {
                try DCTimerImportPlan(backup: backup) { _, _ in throw InternalEngineError() }
            }
            #expect(throws: CancellationError.self) {
                try DCTimerImportPlan(backup: backup) { _, _ in throw CancellationError() }
            }
        }
    }

    @Test func importsDCTimerToEitherDestinationAndDeduplicatesAfterReload() async throws {
        for destination in DCTimerImportDestination.allCases {
            try await withFixture { fixture in
                let backup = try dctimerImportFixture(in: fixture.directory)
                let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
                let original = Solve(seconds: 7, event: "333", scramble: "U2")
                try JSONEncoder().encode([original]).write(to: fixture.storage)
                var events: [ProductEvent] = []
                let model = fixture.model(recordProductEvent: { events.append($0) })
                #expect(try model.importDCTimer(plan, destination: destination, language: .english) == 2)
                #expect(events == [.dctimerImportCompleted])

                let reopened = fixture.model(recordProductEvent: { events.append($0) })
                #expect(reopened.solves.count == 3)
                #expect(reopened.solves.contains(original))
                let clock = try #require(reopened.solves.first { $0.event == "clock" })
                let group = try #require(reopened.groups.first { $0.id == clock.groupID })
                #expect(group.isDefault == (destination == .defaultGroups))
                if destination == .originalSessions { #expect(group.name == "Clock practice") }

                let reread = try DCTimerBackup.read(fixture.directory.appending(path: "spdcube.sqlite"))
                let newPlan = try DCTimerImportPlan(backup: reread, validate: Engine.acceptsImportedScramble)
                #expect(newPlan.compatibilityFailure == nil)
                let otherDestination: DCTimerImportDestination = destination == .defaultGroups ? .originalSessions : .defaultGroups
                #expect(try reopened.importDCTimer(newPlan, destination: otherDestination, language: .english) == 0)
                #expect(events == [.dctimerImportCompleted])
                #expect(reopened.solves.count == 3)
            }
        }
    }

    @Test func importExcludesWholeSessionsAndLeavesTheirResultsAvailableForLater() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
            let model = fixture.model()
            #expect(try model.importDCTimer(plan, destination: .originalSessions, language: .english,
                                           excluding: [0, 1]) == 0)
            #expect(try model.importDCTimer(plan, destination: .originalSessions, language: .english,
                                           excluding: [1]) == 1)
            let reopened = fixture.model()
            #expect(reopened.solves.map(\.event) == ["333"])
            #expect(!reopened.groups.contains { $0.name == "Clock practice" })
            #expect(try reopened.importDCTimer(plan, destination: .defaultGroups, language: .english) == 1)
            #expect(Set(reopened.solves.map(\.event)) == ["333", "clock"])
        }
    }

    @Test func undoRemovesOnlyRemainingResultsFromTheLatestImportAfterReload() async throws {
        try await withFixture { fixture in
            let firstBackup = try dctimerImportFixture(in: fixture.directory)
            let firstPlan = try DCTimerImportPlan(backup: firstBackup, validate: Engine.acceptsImportedScramble)
            let existing = Solve(seconds: 7, event: "333", scramble: "U2")
            try JSONEncoder().encode([existing]).write(to: fixture.storage)
            let model = fixture.model()
            #expect(model.lastImportCount == 0)
            #expect(try model.importDCTimer(firstPlan, destination: .defaultGroups, language: .english) == 2)
            let olderIDs = Set(model.solves.map(\.id))

            let source = fixture.directory.appending(path: "spdcube.sqlite")
            try makeDatabase(source, sql: """
                INSERT INTO resulttb VALUES
                    (6, 0, 12006, 0, 'F R', '2024-02-02 11:12:15'),
                    (7, 0, 12007, 0, 'F U', '2024-02-02 11:12:16');
                """)
            let latest = try DCTimerImportPlan(backup: DCTimerBackup.read(source),
                                               validate: Engine.acceptsImportedScramble)
            #expect(try model.importDCTimer(latest, destination: .originalSessions, language: .english) == 2)
            #expect(try model.importDCTimer(firstPlan, destination: .defaultGroups, language: .english) == 0)
            let added = model.solves.filter { !olderIDs.contains($0.id) }
            try #require(added.count == 2)
            #expect(model.moveSolve(added[0].id, toGroup: SolveGroup.initialID(for: "333")))
            #expect(model.deleteSolve(added[1].id))

            var events: [ProductEvent] = []
            let reopened = fixture.model(recordProductEvent: { events.append($0) })
            #expect(reopened.lastImportCount == 1)
            #expect(reopened.undoLastImport() == 1)
            #expect(reopened.lastImportCount == 0)
            #expect(Set(reopened.solves.map(\.id)) == olderIDs)
            #expect(reopened.groups.contains { $0.id == added[1].groupID })
            #expect(reopened.undoLastImport() == nil)
            #expect(events == [.featureUsed(.dctimerImportUndone)])
            let reloaded = fixture.model()
            #expect(reloaded.lastImportCount == 0)
            #expect(reloaded.solves == reopened.solves)
        }
    }

    @Test func undoRemainsAvailableWhenTheWriteFails() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
            let model = fixture.model()
            #expect(try model.importDCTimer(plan, destination: .defaultGroups, language: .english) == 2)
            let results = model.solves
            try FileManager.default.removeItem(at: fixture.directory)
            #expect(model.undoLastImport() == nil)
            #expect(model.lastImportCount == 2)
            #expect(model.solves == results)
            #expect(model.error != nil)
        }
    }

    @Test func clearingAllResultsAcrossGroupsPreservesGroupsAndClearsUndo() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
            let model = fixture.model()
            let importedAt = Date(timeIntervalSince1970: 1_700_000_000)
            #expect(try model.importDCTimer(plan, destination: .originalSessions, language: .english,
                                           importedAt: importedAt) == 2)
            #expect(fixture.model().lastImportDate == importedAt)
            let idsByGroup = model.solveIDsByGroup
            #expect(idsByGroup.count == 2)
            let clock = try #require(model.solves.first { $0.event == "clock" })
            let clockGroup = try #require(clock.groupID)
            #expect(model.deleteSolves(try #require(idsByGroup[clockGroup])))
            #expect(model.solves.map(\.event) == ["333"])
            #expect(fixture.model().lastImportDate == importedAt)
            let groupIDs = model.groups.map(\.id)
            #expect(model.deleteSolves(Set(model.solves.map(\.id))))
            #expect(model.lastImportCount == 0)
            let reopened = fixture.model()
            #expect(reopened.lastImportCount == 0)
            #expect(reopened.lastImportDate == nil)
            #expect(reopened.solves.isEmpty)
            #expect(reopened.groups.map(\.id) == groupIDs)
        }
    }

    @Test func GroupSavePreservesUnreadableResults() async throws {
        try await withFixture { fixture in
            let bytes = Data("unreadable".utf8)
            try bytes.write(to: fixture.storage)
            let model = fixture.model()
            model.error = nil

            #expect(!model.saveGroup(name: "Practice", isDefault: false))
            #expect(model.error != nil)
            #expect(!model.eventGroups.contains { $0.name == "Practice" })
            #expect(try Data(contentsOf: fixture.storage) == bytes)
        }
    }

    @Test func DCTimerImportPreservesUnreadableCubeginStorage() async throws {
        try await withFixture { fixture in
            let backup = try dctimerImportFixture(in: fixture.directory)
            let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
            let bytes = Data("unreadable".utf8)
            try bytes.write(to: fixture.storage)
            let model = fixture.model()
            #expect(throws: CocoaError.self) {
                try model.importDCTimer(plan, destination: .originalSessions, language: .english)
            }
            #expect(model.solves.isEmpty)
            #expect(try Data(contentsOf: fixture.storage) == bytes)
        }
    }

    private func dctimerImportFixture(in directory: URL) throws -> DCTimerBackup {
        let url = directory.appending(path: "spdcube.sqlite")
        try makeDatabase(url, sql: """
            CREATE TABLE sessiontb (rowid integer, name text);
            CREATE TABLE scrtypetb (sesid integer, type integer);
            CREATE TABLE resulttb (id integer, sesid integer, rest integer, resp integer, scr text, date text);
            INSERT INTO sessiontb VALUES (1, 'Clock practice'), (2, '2-7'), (3, 'Unknown');
            INSERT INTO scrtypetb VALUES (0, -32), (1, -21), (2, 32), (3, 1000);
            INSERT INTO resulttb VALUES
                (1, 0, 12000, 0, 'R U', '2024-02-02 11:12:10'),
                (2, 1, 12001, 1, 'UR3+ ALL0+ y2 ALL0+ UR DL', '2024-02-02 11:12:11'),
                (3, 1, 12002, 0, 'R U', '2024-02-02 11:12:12'),
                (4, 2, 12003, 0, 'R U', '2024-02-02 11:12:13'),
                (5, 3, 12004, 0, 'R U', '2024-02-02 11:12:14');
            """)
        return try DCTimerBackup.read(url)
    }

    @Test func rejectsUnrelatedDatabaseAndInvalidDCTimerRows() async throws {
        try await withFixture { fixture in
            let url = fixture.directory.appending(path: "other.sqlite")
            try makeDatabase(url, sql: "CREATE TABLE unrelated (id integer)")
            #expect(throws: DCTimerBackup.Failure.invalidBackup) { try DCTimerBackup.read(url) }
            try makeDatabase(url, sql: """
                CREATE TABLE sessiontb (rowid integer, name text);
                CREATE TABLE resulttb (id integer, sesid integer, rest integer, resp integer, scr text, date text);
                INSERT INTO resulttb VALUES (0, 0, 1000, 7, 'R', '2024-01-01 00:00:00');
                """)
            #expect(throws: DCTimerBackup.Failure.invalidResult) { try DCTimerBackup.read(url) }
        }
    }

    private func makeDatabase(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        let openStatus = sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        try #require(openStatus == SQLITE_OK)
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func withFixture(_ body: @MainActor (Fixture) async throws -> Void) async throws {
        let name = "CubeginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(Fixture(directory: directory, defaults: defaults))
    }

    private struct Fixture {
        let directory: URL
        let defaults: UserDefaults
        var storage: URL { directory.appending(path: "solves.json") }

        @MainActor func model(now: @escaping () -> ContinuousClock.Instant = { .now },
                             recordProductEvent: @escaping @MainActor (ProductEvent) -> Void = { _ in }) -> TimerModel {
            let generator = ScrambleGenerator()
            return TimerModel(storage: storage, defaults: defaults, now: now, recordProductEvent: recordProductEvent, generateScramble: { event in
                await generator.generate(event)
            })
        }
    }

    private actor ScrambleGenerator {
        private var count = 0

        func generate(_ event: String) -> Scramble {
            count += 1
            return Scramble(algorithm: "\(event):\(count)", svg: "<svg id=\"\(count)\"/>")
        }
    }
}
