import CloudKit
import Foundation
import SQLite3
import Testing
@testable import CubeginApp

struct ResultsListPresentationTests {
    @Test func keepsCloudChangesPendingWhileApplyingLocalEdits() {
        let old = Solve(seconds: 12, event: "333", scramble: "R U", date: .distantPast)
        let removedLocally = Solve(seconds: 13, event: "333", scramble: "R U2", date: .distantPast + 1)
        let remote = Solve(seconds: 14, event: "333", scramble: "U R", date: .distantPast + 2)
        let local = Solve(seconds: 15, event: "333", scramble: "U R2", date: .distantPast + 3)
        let syncedAt = Date(timeIntervalSinceReferenceDate: 100)
        var editedRemotely = old
        editedRemotely.penalty = .plusTwo

        var list = ResultsListPresentation(source: source([removedLocally, old]))
        list.update(from: source([remote, removedLocally, editedRemotely], syncedAt: syncedAt))
        #expect(list.displayedSolves == [removedLocally, old])
        #expect(list.hasCloudUpdates)

        list.update(from: source([local, remote, editedRemotely], syncedAt: syncedAt))
        #expect(list.displayedSolves == [local, old])
        #expect(list.hasCloudUpdates)

        list.showLatest()
        #expect(list.displayedSolves == [local, remote, editedRemotely])
        #expect(!list.hasCloudUpdates)
    }

    @Test func displaysTheFirstSyncedSolvesAndShowsTheSelectedGroupImmediately() {
        let first = Solve(seconds: 12, event: "333", scramble: "R U")
        let other = Solve(seconds: 13, event: "333", scramble: "R U2", groupID: "practice")
        var list = ResultsListPresentation(source: source([]))

        list.update(from: source([first], syncedAt: Date(timeIntervalSinceReferenceDate: 100)))
        #expect(list.displayedSolves == [first])
        #expect(!list.hasCloudUpdates)

        list.update(from: source([other], groupID: "practice", syncedAt: Date(timeIntervalSinceReferenceDate: 101)))
        #expect(list.displayedSolves == [other])
        #expect(!list.hasCloudUpdates)
    }

    private func source(_ solves: [Solve], groupID: String? = nil, syncedAt: Date? = nil) -> ResultsListPresentation.Source {
        .init(event: "333", groupID: groupID, solves: solves, lastCloudSync: syncedAt)
    }
}

private actor SyntheticSyncServer: ResultsCloudTransport {
    enum Failure: Error { case offline, interrupted }
    private enum AccountCheckFailure { case afterUpload, nextCheck }
    private var records: [UUID: SyncRecord] = [:]
    private var online = true
    private var account = "original"
    private var writesUntilFailure: Int?
    private var accountCheckFailure: AccountCheckFailure?
    private(set) var batchSizes: [Int] = []

    func switchAccount() { account = "different" }
    func accountID() throws -> String {
        if accountCheckFailure == .nextCheck {
            accountCheckFailure = nil
            throw CloudSyncFailure.network
        }
        guard online else { throw CloudSyncFailure.network }
        return account
    }

    func prepareZone(for account: String) throws {
        guard try accountID() == account else { throw CloudSyncFailure.accountChanged }
    }

    func setOnline(_ online: Bool) { self.online = online }
    func interruptAfterWrites(_ count: Int?) { writesUntilFailure = count }
    func interruptAccountCheckAfterUpload() { accountCheckFailure = .afterUpload }

    func fetch() throws -> [SyncRecord] {
        guard online else { throw Failure.offline }
        return Array(records.values)
    }

    private func merge(_ record: SyncRecord) throws -> SyncRecord {
        guard online else { throw Failure.offline }
        if let count = writesUntilFailure {
            guard count > 0 else { throw Failure.interrupted }
            writesUntilFailure = count - 1
        }
        if let current = records[record.id], !record.wins(over: current) { return current }
        records[record.id] = record
        if accountCheckFailure == .afterUpload { accountCheckFailure = .nextCheck }
        return record
    }

    func merge(_ batch: [SyncRecord]) -> SyncBatchResults {
        batchSizes.append(batch.count)
        return Dictionary(uniqueKeysWithValues: batch.map { record in
            (record.id, Result { try merge(record) })
        })
    }
}

