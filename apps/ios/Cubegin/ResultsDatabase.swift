import Foundation
import SQLite3

struct ResultsStore: Codable {
    var solves: [Solve] = []
    var groups: [SolveGroup] = []
    var lastImportedSolveIDs: Set<Solve.ID>?
    var lastImportDate: Date?
    var cloudState: ResultsSyncReplica.State?
    var cloudAccount: String?
}

struct ResultsDatabase {
    struct Snapshot {
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
            try database.transaction {
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
                return try readSnapshot(from: database)
            }
        }
    }

    func save(_ store: ResultsStore, replacing previous: Snapshot) throws -> Snapshot {
        let revision = (previous.revision ?? -1) + 1
        try withDatabase(create: previous.revision == nil) { database in
            try database.transaction {
                if let expected = previous.revision {
                    let stored = try database.read("SELECT revision FROM results_info WHERE singleton = 1") { $0.integer(0) }
                    guard stored.first == expected else { throw Failure.staleSnapshot }
                } else {
                    guard try schemaVersion(in: database) == 0, !FileManager.default.fileExists(atPath: legacyURL.path) else {
                        throw Failure.staleSnapshot
                    }
                    try database.execute(Self.schema)
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
            let penalty: SolvePenalty?
            if let rawPenalty = try row.text(5) {
                guard let value = SolvePenalty(rawValue: rawPenalty) else { throw Failure.invalidRecord }
                penalty = value
            } else {
                penalty = nil
            }
            return try Solve(id: row.uuid(0), seconds: row.requiredDouble(1), event: row.requiredText(2),
                             scramble: row.requiredText(3), date: Date(timeIntervalSinceReferenceDate: row.requiredDouble(4)),
                             penalty: penalty, groupID: row.text(6))
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

    func read<T>(_ sql: String, _ decode: (ResultsRow) throws -> T) throws -> [T] {
        try statement(sql) { handle in
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

    func blob(_ index: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(handle, index) else { throw ResultsDatabase.Failure.invalidRecord }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, index)))
    }
}
