import Foundation
import SQLite3

struct ResultsStore: Codable, Equatable, Sendable {
    var solves: [Solve] = []
    var groups: [SolveGroup] = []
    var lastImportedSolveIDs: Set<Solve.ID>?
    var lastImportDate: Date?
    var cloudState: ResultsSyncReplica.State?
    var cloudAccount: String?
}

struct ResultsGroupKey: Hashable, Sendable {
    let event: String
    let id: String

    init(event: String, id: String) {
        self.event = event
        self.id = id
    }

    init(_ solve: Solve) {
        self.init(event: solve.event, id: solve.groupID ?? SolveGroup.initialID(for: solve.event))
    }
}

struct ResultsDatabase: Sendable {
    struct Snapshot: Sendable {
        var store: ResultsStore
        var revision: Int64?
    }

    enum Failure: LocalizedError, Equatable {
        case sqlite(Int32)
        case invalidRecord
        case unsupportedSchema
        case staleSnapshot

        var errorDescription: String? {
            switch self {
            case .sqlite(let code): String(cString: sqlite3_errstr(code))
            case .invalidRecord: "The results database contains an invalid record."
            case .unsupportedSchema: "This version of Cubegin cannot read the results database."
            case .staleSnapshot: "The results database changed. Reopen Cubegin to reload it."
            }
        }
    }

    let url: URL
    private var legacyURL: URL { url.deletingPathExtension().appendingPathExtension("json") }

