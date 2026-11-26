import CloudKit
import CryptoKit
import Foundation

enum SyncedMetadata: Codable, Equatable, Sendable {
    case group(event: String, id: String, name: String?)
    case groupOrder(event: String, ids: [String])
    case defaultGroup(event: String, id: String)
    case preference(key: String, values: [String])

    var id: UUID {
        let key: [String]
        switch self {
        case .group(let event, let id, _): key = ["group", event, id]
        case .groupOrder(let event, _): key = ["order", event]
        case .defaultGroup(let event, _): key = ["default", event]
        case .preference(let keyName, _): key = ["preference", keyName]
        }
        let bytes = Array(SHA256.hash(data: Data(key.joined(separator: "\u{0}").utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    var isGroupDeletion: Bool {
        if case .group(_, _, nil) = self { return true }
        return false
    }
}

struct SyncRecord: Codable, Equatable, Sendable {
    let id: UUID
    let revision: Int
    let replicaID: UUID
    let solve: Solve?
    var metadata: SyncedMetadata?

    private var isDeletion: Bool { metadata?.isGroupDeletion ?? (solve == nil) }

    func wins(over other: Self?) -> Bool {
        guard let other else { return true }
        if isDeletion != other.isDeletion { return isDeletion }
        if revision != other.revision { return revision > other.revision }
        return replicaID != other.replicaID && replicaID.uuidString > other.replicaID.uuidString
    }
}

enum CloudSyncFailure: String, Error {
    case noAccount = "no_account"
    case restricted
    case accountUnavailable = "account_unavailable"
    case accountChanged = "account_changed"
    case authentication, network
    case storageFull = "storage_full"
    case serviceUnavailable = "service_unavailable"
    case localStorage = "local_storage"
    case unknown

    static func accountStatus(_ status: CKAccountStatus) -> Self? {
        switch status {
        case .available: return nil
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable, .couldNotDetermine: return .accountUnavailable
        @unknown default: return .accountUnavailable
        }
    }

    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated: return .authentication
            case .networkUnavailable, .networkFailure: return .network
            case .quotaExceeded: return .storageFull
            case .accountTemporarilyUnavailable: return .accountUnavailable
            case .serviceUnavailable, .requestRateLimited, .zoneBusy: return .serviceUnavailable
            default: break
            }
        }
        return .unknown
    }
}

typealias SyncBatchResults = [UUID: Result<SyncRecord, any Error>]

enum SyncBatchFailure: Error {
    case invalidRecord
}

protocol SyncTransport: Sendable {
    func fetch() async throws -> [SyncRecord]
    func merge(_ records: [SyncRecord]) async throws -> SyncBatchResults
}

protocol ResultsCloudTransport: SyncTransport {
    func accountID() async throws -> String
    func prepareZone(for account: String) async throws
}

extension CloudKitResultsTransport {
    static var showsSyncPreview: Bool {
#if DEBUG && targetEnvironment(simulator)
        syncPreview != nil
#else
        false
#endif
    }

    private static var environment: Environment? {
#if targetEnvironment(simulator)
        nil
#elseif DEBUG && CUBEGIN_RESULTS_SYNC
        Environment.development.matching(bundleIdentifier: Bundle.main.bundleIdentifier)
#elseif DEBUG
        nil
#else
        Environment.production.matching(bundleIdentifier: Bundle.main.bundleIdentifier)
#endif
    }

    static var isAvailable: Bool {
        showsSyncPreview || environment != nil
    }

    static func configured() -> (any ResultsCloudTransport)? {
#if DEBUG && targetEnvironment(simulator)
        return syncPreview
#else
        guard let environment else { return nil }
        return CloudKitResultsTransport(environment: environment)
#endif
    }

#if DEBUG && targetEnvironment(simulator)
    private static var syncPreview: (any ResultsCloudTransport)? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-icloud-late-results") { return LateResultsPreviewCloudTransport() }
        if arguments.contains("--preview-icloud-error") { return PreviewCloudResultsTransport(failure: .network) }
        if arguments.contains("--preview-icloud-account-error") { return PreviewCloudResultsTransport(failure: .accountChanged) }
        if arguments.contains("--preview-icloud-upload") {
            return PreviewCloudResultsTransport(failure: nil, uploadDelay: .seconds(4))
        }
        if arguments.contains("--preview-icloud-success") { return PreviewCloudResultsTransport(failure: nil) }
        return nil
    }
#endif
}

