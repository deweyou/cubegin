import CloudKit
import Foundation

struct SyncRecord: Codable, Equatable, Sendable {
    let id: UUID
    let revision: Int
    let replicaID: UUID
    let solve: Solve? // nil is a durable tombstone, not a CloudKit record deletion.

    func wins(over other: Self?) -> Bool {
        guard let other else { return true }
        if (solve == nil) != (other.solve == nil) { return solve == nil }
        if revision != other.revision { return revision > other.revision }
        return replicaID.uuidString > other.replicaID.uuidString
    }
}

enum CloudSyncFailure: Error, Equatable {
    case noAccount, restricted, accountUnavailable, accountChanged
    case authentication, network, storageFull, serviceUnavailable, localStorage, unknown

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
    static var showsErrorPreview: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--preview-icloud-error")
#else
        false
#endif
    }

    static var isAvailable: Bool {
#if DEBUG && targetEnvironment(simulator)
        showsErrorPreview
#elseif DEBUG && CUBEGIN_RESULTS_SYNC
        Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin.dev"
#else
        false
#endif
    }

    static func configured() -> (any ResultsCloudTransport)? {
        guard isAvailable else { return nil }
#if DEBUG && targetEnvironment(simulator)
        return PreviewCloudResultsTransport()
#else
        return CloudKitResultsTransport()
#endif
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct PreviewCloudResultsTransport: ResultsCloudTransport {
    func accountID() async throws -> String { throw CloudSyncFailure.network }
    func prepareZone(for account: String) async throws { throw CloudSyncFailure.network }
    func fetch() async throws -> [SyncRecord] { throw CloudSyncFailure.network }
    func merge(_ record: SyncRecord) async throws -> SyncRecord { throw CloudSyncFailure.network }
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

    mutating func sync(with transport: any SyncTransport) async throws {
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
        for record in next.records.values where record.wins(over: remoteByID[record.id]) {
            try Task.checkCancellation()
            try apply(try await transport.merge(record))
        }
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

// Reuse the prototype’s private development container and record format.
actor CloudKitResultsTransport: ResultsCloudTransport {
    static let containerID = "iCloud.io.github.deweyou.cubegin.sync-prototype"
    private static let recordType = "PrototypeSolve"
    private let zoneID: CKRecordZone.ID
    private var expectedAccount: String?
    private let container = CKContainer(identifier: containerID)
    private var database: CKDatabase { container.privateCloudDatabase }

    init(zoneName: String = "DevAppResultsV1") {
        zoneID = CKRecordZone.ID(zoneName: zoneName)
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
    }

    private func verifyAccount() async throws {
        guard let expectedAccount, try await accountID() == expectedAccount else {
            throw CloudSyncFailure.accountChanged
        }
        try Task.checkCancellation()
    }

    func fetch() async throws -> [SyncRecord] {
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
        let id = CKRecord.ID(recordName: candidate.id.uuidString, zoneID: zoneID)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let record: CKRecord
            do {
                let fetched = try await database.record(for: id)
                let existing = try decode(fetched)
                guard candidate.wins(over: existing) else { return existing }
                record = fetched
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: id)
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
        guard record.recordType == Self.recordType, let data = record["payload"] as? Data else {
            throw Failure.invalidRecord
        }
        let value = try JSONDecoder().decode(SyncRecord.self, from: data)
        guard value.id.uuidString == record.recordID.recordName,
              value.solve.map({ $0.id == value.id }) ?? true else { throw Failure.invalidRecord }
        return value
    }
}