    func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: legacyURL.path) else {
            return Snapshot(store: ResultsStore(), revision: nil)
        }
        return try withDatabase(create: true) { database in
            try database.execute("PRAGMA journal_mode = WAL")
            return try database.transaction {
                switch try schemaVersion(in: database) {
                case 0:
                    let legacy = try loadLegacyStore()
                    try database.execute(Self.schema)
                    try write(legacy, replacing: ResultsStore(), to: database)
                    try writeInfo(legacy, revision: 0, to: database)
                    try database.execute("PRAGMA user_version = 1")
                case 1:
                    break
                default:
                    throw Failure.unsupportedSchema
                }
                try database.execute(Self.groupIndex)
                return try readSnapshot(from: database)
            }
        }
    }

    func save(_ store: ResultsStore, replacing previous: Snapshot) throws -> Snapshot {
        let revision = (previous.revision ?? -1) + 1
        try withDatabase(create: previous.revision == nil) { database in
            if previous.revision == nil { try database.execute("PRAGMA journal_mode = WAL") }
            try database.transaction {
                if let expected = previous.revision {
                    let stored = try database.read("SELECT revision FROM results_info WHERE singleton = 1") { $0.integer(0) }
                    guard stored.first == expected else { throw Failure.staleSnapshot }
                } else {
                    guard try schemaVersion(in: database) == 0, !FileManager.default.fileExists(atPath: legacyURL.path) else {
                        throw Failure.staleSnapshot
                    }
                    try database.execute(Self.schema)
                    try database.execute(Self.groupIndex)
                }
                try write(store, replacing: previous.store, to: database)
                try writeInfo(store, revision: revision, to: database)
                if previous.revision == nil { try database.execute("PRAGMA user_version = 1") }
            }
        }
        return Snapshot(store: store, revision: revision)
    }

    private func schemaVersion(in database: ResultsConnection) throws -> Int64 {
        guard let version = try database.read("PRAGMA user_version", { $0.integer(0) }).first else {
            throw Failure.unsupportedSchema
        }
        return version
    }

    private func loadLegacyStore() throws -> ResultsStore {
        let data: Data
        do {
            data = try Data(contentsOf: legacyURL)
        } catch CocoaError.fileReadNoSuchFile {
            return ResultsStore()
        }
        let decoder = JSONDecoder()
        var store: ResultsStore
        if let saved = try? decoder.decode(ResultsStore.self, from: data) {
            store = saved
        } else {
            store = ResultsStore(solves: try decoder.decode([Solve].self, from: data))
        }
        let imported = store.lastImportedSolveIDs?.intersection(store.solves.lazy.map(\.id)) ?? []
        store.lastImportedSolveIDs = imported.isEmpty ? nil : imported
        if imported.isEmpty { store.lastImportDate = nil }
        return store
    }

    private func readSnapshot(from database: ResultsConnection) throws -> Snapshot {
        let solves = try database.read("""
            SELECT id, seconds, event, scramble, solved_at, penalty, group_id
            FROM solves ORDER BY solved_at DESC, id
            """) { row in
            try row.solve()
        }
        let groups = try database.read("SELECT id, event, name, is_default FROM solve_groups ORDER BY position") { row in
            try SolveGroup(id: row.requiredText(0), event: row.requiredText(1), name: row.requiredText(2),
                           isDefault: row.integer(3) != 0)
        }
        let imported = Set(try database.read("SELECT id FROM imported_solves") { try $0.uuid(0) })
        let info = try database.read("""
            SELECT revision, imported_at, replica_id, cloud_account FROM results_info WHERE singleton = 1
            """) { row in
            try (row.integer(0), row.double(1).map(Date.init(timeIntervalSinceReferenceDate:)),
                 row.text(2), row.text(3))
        }
        guard let (revision, importedAt, replica, account) = info.first else { throw Failure.invalidRecord }
        let records = try database.read("SELECT id, payload FROM sync_records") { row in
            let id = try row.uuid(0)
            let record = try JSONDecoder().decode(SyncRecord.self, from: row.blob(1))
            guard id == record.id else { throw Failure.invalidRecord }
            return (id, record)
        }
        let cloudState: ResultsSyncReplica.State?
        if let replica {
            guard let replicaID = UUID(uuidString: replica) else { throw Failure.invalidRecord }
            cloudState = .init(replicaID: replicaID, records: Dictionary(uniqueKeysWithValues: records))
        } else {
            guard records.isEmpty else { throw Failure.invalidRecord }
            cloudState = nil
        }
        return Snapshot(store: ResultsStore(solves: solves, groups: groups,
                                             lastImportedSolveIDs: imported.isEmpty ? nil : imported,
                                             lastImportDate: importedAt, cloudState: cloudState, cloudAccount: account),
                        revision: revision)
    }

    private func write(_ store: ResultsStore, replacing previous: ResultsStore, to database: ResultsConnection) throws {
        let before = try Self.solvesByID(previous.solves)
        let after = try Self.solvesByID(store.solves)
        try database.write("DELETE FROM solves WHERE id = ?", rows: before.keys.filter { after[$0] == nil }) {
            [.text($0.uuidString)]
        }
        try database.write("""
            INSERT INTO solves (id, seconds, event, scramble, solved_at, penalty, group_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET seconds = excluded.seconds, event = excluded.event,
                scramble = excluded.scramble, solved_at = excluded.solved_at, penalty = excluded.penalty, group_id = excluded.group_id
            """, rows: store.solves.filter { before[$0.id] != $0 }) { solve in
            [.text(solve.id.uuidString), .real(solve.seconds), .text(solve.event), .text(solve.scramble),
             .real(solve.date.timeIntervalSinceReferenceDate), .text(solve.penalty?.rawValue), .text(solve.groupID)]
        }
        if store.groups != previous.groups {
            try database.execute("DELETE FROM solve_groups")
            try database.write("""
                INSERT INTO solve_groups (id, event, name, is_default, position) VALUES (?, ?, ?, ?, ?)
                """, rows: Array(store.groups.enumerated())) { index, group in
                [.text(group.id), .text(group.event), .text(group.name), .integer(group.isDefault ? 1 : 0), .integer(Int64(index))]
            }
        }
        let oldImported = previous.lastImportedSolveIDs ?? []
        let newImported = store.lastImportedSolveIDs ?? []
        try database.write("DELETE FROM imported_solves WHERE id = ?", rows: oldImported.subtracting(newImported)) {
            [.text($0.uuidString)]
        }
        try database.write("INSERT INTO imported_solves (id) VALUES (?)", rows: newImported.subtracting(oldImported)) {
            [.text($0.uuidString)]
        }
        try writeSyncRecords(store.cloudState?.records ?? [:], replacing: previous.cloudState?.records ?? [:], to: database)
    }

    private func writeSyncRecords(_ records: [UUID: SyncRecord], replacing previous: [UUID: SyncRecord],
                                  to database: ResultsConnection) throws {
        try database.write("DELETE FROM sync_records WHERE id = ?", rows: previous.keys.filter { records[$0] == nil }) {
            [.text($0.uuidString)]
        }
        try database.write("""
            INSERT INTO sync_records (id, payload) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
            """, rows: records.filter { previous[$0.key] != $0.value }) { id, record in
            guard id == record.id else { throw Failure.invalidRecord }
            return [.text(id.uuidString), .blob(try JSONEncoder().encode(record))]
        }
    }

    private func writeInfo(_ store: ResultsStore, revision: Int64, to database: ResultsConnection) throws {
        try database.write("""
            INSERT INTO results_info (singleton, revision, imported_at, replica_id, cloud_account) VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(singleton) DO UPDATE SET revision = excluded.revision, imported_at = excluded.imported_at,
                replica_id = excluded.replica_id, cloud_account = excluded.cloud_account
            """, rows: [store]) { store in
            [.integer(revision), .real(store.lastImportDate?.timeIntervalSinceReferenceDate),
             .text(store.cloudState?.replicaID.uuidString), .text(store.cloudAccount)]
        }
    }

    private static func solvesByID(_ solves: [Solve]) throws -> [Solve.ID: Solve] {
        var indexed: [Solve.ID: Solve] = [:]
        for solve in solves {
            guard indexed.updateValue(solve, forKey: solve.id) == nil else { throw Failure.invalidRecord }
        }
        return indexed
    }

    private func withDatabase<T>(create: Bool, _ action: (ResultsConnection) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        defer { if let handle { sqlite3_close(handle) } }
        try ResultsConnection.check(status)
        guard let handle else { throw Failure.sqlite(SQLITE_CANTOPEN) }
        try ResultsConnection.check(sqlite3_busy_timeout(handle, 1_000))
        let database = ResultsConnection(handle: handle)
        try database.execute("PRAGMA foreign_keys = ON")
        return try action(database)
    }

    private static let groupIndex = """
        CREATE INDEX IF NOT EXISTS solves_by_group_date
        ON solves(event, coalesce(group_id, 'default:' || event), solved_at DESC, id)
        """

    private static let schema = """
        CREATE TABLE results_info (
            singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
            revision INTEGER NOT NULL,
            imported_at REAL,
            replica_id TEXT,
            cloud_account TEXT
        );
        CREATE TABLE solves (
            id TEXT PRIMARY KEY NOT NULL,
            seconds REAL NOT NULL,
            event TEXT NOT NULL,
            scramble TEXT NOT NULL,
            solved_at REAL NOT NULL,
            penalty TEXT,
            group_id TEXT
        );
        CREATE INDEX solves_by_date ON solves(solved_at DESC, id);
        CREATE TABLE solve_groups (
            id TEXT NOT NULL,
            event TEXT NOT NULL,
            name TEXT NOT NULL,
            is_default INTEGER NOT NULL CHECK(is_default IN (0, 1)),
            position INTEGER NOT NULL UNIQUE,
            PRIMARY KEY(event, id)
        );
        CREATE TABLE imported_solves (
            id TEXT PRIMARY KEY NOT NULL REFERENCES solves(id) ON DELETE CASCADE
        );
        CREATE TABLE sync_records (
            id TEXT PRIMARY KEY NOT NULL,
            payload BLOB NOT NULL
        );
        """
}

