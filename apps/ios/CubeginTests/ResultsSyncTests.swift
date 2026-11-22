import CloudKit
import Foundation
import SQLite3
import Testing
@testable import CubeginApp

private actor SyntheticSyncServer: ResultsCloudTransport {
    enum Failure: Error { case offline, interrupted }
    private var records: [UUID: SyncRecord] = [:]
    private var online = true
    private var account = "original"
    private var writesUntilFailure: Int?

    func switchAccount() { account = "different" }
    func accountID() throws -> String {
        guard online else { throw CloudSyncFailure.network }
        return account
    }

    func prepareZone(for account: String) throws {
        guard try accountID() == account else { throw CloudSyncFailure.accountChanged }
    }

    func setOnline(_ online: Bool) { self.online = online }
    func interruptAfterWrites(_ count: Int?) { writesUntilFailure = count }

    func fetch() throws -> [SyncRecord] {
        guard online else { throw Failure.offline }
        return Array(records.values)
    }

    func merge(_ record: SyncRecord) throws -> SyncRecord {
        guard online else { throw Failure.offline }
        if let count = writesUntilFailure {
            guard count > 0 else { throw Failure.interrupted }
            writesUntilFailure = count - 1
        }
        if let current = records[record.id], !record.wins(over: current) { return current }
        records[record.id] = record
        return record
    }
}

struct ResultsSyncTests {
    @Test func recoversAStableGroupAfterConcurrentDeletionAndSyncsItsRename() async throws {
        let server = SyntheticSyncServer()
        let event = "333"
        let initial = SolveGroup(id: SolveGroup.initialID(for: event), event: event, name: "", isDefault: true)
        let practice = SolveGroup(id: "practice", event: event, name: "Practice", isDefault: false)
        let original = [initial, practice]
        var phone = ResultsSyncReplica(state: .init(replicaID: UUID()))
        var tablet = ResultsSyncReplica(state: .init(replicaID: UUID()))
        phone.importGroups(original)
        try await phone.sync(with: server)
        try await tablet.sync(with: server)

        var phoneDefault = practice
        phoneDefault.isDefault = true
        phone.recordGroupChanges(from: original, to: [phoneDefault])
        tablet.recordGroupChanges(from: original, to: [initial])
        try await phone.sync(with: server)
        try await tablet.sync(with: server)
        try await phone.sync(with: server)

        let phoneMerge = phone.mergeGroups([phoneDefault])
        let tabletMerge = tablet.mergeGroups([initial])
        #expect(phoneMerge.didRecover)
        #expect(tabletMerge.didRecover)
        let recoveredOnPhone = phoneMerge.groups
        let recoveredOnTablet = tabletMerge.groups
        var recovered = try #require(recoveredOnPhone.first)
        #expect(recoveredOnPhone.map(\.id) == recoveredOnTablet.map(\.id))
        #expect(recovered.id != initial.id)
        #expect(recovered.id != practice.id)
        #expect(recovered.isDefault)
        #expect(phone.metadata.contains(.group(event: event, id: recovered.id, name: "")))
        recovered.name = "Recovered practice"
        phone.recordGroupChanges(from: recoveredOnPhone, to: [recovered])
        try await phone.sync(with: server)
        try await tablet.sync(with: server)
        let restoredMerge = tablet.mergeGroups(recoveredOnTablet)
        #expect(!restoredMerge.didRecover)
        let restored = restoredMerge.groups
        #expect(restored.map(\.id) == [recovered.id])
        #expect(restored.first?.name == recovered.name)
        #expect(restored.first?.isDefault == true)
    }

    @Test func migratesOriginalGroupsAheadOfLegacyPlaceholders() async throws {
        let server = SyntheticSyncServer()
        let initial = SolveGroup(id: SolveGroup.initialID(for: "333"), event: "333", name: "", isDefault: true)
        let competition = SolveGroup(id: UUID().uuidString, event: "333", name: "Competition", isDefault: true)
        let placeholder = SolveGroup(id: competition.id, event: "333", name: SolveGroup.cloudPlaceholderName, isDefault: false)
        var originalInitial = initial
        originalInitial.isDefault = false
        var original = ResultsSyncReplica(state: .init(replicaID: UUID()))
        var imported = ResultsSyncReplica(state: .init(replicaID: UUID()))
        original.importGroups([competition, originalInitial])
        imported.importGroups([initial, placeholder])
        try await imported.sync(with: server)
        try await original.sync(with: server)
        try await imported.sync(with: server)

        let restored = imported.mergeGroups([initial, placeholder]).groups
        #expect(restored.map(\.id) == [competition.id, initial.id])
        #expect(restored.first?.name == "Competition")
        #expect(restored.first?.isDefault == true)
    }

