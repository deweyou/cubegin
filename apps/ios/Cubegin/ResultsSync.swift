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
        return replicaID.uuidString > other.replicaID.uuidString
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

protocol SyncTransport: Sendable {
    func fetch() async throws -> [SyncRecord]
    func merge(_ record: SyncRecord) async throws -> SyncRecord
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
    private static var syncPreview: PreviewCloudResultsTransport? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-icloud-error") { return .init(failure: .network) }
        if arguments.contains("--preview-icloud-account-error") { return .init(failure: .accountChanged) }
        if arguments.contains("--preview-icloud-upload") { return .init(failure: nil, uploadDelay: .seconds(2)) }
        if arguments.contains("--preview-icloud-success") { return .init(failure: nil) }
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

    func merge(_ record: SyncRecord) async throws -> SyncRecord {
        if uploadDelay > .zero { try await Task.sleep(for: uploadDelay) }
        return record
    }
}
#endif

struct ResultsSyncReplica: Sendable {
    struct State: Codable, Sendable {
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
        for (index, record) in pending.enumerated() {
            try Task.checkCancellation()
            try apply(try await transport.merge(record))
            await onUploadProgress?(index + 1, pending.count)
        }
        return remote.count
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
        case invalidRecord
        case unexpectedServerDeletion
    }

    func prepareZone(for account: String) async throws {
        expectedAccount = account
        try await verifyAccount()
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        try await verifyAccount()
        _ = try await database.save(CKRecordZone(zoneID: metadataZoneID))
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
        var token: CKServerChangeToken?
        var records: [UUID: SyncRecord] = [:]
        while true {
            try await verifyAccount()
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            guard page.deletions.isEmpty else { throw Failure.unexpectedServerDeletion }
            for result in page.modificationResultsByID.values {
                let record = try decode(result.get().record)
                if record.wins(over: records[record.id]) { records[record.id] = record }
            }
            if !page.moreComing { return Array(records.values) }
            token = page.changeToken
        }
    }

    func merge(_ candidate: SyncRecord) async throws -> SyncRecord {
        let zone = candidate.metadata == nil ? zoneID : metadataZoneID
        let id = CKRecord.ID(recordName: candidate.id.uuidString, zoneID: zone)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let record: CKRecord
            do {
                let fetched = try await database.record(for: id)
                let existing = try decode(fetched)
                guard candidate.wins(over: existing) else { return existing }
                record = fetched
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: recordType, recordID: id)
            }
            try await verifyAccount()
            record["payload"] = try JSONEncoder().encode(candidate) as NSData
            do {
                let result = try await database.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false
                )
                guard let saved = result.saveResults[id] else { throw Failure.invalidRecord }
                return try decode(saved.get())
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                continue
            }
        }
        throw Failure.invalidRecord
    }

    private func decode(_ record: CKRecord) throws -> SyncRecord {
        guard record.recordType == recordType, let data = record["payload"] as? Data else {
            throw Failure.invalidRecord
        }
        let value = try JSONDecoder().decode(SyncRecord.self, from: data)
        guard value.id.uuidString == record.recordID.recordName,
              value.solve.map({ $0.id == value.id }) ?? true,
              (record.recordID.zoneID == metadataZoneID) == (value.metadata != nil),
              value.metadata.map({ $0.id == value.id && value.solve == nil }) ?? true
        else { throw Failure.invalidRecord }
        return value
    }
}