private actor SyntheticCloudKitBatch {
    private let maximumRequestSize: Int
    private let rejected: Set<CKRecord.ID>
    private var concurrentWrites: [CKRecord.ID: SyncRecord]
    private var stored: [CKRecord.ID: Data] = [:]
    private(set) var fetches: [[CKRecord.ID]] = []
    private(set) var saves: [[CKRecord.ID]] = []

    init(maximumRequestSize: Int = 100, concurrentWrites: [CKRecord.ID: SyncRecord] = [:], rejected: Set<CKRecord.ID> = []) {
        self.maximumRequestSize = maximumRequestSize
        self.concurrentWrites = concurrentWrites
        self.rejected = rejected
    }

    nonisolated func writer() -> CloudKitResultsBatchWriter {
        CloudKitResultsBatchWriter(recordType: "CubeginResult", fetchRecords: { try await self.fetch($0) },
                                   saveRecords: { try await self.save($0) }, decode: { record in
            guard let payload = record["payload"] as? Data else { throw SyncBatchFailure.invalidRecord }
            return try JSONDecoder().decode(SyncRecord.self, from: payload)
        })
    }

    private func fetch(_ ids: [CKRecord.ID]) throws -> CloudKitResultsBatchWriter.RecordResults {
        fetches.append(ids)
        guard ids.count <= maximumRequestSize else { throw CKError(.limitExceeded) }
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            guard let payload = stored[id] else { return (id, .failure(CKError(.unknownItem))) }
            let record = CKRecord(recordType: "CubeginResult", recordID: id)
            record["payload"] = payload as NSData
            return (id, .success(record))
        })
    }

    private func save(_ batch: [CKRecord]) throws -> CloudKitResultsBatchWriter.RecordResults {
        saves.append(batch.map(\.recordID))
        guard batch.count <= maximumRequestSize else { throw CKError(.limitExceeded) }
        return Dictionary(uniqueKeysWithValues: batch.map { record in
            (record.recordID, Result { try save(record) })
        })
    }

    private func save(_ record: CKRecord) throws -> CKRecord {
        let id = record.recordID
        if let concurrent = concurrentWrites.removeValue(forKey: id) {
            stored[id] = try JSONEncoder().encode(concurrent)
            throw CKError(.serverRecordChanged)
        }
        guard !rejected.contains(id) else { throw CKError(.quotaExceeded) }
        stored[id] = record["payload"] as? Data
        return record
    }
}

struct CloudKitResultsBatchWriterTests {
    @Test func retriesConflictsWithoutResendingSuccessfulRecords() async throws {
        let deleted = candidate()
        let stillLocal = candidate()
        let accepted = candidate()
        let rejected = candidate()
        let tombstone = SyncRecord(id: deleted.id, revision: 1, replicaID: UUID(), solve: nil)
        let older = SyncRecord(id: stillLocal.id, revision: 1, replicaID: UUID(), solve: stillLocal.solve)
        let ids = [deleted, stillLocal, accepted, rejected].map(recordID)
        let cloud = SyntheticCloudKitBatch(concurrentWrites: [ids[0]: tombstone, ids[1]: older], rejected: [ids[3]])

        let candidates = Dictionary(uniqueKeysWithValues: zip(ids, [deleted, stillLocal, accepted, rejected]))
        let results = try await cloud.writer().merge(candidates)

        let fetches = await cloud.fetches.map(Set.init)
        let saves = await cloud.saves.map(Set.init)
        #expect(fetches == [Set(ids), [ids[0], ids[1]]])
        #expect(saves == [Set(ids), [ids[1]]])
        #expect(try results[deleted.id]?.get() == tombstone)
        #expect(try results[stillLocal.id]?.get() == stillLocal)
        #expect(try results[accepted.id]?.get() == accepted)
        #expect(throws: CKError(.quotaExceeded)) { try results[rejected.id]?.get() }
    }

    @Test func splitsOversizeFetchesAndSaves() async throws {
        let candidates = (0..<3).map { _ in candidate() }
        let cloud = SyntheticCloudKitBatch(maximumRequestSize: 2)
        let records = Dictionary(uniqueKeysWithValues: candidates.map { (recordID($0), $0) })

        let results = try await cloud.writer().merge(records)

        #expect(await cloud.fetches.map(\.count) == [3, 1, 2])
        #expect(await cloud.saves.map(\.count) == [3, 1, 2])
        for candidate in candidates {
            #expect(try results[candidate.id]?.get() == candidate)
        }
    }

    private func candidate() -> SyncRecord {
        let solve = Solve(seconds: 12, event: "333", scramble: "R U")
        return SyncRecord(id: solve.id, revision: 2, replicaID: UUID(), solve: solve)
    }

    private func recordID(_ record: SyncRecord) -> CKRecord.ID {
        CKRecord.ID(recordName: record.id.uuidString, zoneID: CKRecordZone.ID(zoneName: "CubeginResultsV1"))
    }
}