private struct ResultsConnection {
    enum Value {
        case text(String?)
        case real(Double?)
        case integer(Int64)
        case blob(Data)
    }

    let handle: OpaquePointer

    static func check(_ result: Int32, equals expected: Int32 = SQLITE_OK) throws {
        guard result != expected else { return }
        if result == SQLITE_FULL { throw CocoaError(.fileWriteOutOfSpace) }
        throw ResultsDatabase.Failure.sqlite(result)
    }

    func execute(_ sql: String) throws {
        try Self.check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try action()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func read<T>(_ sql: String, values: [Value] = [], _ decode: (ResultsRow) throws -> T) throws -> [T] {
        try statement(sql) { handle in
            for (index, value) in values.enumerated() {
                try bind(value, to: handle, at: Int32(index + 1))
            }
            var rows: [T] = []
            var status = sqlite3_step(handle)
            while status == SQLITE_ROW {
                rows.append(try decode(ResultsRow(handle: handle)))
                status = sqlite3_step(handle)
            }
            try Self.check(status, equals: SQLITE_DONE)
            return rows
        }
    }

    func write<Rows: Collection>(_ sql: String, rows: Rows, values: (Rows.Element) throws -> [Value]) throws {
        guard !rows.isEmpty else { return }
        try statement(sql) { handle in
            for row in rows {
                for (index, value) in try values(row).enumerated() {
                    try bind(value, to: handle, at: Int32(index + 1))
                }
                try Self.check(sqlite3_step(handle), equals: SQLITE_DONE)
                try Self.check(sqlite3_reset(handle))
                try Self.check(sqlite3_clear_bindings(handle))
            }
        }
    }

    private func statement<T>(_ sql: String, _ action: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        defer { if let statement { sqlite3_finalize(statement) } }
        try Self.check(status)
        guard let statement else { throw ResultsDatabase.Failure.invalidRecord }
        return try action(statement)
    }

    private func bind(_ value: Value, to handle: OpaquePointer, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result: Int32
        switch value {
        case .text(let text?):
            result = text.withCString { sqlite3_bind_text(handle, index, $0, Int32(text.utf8.count), transient) }
        case .real(let real?):
            guard real.isFinite else { throw ResultsDatabase.Failure.invalidRecord }
            result = sqlite3_bind_double(handle, index, real)
        case .integer(let integer):
            result = sqlite3_bind_int64(handle, index, integer)
        case .blob(let blob):
            result = blob.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32($0.count), transient) }
        case .text(nil), .real(nil):
            result = sqlite3_bind_null(handle, index)
        }
        try Self.check(result)
    }
}