#if DEBUG && targetEnvironment(simulator)
private struct PreviewCloudResultsTransport: ResultsCloudTransport {
    let failure: CloudSyncFailure?
    var uploadDelay: Duration = .zero

    func accountID() async throws -> String { "preview" }
    func prepareZone(for account: String) async throws {}

    func fetch() async throws -> [SyncRecord] {
        try await Task.sleep(for: .seconds(2.5))
        if let failure { throw failure }
        return []
    }

    func merge(_ records: [SyncRecord]) async throws -> SyncBatchResults {
        if uploadDelay > .zero { try await Task.sleep(for: uploadDelay) }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, .success($0)) })
    }
}

private actor LateResultsPreviewCloudTransport: ResultsCloudTransport {
    private var didFetch = false
    private let replicaID = UUID()
    private let solve = Solve(seconds: 12.345, event: "333", scramble: "R U")

    func accountID() async throws -> String { "preview" }
    func prepareZone(for account: String) async throws {}

    func fetch() async throws -> [SyncRecord] {
        let hasRemoteSolve = didFetch
        didFetch = true
        try await Task.sleep(for: .seconds(2.5))
        guard hasRemoteSolve else { return [] }
        return [SyncRecord(id: solve.id, revision: 1, replicaID: replicaID, solve: solve)]
    }

    func merge(_ records: [SyncRecord]) -> SyncBatchResults {
        Dictionary(uniqueKeysWithValues: records.map { ($0.id, .success($0)) })
    }
}
#endif

struct ResultsSyncReplica: Sendable {
    private static let uploadBatchSize = 100

    struct State: Codable, Equatable, Sendable {
        let replicaID: UUID
        var records: [UUID: SyncRecord] = [:]
    }

    private let file: URL?
    private(set) var state: State

    init(state: State) {
        self.file = nil
        self.state = state
    }

    init(file: URL, replicaID: UUID = UUID()) throws {
        self.file = file
        do {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
            state = State(replicaID: replicaID)
        }
    }

    var solves: [Solve] { state.records.values.compactMap(\.solve).sorted(by: Solve.newestFirst) }

    mutating func importSolves(_ solves: [Solve]) throws {
        var next = state
        for solve in solves where next.records[solve.id] == nil {
            next.records[solve.id] = SyncRecord(id: solve.id, revision: 1, replicaID: next.replicaID, solve: solve)
        }
        try persist(next)
    }

    mutating func edit(_ solve: Solve) throws {
        guard let old = state.records[solve.id], old.solve != nil else { return }
        try apply(SyncRecord(id: solve.id, revision: old.revision + 1, replicaID: state.replicaID, solve: solve))
    }

    mutating func delete(_ id: UUID) throws {
        guard let old = state.records[id], old.solve != nil else { return }
        try apply(SyncRecord(id: id, revision: old.revision + 1, replicaID: state.replicaID, solve: nil))
    }

    mutating func recordMetadata(_ metadata: SyncedMetadata, migrationRevision: Int? = nil) {
        let id = metadata.id
        let previous = state.records[id]
        guard previous?.metadata != metadata, previous?.metadata?.isGroupDeletion != true,
              migrationRevision == nil || previous == nil else { return }
        state.records[id] = SyncRecord(
            id: id, revision: migrationRevision ?? (max(0, previous?.revision ?? 0) + 1),
            replicaID: state.replicaID, solve: nil, metadata: metadata
        )
    }

    var metadata: [SyncedMetadata] { state.records.values.compactMap(\.metadata) }