struct ResultsSyncTests {
    @MainActor
    @Test func reportsProcessedUploadsOnlyForPendingChanges() async throws {
        let server = SyntheticSyncServer()
        var replica = ResultsSyncReplica(state: .init(replicaID: UUID()))
        try replica.importSolves((0..<201).map { index in
            Solve(seconds: 12, event: "333", scramble: "R U", date: Date(timeIntervalSinceReferenceDate: Double(index)))
        })

        var processed: [Int] = []
        var totals: [Int] = []
        try await replica.sync(with: server) { completed, total in
            processed.append(completed)
            totals.append(total)
        }
        #expect(await server.batchSizes == [100, 100, 1])
        #expect(processed == [0, 100, 200, 201])
        #expect(totals == [201, 201, 201, 201])

        processed.removeAll()
        try await replica.sync(with: server) { completed, _ in processed.append(completed) }
        #expect(processed.isEmpty)
        #expect(await server.batchSizes == [100, 100, 1])
    }

    @Test func routesReleaseAndDevBuildsToSeparateCloudKitEnvironments() {
        let production = CloudKitResultsTransport.Environment.production
        let development = CloudKitResultsTransport.Environment.development

        #expect(production.matching(bundleIdentifier: "io.github.deweyou.cubegin") == production)
        #expect(production.matching(bundleIdentifier: "io.github.deweyou.cubegin.dev") == nil)
        #expect(development.matching(bundleIdentifier: "io.github.deweyou.cubegin") == nil)
        #expect(development.matching(bundleIdentifier: "io.github.deweyou.cubegin.dev") == development)
        #expect(production.matching(bundleIdentifier: nil) == nil)

        #expect(production.containerID == "iCloud.io.github.deweyou.cubegin")
        #expect(production.recordType == "CubeginResult")
        #expect(production.zoneName == "CubeginResultsV1")
        #expect(development.containerID == "iCloud.io.github.deweyou.cubegin.sync-prototype")
        #expect(development.recordType == "PrototypeSolve")
        #expect(development.zoneName == "DevAppResultsV1")
    }

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

    @MainActor
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
        var processed: [Int] = []
        await #expect(throws: SyntheticSyncServer.Failure.interrupted) {
            try await iphone.sync(with: server) { count, _ in processed.append(count) }
        }
        #expect(processed == [0, 1])
        #expect(try await server.fetch().count == 2)
        iphone = try ResultsSyncReplica(file: file)
        await server.interruptAfterWrites(nil)
        #expect(try await iphone.sync(with: server) == 2)
        #expect(await server.batchSizes == [1, 2, 1])
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
        let storage = directory.appending(path: "solves.sqlite")
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
        let storage = directory.appending(path: "solves.sqlite")
        let suite = "results-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let local = Solve(seconds: 12, event: "333", scramble: "R U")
        let remote = Solve(seconds: 17, event: "333", scramble: "R U2")
        try JSONEncoder().encode([local]).write(to: directory.appending(path: "solves.json"))
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
        let phoneStorage = directory.appending(path: "phone.sqlite")
        let phone = TimerModel(storage: phoneStorage, defaults: phoneDefaults, cloudTransport: server)
        let tablet = TimerModel(storage: directory.appending(path: "tablet.sqlite"),
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
    @Test func preferenceChangeAfterInterruptedSyncUsesANewRevision() async throws {
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
        let phoneStorage = directory.appending(path: "phone.sqlite")
        let phone = TimerModel(storage: phoneStorage, defaults: phoneDefaults, cloudTransport: server)
        phone.requestCloudSync()
        try await waitForSync(phone) { if case .synced = $0 { true } else { false } }

        await server.interruptAccountCheckAfterUpload()
        phone.standardEvent = "222"
        try await waitForSync(phone) { if case .failed(.network) = $0 { true } else { false } }
        let firstPreference = SyncedMetadata.preference(key: "scramble.standard", values: ["222"])
        let firstRecords = try await server.fetch()
        let firstUpload = try #require(firstRecords.first { $0.id == firstPreference.id })
        #expect(firstUpload.metadata == firstPreference)

        let reopened = TimerModel(storage: phoneStorage, defaults: phoneDefaults, cloudTransport: server)
        reopened.standardEvent = "444"
        try await waitForSync(reopened) { if case .synced = $0 { true } else { false } }
        let secondRecords = try await server.fetch()
        let secondUpload = try #require(secondRecords.first { $0.id == firstPreference.id })
        #expect(secondUpload.revision > firstUpload.revision)

        let tablet = TimerModel(storage: directory.appending(path: "tablet.sqlite"),
                                defaults: tabletDefaults, cloudTransport: server)
        tablet.requestCloudSync()
        try await waitForSync(tablet) { if case .synced = $0 { true } else { false } }
        #expect(reopened.event == "444")
        #expect(tablet.event == "444")
    }

    @MainActor
    @Test func refusesToSyncLocalResultsToADifferentAccount() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appending(path: "solves.sqlite")
        let suite = "results-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let score = Solve(seconds: 12, event: "333", scramble: "R U")
        try JSONEncoder().encode([score]).write(to: directory.appending(path: "solves.json"))
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