private struct ResultsRow {
    let handle: OpaquePointer

    func integer(_ index: Int32) -> Int64 { sqlite3_column_int64(handle, index) }

    func double(_ index: Int32) -> Double? {
        let type = sqlite3_column_type(handle, index)
        guard type == SQLITE_FLOAT || type == SQLITE_INTEGER else { return nil }
        let value = sqlite3_column_double(handle, index)
        return value.isFinite ? value : nil
    }

    func requiredDouble(_ index: Int32) throws -> Double {
        guard let value = double(index) else { throw ResultsDatabase.Failure.invalidRecord }
        return value
    }

    func text(_ index: Int32) throws -> String? {
        if sqlite3_column_type(handle, index) == SQLITE_NULL { return nil }
        guard let bytes = sqlite3_column_text(handle, index),
              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(handle, index))),
                                encoding: .utf8) else { throw ResultsDatabase.Failure.invalidRecord }
        return text
    }

    func requiredText(_ index: Int32) throws -> String {
        guard let value = try text(index) else { throw ResultsDatabase.Failure.invalidRecord }
        return value
    }

    func uuid(_ index: Int32) throws -> UUID {
        guard let id = UUID(uuidString: try requiredText(index)) else { throw ResultsDatabase.Failure.invalidRecord }
        return id
    }

    func solve() throws -> Solve {
        let penalty: SolvePenalty?
        if let rawPenalty = try text(5) {
            guard let value = SolvePenalty(rawValue: rawPenalty) else { throw ResultsDatabase.Failure.invalidRecord }
            penalty = value
        } else {
            penalty = nil
        }
        return try Solve(id: uuid(0), seconds: requiredDouble(1), event: requiredText(2),
                         scramble: requiredText(3), date: Date(timeIntervalSinceReferenceDate: requiredDouble(4)),
                         penalty: penalty, groupID: text(6))
    }

    func blob(_ index: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(handle, index) else { throw ResultsDatabase.Failure.invalidRecord }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, index)))
    }
}