    mutating func importGroups(_ groups: [SolveGroup]) {
        for (event, eventGroups) in Dictionary(grouping: groups, by: \.event) {
            let initialID = SolveGroup.initialID(for: event)
            guard eventGroups.count > 1 || eventGroups.first?.id != initialID ||
                    eventGroups.first?.name.isEmpty == false else { continue }
            // Old replicas could infer a group from a remote solve without knowing its name or order.
            let hasPlaceholders = eventGroups.contains { $0.name == SolveGroup.cloudPlaceholderName }
            for group in eventGroups {
                let isInferred = group.name == SolveGroup.cloudPlaceholderName ||
                    (hasPlaceholders && group.id == initialID && group.name.isEmpty)
                let revision = isInferred ? -1 : 0
                recordMetadata(.group(event: event, id: group.id, name: group.name), migrationRevision: revision)
            }
            let orderRevision = hasPlaceholders ? -1 : 0
            recordMetadata(.groupOrder(event: event, ids: eventGroups.map(\.id)), migrationRevision: orderRevision)
            if let group = eventGroups.first(where: \.isDefault) {
                recordMetadata(.defaultGroup(event: event, id: group.id), migrationRevision: orderRevision)
            }
        }
    }

    mutating func recordGroupChanges(from previous: [SolveGroup], to current: [SolveGroup]) {
        let before = Dictionary(grouping: previous, by: \.event)
        let after = Dictionary(grouping: current, by: \.event)
        for (event, groups) in after {
            let previousGroups = before[event] ?? []
            let oldNames = Dictionary(previousGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let currentIDs = groups.map(\.id)
            let currentIDSet = Set(currentIDs)
            for group in groups where oldNames[group.id] != group.name {
                recordMetadata(.group(event: event, id: group.id, name: group.name))
            }
            for id in oldNames.keys where !currentIDSet.contains(id) {
                recordMetadata(.group(event: event, id: id, name: nil))
            }
            if currentIDs != previousGroups.map(\.id) {
                recordMetadata(.groupOrder(event: event, ids: currentIDs))
            }
            if let newDefault = groups.first(where: \.isDefault),
               previousGroups.first(where: \.isDefault)?.id != newDefault.id {
                recordMetadata(.defaultGroup(event: event, id: newDefault.id))
            }
        }
    }

    mutating func mergeGroups(_ local: [SolveGroup]) -> (groups: [SolveGroup], didRecover: Bool) {
        var events = Dictionary(grouping: local, by: \.event)
        var order: [String: [String]] = [:]
        var defaults: [String: String] = [:]
        for item in metadata {
            switch item {
            case .group(let event, let id, let name):
                var groups = events[event] ?? []
                if let name {
                    if let index = groups.firstIndex(where: { $0.id == id }) {
                        groups[index].name = name
                    } else {
                        groups.append(SolveGroup(id: id, event: event, name: name, isDefault: false))
                    }
                } else {
                    groups.removeAll { $0.id == id }
                }
                events[event] = groups
            case .groupOrder(let event, let ids): order[event] = ids
            case .defaultGroup(let event, let id): defaults[event] = id
            case .preference: break
            }
        }
        let localEvents = Set(local.map(\.event))
        let eventOrder = local.map(\.event).reduce(into: [String]()) { events, event in
            if !events.contains(event) { events.append(event) }
        } + events.keys.filter { !localEvents.contains($0) }.sorted()
        var didRecover = false
        let merged = eventOrder.flatMap { event -> [SolveGroup] in
            guard var groups = events[event], !groups.isEmpty else {
                didRecover = true
                return [recoverDefaultGroup(for: event)]
            }
            if let order = order[event] {
                let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) },
                                      uniquingKeysWith: { first, _ in first })
                groups.sort { (rank[$0.id] ?? Int.max, $0.id) < (rank[$1.id] ?? Int.max, $1.id) }
            }
            let desired = defaults[event] ?? groups.first(where: \.isDefault)?.id
            let defaultID = groups.first(where: { $0.id == desired })?.id ?? groups[0].id
            for index in groups.indices { groups[index].isDefault = groups[index].id == defaultID }
            return groups
        }
        return (merged, didRecover)
    }

    private mutating func recoverDefaultGroup(for event: String) -> SolveGroup {
        var id = SolveGroup.initialID(for: event)
        var generation = 1
        // Replicas that see the same deletions must recover the same group identity.
        while state.records[SyncedMetadata.group(event: event, id: id, name: nil).id]?.metadata?.isGroupDeletion == true {
            id = "recovered:\(event):\(generation)"
            generation += 1
        }
        recordMetadata(.group(event: event, id: id, name: ""))
        recordMetadata(.groupOrder(event: event, ids: [id]))
        recordMetadata(.defaultGroup(event: event, id: id))
        return SolveGroup(id: id, event: event, name: "", isDefault: true)
    }

    mutating func recordLocalChanges(from previous: [Solve], to current: [Solve]) throws {
        let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next = state
        for id in before.keys where after[id] == nil {
            guard let record = next.records[id], record.solve != nil else { continue }
            next.records[id] = SyncRecord(id: id, revision: record.revision + 1, replicaID: next.replicaID, solve: nil)
        }
        for solve in current where before[solve.id] != solve {
            let previous = next.records[solve.id]
            if let previous, previous.solve == nil { continue }
            next.records[solve.id] = SyncRecord(
                id: solve.id, revision: (previous?.revision ?? 0) + 1, replicaID: next.replicaID, solve: solve
            )
        }
        try persist(next)
    }

    @discardableResult
    mutating func sync(
        with transport: any SyncTransport,
        onUploadProgress: (@MainActor @Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> Int {
        try Task.checkCancellation()
        let remote = try await transport.fetch()
        try Task.checkCancellation()
        var next = state
        var remoteByID: [UUID: SyncRecord] = [:]
        for record in remote {
            if record.wins(over: remoteByID[record.id]) { remoteByID[record.id] = record }
            if record.wins(over: next.records[record.id]) { next.records[record.id] = record }
        }
        try persist(next)
        let pending = next.records.values.filter { $0.wins(over: remoteByID[$0.id]) }
        if !pending.isEmpty { await onUploadProgress?(0, pending.count) }
        var completed = 0
        for start in stride(from: 0, to: pending.count, by: Self.uploadBatchSize) {
            try Task.checkCancellation()
            let batch = pending[start..<min(start + Self.uploadBatchSize, pending.count)]
            let results = try await transport.merge(Array(batch))
            try Task.checkCancellation()
            let (processed, failure) = try applyBatch(results, for: batch)
            if processed > 0 {
                completed += processed
                await onUploadProgress?(completed, pending.count)
            }
            if let failure { throw failure }
        }
        return remote.count
    }

    private mutating func applyBatch(_ results: SyncBatchResults, for batch: ArraySlice<SyncRecord>) throws -> (Int, (any Error)?) {
        var next = state
        var changed = false
        var processed = 0
        var firstFailure: (any Error)?
        for candidate in batch {
            do {
                guard let result = results[candidate.id] else { throw SyncBatchFailure.invalidRecord }
                let record = try result.get()
                guard record.id == candidate.id else { throw SyncBatchFailure.invalidRecord }
                if record.wins(over: next.records[record.id]) {
                    next.records[record.id] = record
                    changed = true
                }
                processed += 1
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if changed { try persist(next) }
        return (processed, firstFailure)
    }

    private mutating func apply(_ record: SyncRecord) throws {
        guard record.wins(over: state.records[record.id]) else { return }
        var next = state
        next.records[record.id] = record
        try persist(next)
    }

    private mutating func persist(_ next: State) throws {
        if let file { try JSONEncoder().encode(next).write(to: file, options: .atomic) }
        state = next
    }
}

actor CloudKitResultsTransport: ResultsCloudTransport {
    enum Environment: Equatable, Sendable {
        case development
        case production

        private var bundleIdentifier: String {
            switch self {
            case .development: "io.github.deweyou.cubegin.dev"
            case .production: "io.github.deweyou.cubegin"
            }
        }

        var containerID: String {
            switch self {
            case .development: "iCloud.io.github.deweyou.cubegin.sync-prototype"
            case .production: "iCloud.io.github.deweyou.cubegin"
            }
        }

        var recordType: String {
            switch self {
            case .development: "PrototypeSolve"
            case .production: "CubeginResult"
            }
        }

        var zoneName: String {
            switch self {
            case .development: "DevAppResultsV1"
            case .production: "CubeginResultsV1"
            }
        }

        func matching(bundleIdentifier: String?) -> Self? {
            bundleIdentifier == self.bundleIdentifier ? self : nil
        }
    }

    private let recordType: String
    private let zoneID: CKRecordZone.ID
    private let metadataZoneID: CKRecordZone.ID
    private var expectedAccount: String?
    private var preparedAccount: String?
    private var zoneSnapshots: [CKRecordZone.ID: ZoneSnapshot] = [:]

    private struct ZoneSnapshot {
        var token: CKServerChangeToken?
        var records: [UUID: SyncRecord] = [:]
    }
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init(environment: Environment) {
        container = CKContainer(identifier: environment.containerID)
        recordType = environment.recordType
        zoneID = CKRecordZone.ID(zoneName: environment.zoneName)
        metadataZoneID = CKRecordZone.ID(zoneName: environment.zoneName + "Metadata")
    }

    func accountID() async throws -> String {
        if let failure = CloudSyncFailure.accountStatus(try await container.accountStatus()) {
            throw failure
        }
        return try await container.userRecordID().recordName
    }

    enum Failure: Error {
        case unexpectedServerDeletion
    }

    func prepareZone(for account: String) async throws {
        if expectedAccount != account {
            zoneSnapshots.removeAll()
            preparedAccount = nil
            expectedAccount = account
        }
        try await verifyAccount()
        guard preparedAccount != account else { return }
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        try await verifyAccount()
        _ = try await database.save(CKRecordZone(zoneID: metadataZoneID))
        preparedAccount = account
    }

    private func verifyAccount() async throws {
        guard let expectedAccount, try await accountID() == expectedAccount else {
            throw CloudSyncFailure.accountChanged
        }
        try Task.checkCancellation()
    }

    func fetch() async throws -> [SyncRecord] {
        let solves = try await fetch(in: zoneID)
        let metadata = try await fetch(in: metadataZoneID)
        return solves + metadata
    }

    private func fetch(in zoneID: CKRecordZone.ID) async throws -> [SyncRecord] {
        let previous = zoneSnapshots[zoneID] ?? ZoneSnapshot()
        do {
            let snapshot = try await fetchChanges(in: zoneID, since: previous)
            zoneSnapshots[zoneID] = snapshot
            return Array(snapshot.records.values)
        } catch let error as CKError where error.code == .changeTokenExpired && previous.token != nil {
            let snapshot = try await fetchChanges(in: zoneID, since: ZoneSnapshot())
            zoneSnapshots[zoneID] = snapshot
            return Array(snapshot.records.values)
        } catch let error as CKError where error.code == .zoneNotFound {
            preparedAccount = nil
            zoneSnapshots[zoneID] = nil
            throw error
        }
    }

    private func fetchChanges(in zoneID: CKRecordZone.ID, since previous: ZoneSnapshot) async throws -> ZoneSnapshot {
        var snapshot = previous
        while true {
            try await verifyAccount()
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: snapshot.token)
            guard page.deletions.isEmpty else { throw Failure.unexpectedServerDeletion }
            for result in page.modificationResultsByID.values {
                let record = try decode(result.get().record)
                if record.wins(over: snapshot.records[record.id]) { snapshot.records[record.id] = record }
            }
            snapshot.token = page.changeToken
            if !page.moreComing { return snapshot }
        }
    }

    func merge(_ records: [SyncRecord]) async throws -> SyncBatchResults {
        let database = database
        let writer = CloudKitResultsBatchWriter(
            recordType: recordType,
            fetchRecords: { ids in
                try await self.verifyAccount()
                return try await database.records(for: ids)
            },
            saveRecords: { records in
                try await self.verifyAccount()
                return try await database.modifyRecords(
                    saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false
                ).saveResults
            },
            decode: { try self.decode($0) }
        )
        let candidates = Dictionary(uniqueKeysWithValues: records.map { record in
            let zone = record.metadata == nil ? zoneID : metadataZoneID
            return (CKRecord.ID(recordName: record.id.uuidString, zoneID: zone), record)
        })
        return try await writer.merge(candidates)
    }

    private nonisolated func decode(_ record: CKRecord) throws -> SyncRecord {
        guard record.recordType == recordType, let data = record["payload"] as? Data else {
            throw SyncBatchFailure.invalidRecord
        }
        let value = try JSONDecoder().decode(SyncRecord.self, from: data)
        guard value.id.uuidString == record.recordID.recordName,
              value.solve.map({ $0.id == value.id }) ?? true,
              (record.recordID.zoneID == metadataZoneID) == (value.metadata != nil),
              value.metadata.map({ $0.id == value.id && value.solve == nil }) ?? true
        else { throw SyncBatchFailure.invalidRecord }
        return value
    }
}

struct CloudKitResultsBatchWriter: Sendable {
    typealias RecordResults = [CKRecord.ID: Result<CKRecord, any Error>]

    let recordType: String
    let fetchRecords: @Sendable ([CKRecord.ID]) async throws -> RecordResults
    let saveRecords: @Sendable ([CKRecord]) async throws -> RecordResults
    let decode: @Sendable (CKRecord) throws -> SyncRecord

    func merge(_ candidates: [CKRecord.ID: SyncRecord]) async throws -> SyncBatchResults {
        var pending = candidates
        var results: SyncBatchResults = [:]
        for attempt in 1...3 {
            guard !pending.isEmpty else { break }
            let fetched = try await request(Array(pending.keys), using: fetchRecords)
            let prepared = prepareSaves(pending, fetched: fetched, results: &results)
            let saved = try await request(Array(prepared.keys)) { ids in
                try await saveRecords(ids.compactMap { prepared[$0] })
            }
            var conflicts: [CKRecord.ID: SyncRecord] = [:]
            for (id, candidate) in pending where prepared[id] != nil {
                let outcome = saved[id] ?? .failure(SyncBatchFailure.invalidRecord)
                if case .failure(let error as CKError) = outcome, error.code == .serverRecordChanged, attempt < 3 {
                    conflicts[id] = candidate
                } else {
                    results[candidate.id] = outcome.flatMap { record in Result { try decode(record) } }
                }
            }
            pending = conflicts
        }
        return results
    }

    private func prepareSaves(_ candidates: [CKRecord.ID: SyncRecord], fetched: RecordResults,
                              results: inout SyncBatchResults) -> [CKRecord.ID: CKRecord] {
        var prepared: [CKRecord.ID: CKRecord] = [:]
        for (id, candidate) in candidates {
            do {
                guard let lookup = fetched[id] else { throw SyncBatchFailure.invalidRecord }
                let record: CKRecord
                switch lookup {
                case .success(let existing):
                    let remote = try decode(existing)
                    guard candidate.wins(over: remote) else {
                        results[candidate.id] = .success(remote)
                        continue
                    }
                    record = existing
                case .failure(let error as CKError) where error.code == .unknownItem:
                    record = CKRecord(recordType: recordType, recordID: id)
                case .failure(let error):
                    throw error
                }
                record["payload"] = try JSONEncoder().encode(candidate) as NSData
                prepared[id] = record
            } catch {
                results[candidate.id] = .failure(error)
            }
        }
        return prepared
    }

    private func request(_ ids: [CKRecord.ID], using operation: ([CKRecord.ID]) async throws -> RecordResults) async throws -> RecordResults {
        try Task.checkCancellation()
        guard !ids.isEmpty else { return [:] }
        do {
            let results = try await operation(ids)
            try Task.checkCancellation()
            return results
        } catch let error as CKError where error.code == .limitExceeded && ids.count > 1 {
            let middle = ids.count / 2
            let first = try await request(Array(ids[..<middle]), using: operation)
            let second = try await request(Array(ids[middle...]), using: operation)
            return first.merging(second) { first, _ in first }
        } catch {
            try Task.checkCancellation()
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, .failure(error)) })
        }
    }
}

