import Foundation
import SQLite3
import Testing
@testable import CubeginApp

@MainActor
struct TimerModelTests {
    @Test(arguments: [14_999, 15_000, 16_999, 17_000])
    func inspectionUsesReleaseTimeAndPersistsPenalty(milliseconds: Int) async throws {
        try await withFixture { fixture in
            fixture.defaults.set(true, forKey: TimerModel.inspectionKey)
            var now = ContinuousClock.now
            let model = fixture.model(now: { now })
            model.refresh()
            try await waitForGeneration(model)

            model.press(.touch, delayTenths: 20)
            #expect(model.isReady)
            #expect(model.inspectionStarted == nil)
            model.release(.touch)
            let inspectionStart = try #require(model.inspectionStarted)
            #expect(inspectionStart == now)
            #expect(model.started == nil)

            model.press(.touch, delayTenths: 0)
            model.cancelPress(.touch)
            model.release(.touch)
            #expect(model.inspectionStarted == inspectionStart)

            now += .milliseconds(milliseconds - 200)
            model.press(.touch, delayTenths: 2)
            now += .milliseconds(200)
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

    @Test func holdReleaseAndStopPersistTheOriginalScrambleAndExactTime() async throws {
        try await withFixture { fixture in
            var now = ContinuousClock.now
            let model = fixture.model(now: { now })
            model.refresh()
            try await waitForGeneration(model)
            let original = try #require(model.scramble)
            #expect(model.saveGroup(name: "Practice", isDefault: false))
            let group = try #require(model.currentGroup)

            model.press(.touch, delayTenths: 2)
            now += .milliseconds(199)
            model.release(.touch)
            #expect(model.started == nil)

            model.press(.keyboard, delayTenths: 2)
            now += .milliseconds(200)
            model.release(.touch)
            #expect(model.started == nil)
            model.release(.keyboard)
            #expect(model.started == now)
            try await waitForPrefetch(model)
            let prefetched = try #require(model.nextScramble)
            #expect(prefetched.algorithm != original.algorithm)

            now += .milliseconds(12_345)
            model.press(.touch, delayTenths: 2)
            #expect(model.started == nil)
            let solve = try #require(model.lastSolve)
            #expect(solve.seconds == 12.345)
            #expect(solve.event == "333")
            #expect(solve.groupID == group.id)
            #expect(solve.scramble == original.algorithm)
            #expect(model.scramble?.algorithm == prefetched.algorithm)
            #expect(model.nextScramble == nil)
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
            model.interrupt()
            #expect(model.started == nil)
            #expect(model.nextScramble == nil)
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
            #expect(model.lastSolve == nil)

            model.mode = .training
            model.eventSelection = "333.oll"
            model.refresh()
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm.hasPrefix("333.oll:") == true)
            #expect(model.currentGroup?.id == "default:333.oll")

            let reopened = fixture.model()
            #expect(reopened.mode == .standard)
            #expect(reopened.event == "222")
            reopened.mode = .training
            #expect(reopened.event == "333.oll")
        }
    }

    @Test func legacySolvesSurviveGroupEditsMovesAndPenalties() async throws {
        try await withFixture { fixture in
            let first = Solve(seconds: 13.25, event: "333", scramble: "R U", date: Date(timeIntervalSince1970: 100))
            let second = Solve(seconds: 15, event: "333", scramble: "F U", date: Date(timeIntervalSince1970: 90))
            let unrelated = Solve(seconds: 8, event: "222", scramble: "R2", date: Date(timeIntervalSince1970: 80))
            try JSONEncoder().encode([first, second, unrelated]).write(to: fixture.storage)
            let model = fixture.model()
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
            #expect(model.moveSolves([first.id, second.id], toGroup: practice.id))
            #expect(model.groupSolves.isEmpty)

            #expect(model.togglePenalty(.plusTwo, for: first.id))
            #expect(model.solves.first?.resultSeconds == 15.25)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == nil)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == first.seconds)

            let reopened = fixture.model()
            #expect(reopened.eventGroups.map(\.id) == [practice.id, initial.id])
            #expect(reopened.groupSolves.map(\.id) == [first.id, second.id])
            #expect(reopened.groupSolves.first?.scramble == first.scramble)
            #expect(reopened.groupSolves.first?.date == first.date)
            #expect(reopened.moveSolve(first.id, toGroup: initial.id))
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

    @Test func importsDCTimerToEitherDestinationAndDeduplicatesAfterReload() async throws {
        for destination in DCTimerImportDestination.allCases {
            try await withFixture { fixture in
                let backup = try dctimerImportFixture(in: fixture.directory)
                let plan = try DCTimerImportPlan(backup: backup, validate: Engine.acceptsImportedScramble)
                let original = Solve(seconds: 7, event: "333", scramble: "U2")
                try JSONEncoder().encode([original]).write(to: fixture.storage)
                let model = fixture.model()
                #expect(try model.importDCTimer(plan, destination: destination, language: .english) == 2)

                let reopened = fixture.model()
                #expect(reopened.solves.count == 3)
                #expect(reopened.solves.contains(original))
                let clock = try #require(reopened.solves.first { $0.event == "clock" })
                let group = try #require(reopened.groups.first { $0.id == clock.groupID })
                #expect(group.isDefault == (destination == .defaultGroups))
                if destination == .originalSessions { #expect(group.name == "Clock practice") }

                let reread = try DCTimerBackup.read(fixture.directory.appending(path: "spdcube.sqlite"))
                let newPlan = try DCTimerImportPlan(backup: reread, validate: Engine.acceptsImportedScramble)
                let otherDestination: DCTimerImportDestination = destination == .defaultGroups ? .originalSessions : .defaultGroups
                #expect(try reopened.importDCTimer(newPlan, destination: otherDestination, language: .english) == 0)
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

            let reopened = fixture.model()
            #expect(reopened.lastImportCount == 1)
            #expect(reopened.undoLastImport() == 1)
            #expect(reopened.lastImportCount == 0)
            #expect(Set(reopened.solves.map(\.id)) == olderIDs)
            #expect(reopened.groups.contains { $0.id == added[1].groupID })
            #expect(reopened.undoLastImport() == nil)
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

        @MainActor func model(now: @escaping () -> ContinuousClock.Instant = { .now }) -> TimerModel {
            let generator = ScrambleGenerator()
            return TimerModel(storage: storage, defaults: defaults, now: now) { event in
                await generator.generate(event)
            }
        }
    }

    private actor ScrambleGenerator {
        private var count = 0

        func generate(_ event: String) -> Scramble {
            count += 1
            return Scramble(algorithm: "\(event):\(count)", svg: "")
        }
    }
}