    @Test func firstSyncMergesBothHistoriesAndRetriesPartialUpload() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = SyntheticSyncServer()
        let file = directory.appending(path: "iphone.json")
        var iphone = try ResultsSyncReplica(file: file)
        var ipad = try ResultsSyncReplica(file: directory.appending(path: "ipad.json"))
        let a = Solve(seconds: 10, event: "333", scramble: "R U", date: .distantPast)
        let b = Solve(seconds: 11, event: "333", scramble: "F U", date: .distantPast)
        let c = Solve(seconds: 12, event: "333", scramble: "U R", date: .distantPast)
        try iphone.importSolves([a, b])
        try ipad.importSolves([c])
        try await ipad.sync(with: server)
        await server.interruptAfterWrites(1)
        await #expect(throws: SyntheticSyncServer.Failure.interrupted) { try await iphone.sync(with: server) }
        #expect(try await server.fetch().count == 2)
        iphone = try ResultsSyncReplica(file: file)
        await server.interruptAfterWrites(nil)
        try await iphone.sync(with: server)
        try await ipad.sync(with: server)
        #expect(iphone.solves == ipad.solves)
        #expect(Set(iphone.solves.map(\.id)) == Set([a.id, b.id, c.id]))
        #expect(try await server.fetch().count == 3)
    }

    @Test func sameDCTimerBackupImportedOnBothDevicesProducesOneResult() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "synthetic.sqlite")
        try makeBackup(at: source)
        func read(timeZone: TimeZone, group: String) throws -> Solve {
            let backup = try DCTimerBackup.read(source, timeZone: timeZone)
            let entry = try #require(backup.sessions.first?.entries.first)
            return Solve(id: entry.id, seconds: Double(entry.milliseconds) / 1000,
                         event: "333", scramble: entry.scramble, date: entry.date, penalty: entry.penalty, groupID: group)
        }
        let a = try read(timeZone: #require(TimeZone(secondsFromGMT: 0)), group: "group-a")
        let b = try read(timeZone: #require(TimeZone(secondsFromGMT: 28_800)), group: "group-b")
        #expect(a.id == b.id)
        #expect(a.date != b.date)
        let server = SyntheticSyncServer()
        var iphone = try ResultsSyncReplica(file: directory.appending(path: "iphone.json"))
        var ipad = try ResultsSyncReplica(file: directory.appending(path: "ipad.json"))
        try iphone.importSolves([a, a])
        try ipad.importSolves([b])
        try await iphone.sync(with: server)
        try await ipad.sync(with: server)
        try await iphone.sync(with: server)
        try iphone.importSolves([a, b])
        #expect(iphone.solves.count == 1)
        #expect(iphone.solves == ipad.solves)
        #expect(try await server.fetch().count == 1)
    }

    @Test func offlineDeleteSurvivesRestartAndBeatsConcurrentEditsAndReimport() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = SyntheticSyncServer()
        let file = directory.appending(path: "iphone.json")
        var iphone = try ResultsSyncReplica(file: file)
        var ipad = try ResultsSyncReplica(file: directory.appending(path: "ipad.json"))
        var a = Solve(seconds: 10, event: "333", scramble: "R U", date: .distantPast)
        let b = Solve(seconds: 12, event: "333", scramble: "U R", date: .distantPast)
        try iphone.importSolves([a, b])
        try await iphone.sync(with: server)
        try await ipad.sync(with: server)
        await server.setOnline(false)
        try iphone.delete(a.id)
        await #expect(throws: SyntheticSyncServer.Failure.offline) { try await iphone.sync(with: server) }
        iphone = try ResultsSyncReplica(file: file)
        #expect(iphone.solves == [b])
        a.penalty = .plusTwo
        try ipad.edit(a)
        a.penalty = .dnf
        try ipad.edit(a)
        await server.setOnline(true)
        try await ipad.sync(with: server)
        try await iphone.sync(with: server)
        try await ipad.sync(with: server)
        try ipad.importSolves([a])
        #expect(iphone.solves == [b])
        #expect(ipad.solves == [b])
        let tombstone = try #require(try await server.fetch().first(where: { $0.id == a.id }))
        #expect(tombstone.solve == nil)
    }

    @Test func localChangesWhileSyncIsOffSurviveReopenAndSyncOnReenable() async throws {
        let server = SyntheticSyncServer()
        let original = Solve(seconds: 10, event: "333", scramble: "R U", date: .distantPast)
        let new = Solve(seconds: 11, event: "333", scramble: "U R", date: .distantPast)
        var replica = ResultsSyncReplica(state: .init(replicaID: UUID()))
        try replica.importSolves([original])
        try await replica.sync(with: server)

        try replica.recordLocalChanges(from: [original], to: [new])
        #expect(try await server.fetch().compactMap(\.solve) == [original])
        let saved = try JSONEncoder().encode(replica.state)
        var reopened = ResultsSyncReplica(state: try JSONDecoder().decode(ResultsSyncReplica.State.self, from: saved))
        try await reopened.sync(with: server)
        #expect(reopened.solves == [new])
        #expect(try await server.fetch().compactMap(\.solve) == [new])
    }

    @Test func localSolveMissingFromOlderSyncStateSurvivesMerge() async throws {
        let server = SyntheticSyncServer()
        let missing = Solve(seconds: 12.345, event: "333", scramble: "R U", date: .distantPast)
        let deleted = Solve(seconds: 10, event: "333", scramble: "U R", date: .distantPast)
        var replica = ResultsSyncReplica(state: .init(replicaID: UUID()))
        try replica.importSolves([deleted])
        try replica.delete(deleted.id)

        // This is the old save layout: local results contain an ID absent from the sync state.
        try replica.importSolves([missing, deleted])
        try await replica.sync(with: server)
        #expect(replica.solves == [missing])
        #expect(try await server.fetch().compactMap(\.solve) == [missing])
    }

    @Test func distinguishesAccountStatusAndCloudKitErrors() {
        #expect(CloudSyncFailure.accountStatus(.available) == nil)
        #expect(CloudSyncFailure.accountStatus(.noAccount) == .noAccount)
        #expect(CloudSyncFailure.accountStatus(.restricted) == .restricted)
        #expect(CloudSyncFailure.accountStatus(.temporarilyUnavailable) == .accountUnavailable)
        #expect(CloudSyncFailure.classify(CKError(.notAuthenticated)) == .authentication)
        #expect(CloudSyncFailure.classify(CKError(.quotaExceeded)) == .storageFull)
        #expect(CloudSyncFailure.classify(CKError(.networkFailure)) == .network)
        #expect(CloudSyncFailure.classify(CKError(.badContainer)) == .unknown)
    }

    @MainActor
    @Test func sharesOnePreferenceAndKeepsThePreviousResultsChoice() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appending(path: "solves.json")
        let suite = "icloud-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ICloudSyncPreference.isEnabled(in: defaults))
        let fresh = TimerModel(storage: storage, defaults: defaults, cloudTransport: SyntheticSyncServer())
        #expect(fresh.cloudSyncEnabled)
        defaults.set(false, forKey: "results.icloudSync")
        let model = TimerModel(storage: storage, defaults: defaults, cloudTransport: SyntheticSyncServer())
        #expect(!model.cloudSyncEnabled)
        model.setCloudSyncEnabled(true)
        #expect(model.cloudSyncEnabled)
        #expect(ICloudSyncPreference.isEnabled(in: defaults))
        let reopened = TimerModel(storage: storage, defaults: defaults, cloudTransport: SyntheticSyncServer())
        #expect(reopened.cloudSyncEnabled)
        reopened.setCloudSyncEnabled(false)
        #expect(!ICloudSyncPreference.isEnabled(in: defaults))
    }

    @MainActor
    @Test func integratesLegacyResultsAndPersistsOfflineDeletionWithoutClearingOtherScores() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appending(path: "solves.json")
        let suite = "results-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let local = Solve(seconds: 12, event: "333", scramble: "R U")
        let remote = Solve(seconds: 17, event: "333", scramble: "R U2")
        try JSONEncoder().encode([local]).write(to: storage)
        let server = SyntheticSyncServer()
        var replica = ResultsSyncReplica(state: .init(replicaID: UUID()))
        try replica.importSolves([remote])
        try await replica.sync(with: server)

        let model = TimerModel(storage: storage, defaults: defaults, cloudTransport: server)
        #expect(model.cloudSyncEnabled)
        #expect(model.solves == [local])
        model.requestCloudSync()
        try await waitForSync(model) { if case .synced = $0 { true } else { false } }
        #expect(Set(model.solves.map(\.id)) == [local.id, remote.id])

        model.setCloudSyncEnabled(false)
        await server.setOnline(false)
        #expect(model.deleteSolves([local.id]))
        let reopened = TimerModel(storage: storage, defaults: defaults, cloudTransport: server)
        #expect(!reopened.cloudSyncEnabled)
        #expect(reopened.solves == [remote])
        reopened.setCloudSyncEnabled(true)
        try await waitForSync(reopened) { if case .failed(.network) = $0 { true } else { false } }
        #expect(reopened.solves == [remote])

        await server.setOnline(true)
        reopened.requestCloudSync()
        try await waitForSync(reopened) { if case .synced = $0 { true } else { false } }
        let records = try await server.fetch()
        #expect(records.compactMap(\.solve) == [remote])
        #expect(records.contains { $0.id == local.id && $0.solve == nil })
    }

    @MainActor
    @Test func syncsGroupsAndSavedPreferencesAcrossTwoDevices() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let phoneSuite = "sync-phone-\(UUID())"
        let tabletSuite = "sync-tablet-\(UUID())"
        let phoneDefaults = try #require(UserDefaults(suiteName: phoneSuite))
        let tabletDefaults = try #require(UserDefaults(suiteName: tabletSuite))
        defer {
            phoneDefaults.removePersistentDomain(forName: phoneSuite)
            tabletDefaults.removePersistentDomain(forName: tabletSuite)
        }
        let server = SyntheticSyncServer()
        let phoneStorage = directory.appending(path: "phone.json")
        let phone = TimerModel(storage: phoneStorage, defaults: phoneDefaults, cloudTransport: server)
        let tablet = TimerModel(storage: directory.appending(path: "tablet.json"),
                                defaults: tabletDefaults, cloudTransport: server)
        phone.requestCloudSync()
        try await waitForSync(phone) { if case .synced = $0 { true } else { false } }
        phone.setCloudSyncEnabled(false)
        let initial = try #require(phone.currentGroup?.id)
        #expect(phone.saveGroup(name: "Competition", isDefault: true))
        let competition = try #require(phone.currentGroup?.id)
        #expect(phone.reorderGroups([competition, initial]))
        let assist = AssistPreferences(event: phone.event, groupID: competition, defaults: phoneDefaults)
        phone.preferenceDidChange(assist.saveMethod(.xcross))
        let orderKey = "assist.333/\(competition).order.xcross"
        phoneDefaults.set(["D", "U"], forKey: orderKey)
        phone.preferenceDidChange(orderKey)
        phone.standardEvent = "222"

        // Reopen while syncing is off to verify that local changes survive until reenabled.
        let reopened = TimerModel(storage: phoneStorage, defaults: phoneDefaults, cloudTransport: server)
        reopened.setCloudSyncEnabled(true)
        try await waitForSync(reopened) { if case .synced = $0 { true } else { false } }
        tablet.requestCloudSync()
        try await waitForSync(tablet) { if case .synced = $0 { true } else { false } }
        #expect(tablet.event == "222")
        let syncedGroups = tablet.groups.filter { $0.event == "333" }
        #expect(syncedGroups.map(\.id) == [competition, initial])
        #expect(syncedGroups.first?.name == "Competition")
        #expect(syncedGroups.first?.isDefault == true)
        let syncedAssist = AssistPreferences(event: "333", groupID: competition, defaults: tabletDefaults)
        #expect(syncedAssist.selectedMethod(from: [.cross, .xcross]) == .xcross)
        #expect(tabletDefaults.stringArray(forKey: orderKey) == ["D", "U"])

        tablet.standardEvent = "333"
        #expect(tablet.saveGroup(id: initial, name: "Practice", isDefault: true))
        #expect(tablet.deleteGroup(competition))
        try await waitForSync(tablet) { if case .synced = $0 { true } else { false } }
        reopened.requestCloudSync()
        try await waitForSync(reopened) { if case .synced = $0 { true } else { false } }
        #expect(reopened.event == "333")
        #expect(reopened.eventGroups.map(\.id) == [initial])
        #expect(reopened.currentGroup?.name == "Practice")
    }

    @MainActor
    @Test func refusesToSyncLocalResultsToADifferentAccount() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appending(path: "solves.json")
        let suite = "results-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let score = Solve(seconds: 12, event: "333", scramble: "R U")
        try JSONEncoder().encode([score]).write(to: storage)
        let server = SyntheticSyncServer()
        let model = TimerModel(storage: storage, defaults: defaults, cloudTransport: server)
        model.requestCloudSync()
        try await waitForSync(model) { if case .synced = $0 { true } else { false } }

        await server.switchAccount()
        model.requestCloudSync()
        try await waitForSync(model) { if case .failed(.accountChanged) = $0 { true } else { false } }
        #expect(model.solves == [score])
    }

    @MainActor
    private func waitForSync(_ model: TimerModel, matching: (TimerModel.CloudSyncStatus) -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !matching(model.cloudSyncStatus) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(matching(model.cloudSyncStatus))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makeBackup(at url: URL) throws {
        var db: OpaquePointer?
        let status = sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        try #require(status == SQLITE_OK)
        let created = sqlite3_exec(db, """
            CREATE TABLE sessiontb (rowid integer, name text);
            CREATE TABLE resulttb (id integer, sesid integer, rest integer, resp integer, scr text, date text);
            INSERT INTO resulttb VALUES (1, 0, 12345, 0, 'R U', '2024-01-01 00:00:00');
            """, nil, nil, nil)
        try #require(created == SQLITE_OK)
    }
}