struct ResultsChange: Sendable {
    enum Origin: Equatable, Sendable { case local, cloud }

    struct Entry: Sendable {
        let before: Solve?
        let after: Solve?

        let id: Solve.ID

        func affects(_ group: ResultsGroupKey) -> Bool {
            before.map(ResultsGroupKey.init) == group || after.map(ResultsGroupKey.init) == group
        }
    }

    let revision: Int64
    let origin: Origin
    let entries: [Entry]
    let affectedGroups: Set<ResultsGroupKey>

    init(revision: Int64, origin: Origin, before: [Solve], after: [Solve]) {
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        entries = old.keys.filter { new[$0] == nil }.map { Entry(before: old[$0], after: nil, id: $0) }
            + after.filter { old[$0.id] != $0 }.map { Entry(before: old[$0.id], after: $0, id: $0.id) }
        affectedGroups = Set(entries.flatMap { [$0.before, $0.after].compactMap { $0.map(ResultsGroupKey.init) } })
        self.revision = revision
        self.origin = origin
    }
}

// Only short synchronous local edits share this lock with the background writer.
// CloudKit requests, merge preparation, and independent SQLite readers never hold it.
final class ResultsPersistence: @unchecked Sendable {
    let database: ResultsDatabase
    private let lock = NSRecursiveLock()
    private let observerLock = NSLock()
    private var snapshot = ResultsDatabase.Snapshot(store: ResultsStore(), revision: nil)
    private var observers: [UUID: AsyncStream<ResultsChange>.Continuation] = [:]

    init(url: URL) {
        database = ResultsDatabase(url: url)
    }

    func load() throws -> ResultsDatabase.Snapshot {
        try lock.withLock {
            snapshot = try database.load()
            return snapshot
        }
    }

    var current: ResultsDatabase.Snapshot { lock.withLock { snapshot } }

    func withExclusiveWrite<T>(_ edit: () throws -> T) rethrows -> T {
        try lock.withLock(edit)
    }

    func save(_ store: ResultsStore, replacing previous: ResultsDatabase.Snapshot,
              origin: ResultsChange.Origin) throws -> ResultsDatabase.Snapshot {
        try lock.withLock {
            if origin == .cloud { try Task.checkCancellation() }
            guard snapshot.revision == previous.revision else { throw ResultsDatabase.Failure.staleSnapshot }
            guard previous.store != store else { return previous }
            let committed = try database.save(store, replacing: previous)
            snapshot = committed
            let listeners = observerLock.withLock { Array(observers.values) }
            if let revision = committed.revision, !listeners.isEmpty, previous.store.solves != store.solves {
                let change = ResultsChange(revision: revision, origin: origin,
                                           before: previous.store.solves, after: store.solves)
                for listener in listeners { listener.yield(change) }
            }
            return committed
        }
    }

    func reader(for group: ResultsGroupKey) -> ResultsPageReader {
        ResultsPageReader(database: database, group: group) { [weak self] in
            self?.current.revision != nil
        }
    }