actor ResultsSyncWorker {
    struct Preparation: Sendable {
        let snapshot: ResultsDatabase.Snapshot
        let replica: ResultsSyncReplica
        let account: String
        let recordCount: Int
    }

    struct Applied: Sendable {
        let preferences: [SyncedMetadata]
        let hasRepairsToUpload: Bool
    }

    private let persistence: ResultsPersistence
    private let transport: any ResultsCloudTransport

    init(persistence: ResultsPersistence, transport: any ResultsCloudTransport) {
        self.persistence = persistence
        self.transport = transport
    }

    func synchronize(groups: [SolveGroup], preferences: [String: [String]], editedKeys: Set<String>,
                     onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void) async throws -> Preparation {
        let account = try await transport.accountID()
        try Task.checkCancellation()
        var snapshot = persistence.current
        let storedAccount = snapshot.store.cloudAccount
        if let storedAccount, storedAccount != account { throw CloudSyncFailure.accountChanged }
        var replica = ResultsSyncReplica(state: snapshot.store.cloudState ?? .init(replicaID: UUID()))
        // Seed results from older builds and durably reserve revisions before uploading.
        try replica.importSolves(snapshot.store.solves)
        replica.importGroups(self.groups(from: snapshot, supplementedBy: groups))
        for (key, values) in preferences {
            replica.recordMetadata(.preference(key: key, values: values),
                                   migrationRevision: editedKeys.contains(key) ? nil : 0)
        }
        if snapshot.store.cloudState != replica.state || storedAccount == nil {
            var prepared = snapshot.store
            prepared.cloudState = replica.state
            prepared.cloudAccount = account
            snapshot = try save(prepared, replacing: snapshot)
        }

        try await transport.prepareZone(for: account)
        let recordCount = try await replica.sync(with: transport, onUploadProgress: onProgress)
        try Task.checkCancellation()
        guard try await transport.accountID() == account else { throw CloudSyncFailure.accountChanged }
        try Task.checkCancellation()
        return Preparation(snapshot: snapshot, replica: replica, account: account, recordCount: recordCount)
    }

    func apply(_ preparation: Preparation, groups: [SolveGroup]) throws -> Applied {
        try Task.checkCancellation()
        guard persistence.current.revision == preparation.snapshot.revision else {
            throw ResultsDatabase.Failure.staleSnapshot
        }
        var replica = preparation.replica
        let groupMerge = replica.mergeGroups(self.groups(from: preparation.snapshot, supplementedBy: groups))
        var updatedGroups = groupMerge.groups
        var groupKeys = Set(updatedGroups.map { ResultsGroupKey(event: $0.event, id: $0.id) })
        var defaults = Dictionary(updatedGroups.filter(\.isDefault).map { ($0.event, $0.id) },
                                  uniquingKeysWith: { first, _ in first })
        let deleted = Set(replica.metadata.compactMap { metadata -> ResultsGroupKey? in
            guard case .group(let event, let id, nil) = metadata else { return nil }
            return ResultsGroupKey(event: event, id: id)
        })
        var needsUpload = groupMerge.didRecover
        var solves = replica.solves
        for index in solves.indices {
            let key = ResultsGroupKey(solves[index])
            guard !groupKeys.contains(key) else { continue }
            if deleted.contains(key), let fallback = defaults[key.event] {
                // Keep a concurrent solve when its destination group was removed remotely.
                solves[index].groupID = fallback
                try replica.edit(solves[index])
                needsUpload = true
            } else {
                let isDefault = defaults[key.event] == nil
                updatedGroups.append(SolveGroup(id: key.id, event: key.event,
                                                name: key.id == SolveGroup.initialID(for: key.event) ? "" : SolveGroup.cloudPlaceholderName,
                                                isDefault: isDefault))
                groupKeys.insert(key)
                if isDefault { defaults[key.event] = key.id }
            }
        }

        var store = preparation.snapshot.store
        if store.solves != solves {
            store.solves = solves
            if let importedIDs = store.lastImportedSolveIDs {
                let remaining = importedIDs.intersection(solves.lazy.map(\.id))
                store.lastImportedSolveIDs = remaining.isEmpty ? nil : remaining
                if remaining.isEmpty { store.lastImportDate = nil }
            }
        }
        store.groups = updatedGroups
        store.cloudState = replica.state
        store.cloudAccount = preparation.account
        _ = try save(store, replacing: preparation.snapshot)
        return Applied(preferences: replica.metadata, hasRepairsToUpload: needsUpload)
    }

    private func groups(from snapshot: ResultsDatabase.Snapshot, supplementedBy defaults: [SolveGroup]) -> [SolveGroup] {
        let stored = snapshot.store.groups
        let events = Set(stored.map(\.event))
        return stored + defaults.filter { !events.contains($0.event) }
    }

    private func save(_ store: ResultsStore, replacing snapshot: ResultsDatabase.Snapshot) throws -> ResultsDatabase.Snapshot {
        do {
            return try persistence.save(store, replacing: snapshot, origin: .cloud)
        } catch ResultsDatabase.Failure.staleSnapshot {
            throw ResultsDatabase.Failure.staleSnapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CloudSyncFailure.localStorage
        }
    }
}
