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

        #expect(ICloudSyncPreference.isEnabled(in: defaults, supportsResults: false))
        #expect(!ICloudSyncPreference.isEnabled(in: defaults, supportsResults: true))
        defaults.set(true, forKey: "results.icloudSync")
        let model = TimerModel(storage: storage, defaults: defaults, cloudTransport: SyntheticSyncServer())
        #expect(model.cloudSyncEnabled)
        model.setCloudSyncEnabled(false)
        #expect(!ICloudSyncPreference.isEnabled(in: defaults, supportsResults: false))
        #expect(!ICloudSyncPreference.isEnabled(in: defaults, supportsResults: true))
        let reopened = TimerModel(storage: storage, defaults: defaults, cloudTransport: SyntheticSyncServer())
        #expect(!reopened.cloudSyncEnabled)
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
        #expect(!model.cloudSyncEnabled)
        #expect(model.solves == [local])
        model.setCloudSyncEnabled(true)
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
        model.setCloudSyncEnabled(true)
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