    func changes() -> AsyncStream<ResultsChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ResultsChange.self)
        continuation.onTermination = { [weak self] _ in
            self?.removeObserver(id)
        }
        observerLock.withLock { observers[id] = continuation }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        _ = observerLock.withLock { observers.removeValue(forKey: id) }
    }
}

struct SolvePage: Equatable, Sendable {
    let solves: [Solve]
    let total: Int
    let revision: Int64
    let bestID: Solve.ID?
    let worstID: Solve.ID?
}

actor ResultsPageReader {
    private static let groupFilter = "event = ? AND coalesce(group_id, 'default:' || event) = ?"
    private static let columns = "id, seconds, event, scramble, solved_at, penalty, group_id"
    private let url: URL
    private let group: ResultsGroupKey
    private let isCommitted: (@Sendable () -> Bool)?
    private var reader: Reader?
    private var hasLocalEdits = false
    private var summary: (includesDNF: Bool, value: Summary)?

    private struct Summary {
        let total: Int
        let bestID: Solve.ID?
        let worstID: Solve.ID?
    }

    // A read transaction in WAL mode keeps scrolling on the same snapshot while an
    // iCloud change awaits acknowledgement. Temporary rows show subsequent local edits.
    private final class Reader {
        let connection: ResultsConnection
        let revision: Int64

        init(url: URL) throws {
            var handle: OpaquePointer?
            let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
            guard status == SQLITE_OK, let handle else {
                if let handle { sqlite3_close(handle) }
                throw ResultsDatabase.Failure.sqlite(status)
            }
            connection = ResultsConnection(handle: handle)
            do {
                try ResultsConnection.check(sqlite3_busy_timeout(handle, 1_000))
                try connection.execute("BEGIN DEFERRED")
                guard let revision = try connection.read("SELECT revision FROM results_info WHERE singleton = 1", { $0.integer(0) }).first else {
                    throw ResultsDatabase.Failure.invalidRecord
                }
                self.revision = revision
            } catch {
                sqlite3_close(handle)
                throw error
            }
        }

        deinit { sqlite3_close(connection.handle) }
    }

    init(database: ResultsDatabase, group: ResultsGroupKey, isCommitted: (@Sendable () -> Bool)? = nil) {
        self.url = database.url
        self.group = group
        self.isCommitted = isCommitted
    }

    private func open() throws -> Reader? {
        if let reader { return reader }
        // A first write can create the file before its schema transaction commits.
        let available = isCommitted?() ?? FileManager.default.fileExists(atPath: url.path)
        guard available else { return nil }
        let opened = try Reader(url: url)
        reader = opened
        return opened
    }

    private var matching: String {
        guard hasLocalEdits else { return "SELECT \(Self.columns) FROM solves WHERE \(Self.groupFilter)" }
        return """
            SELECT \(Self.columns) FROM solves WHERE \(Self.groupFilter)
                AND id NOT IN (SELECT id FROM local_edits)
            UNION ALL
            SELECT \(Self.columns) FROM local_edits WHERE event IS NOT NULL
            """
    }

    private var groupValues: [ResultsConnection.Value] { [.text(group.event), .text(group.id)] }

    func page(offset: Int, limit: Int, includesDNF: Bool) throws -> SolvePage {
        try Task.checkCancellation()
        guard let reader = try open() else {
            return SolvePage(solves: [], total: 0, revision: -1, bestID: nil, worstID: nil)
        }
        let db = reader.connection
        let dataset = matching
        let summary: Summary
        if let cached = self.summary, cached.includesDNF == includesDNF {
            summary = cached.value
        } else {
            let count = try db.read("SELECT count(*) FROM (\(dataset))", values: groupValues) { Int($0.integer(0)) }.first ?? 0
            let score = "CASE WHEN penalty = 'plusTwo' THEN seconds + 2 ELSE seconds END"
            let best = try db.read("""
                SELECT id FROM (\(dataset)) WHERE penalty IS NOT 'dnf'
                ORDER BY \(score), solved_at, id DESC LIMIT 1
                """, values: groupValues) { try $0.uuid(0) }.first
            let dnfClause = includesDNF ? "" : "WHERE penalty IS NOT 'dnf'"
            let worst = try db.read("""
                SELECT id FROM (\(dataset)) \(dnfClause)
                ORDER BY (penalty IS 'dnf') DESC, CASE WHEN penalty IS NOT 'dnf' THEN \(score) END DESC, solved_at DESC, id LIMIT 1
                """, values: groupValues) { try $0.uuid(0) }.first
            summary = Summary(total: count, bestID: best, worstID: worst)
            self.summary = (includesDNF, summary)
        }
        let solves = try db.read("""
            SELECT \(Self.columns) FROM (\(dataset))
            ORDER BY solved_at DESC, id LIMIT ? OFFSET ?
            """, values: groupValues + [.integer(Int64(limit)), .integer(Int64(offset))]) { try $0.solve() }
        return SolvePage(solves: solves, total: summary.total, revision: reader.revision,
                           bestID: summary.bestID, worstID: summary.worstID)
    }

    func reset() {
        reader = nil
        hasLocalEdits = false
        summary = nil
    }

    func applyLocal(_ entries: [ResultsChange.Entry]) throws {
        guard !entries.isEmpty, let reader = try open() else { return }
        let db = reader.connection
        if !hasLocalEdits {
            try db.execute("""
                CREATE TEMP TABLE local_edits (
                    id TEXT PRIMARY KEY NOT NULL, seconds REAL, event TEXT, scramble TEXT,
                    solved_at REAL, penalty TEXT, group_id TEXT
                )
                """)
            hasLocalEdits = true
        }
        try db.write("INSERT OR REPLACE INTO local_edits VALUES (?, ?, ?, ?, ?, ?, ?)", rows: entries) { entry in
            let solve = entry.after.flatMap { ResultsGroupKey($0) == group ? $0 : nil }
            return [.text(entry.id.uuidString), .real(solve?.seconds), .text(solve?.event), .text(solve?.scramble),
                    .real(solve?.date.timeIntervalSinceReferenceDate), .text(solve?.penalty?.rawValue), .text(solve?.groupID)]
        }
        summary = nil
    }

    func window(startingAt id: Solve.ID, count: Int) throws -> [Solve] {
        try Task.checkCancellation()
        guard let reader = try open() else { return [] }
        return try reader.connection.read("""
            WITH scoped AS (\(matching)), anchor AS (SELECT solved_at, id FROM scoped WHERE id = ?)
            SELECT \(Self.columns) FROM scoped
            WHERE solved_at < (SELECT solved_at FROM anchor)
                OR (solved_at = (SELECT solved_at FROM anchor) AND id >= (SELECT id FROM anchor))
            ORDER BY solved_at DESC, id LIMIT ?
            """, values: groupValues + [.text(id.uuidString), .integer(Int64(count))]) { try $0.solve() }
    }

    func allTimes() throws -> [Double?] {
        try Task.checkCancellation()
        guard let reader = try open() else { return [] }
        return try reader.connection.read("""
            SELECT CASE penalty WHEN 'dnf' THEN NULL WHEN 'plusTwo' THEN seconds + 2 ELSE seconds END
            FROM (\(matching)) ORDER BY solved_at DESC, id
            """, values: groupValues) { $0.double(0) }
    }

    func allIDs() throws -> Set<Solve.ID> {
        try Task.checkCancellation()
        guard let reader = try open() else { return [] }
        return Set(try reader.connection.read("SELECT id FROM (\(matching))", values: groupValues) { try $0.uuid(0) })
    }

    func allSolves() throws -> [Solve] {
        try Task.checkCancellation()
        guard let reader = try open() else { return [] }
        return try reader.connection.read("""
            SELECT \(Self.columns) FROM (\(matching)) ORDER BY solved_at DESC, id
            """, values: groupValues) { try $0.solve() }
    }
}
