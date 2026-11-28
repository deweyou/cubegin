import Foundation
import SQLite3
import Testing
@testable import CubeginApp

struct ResultsDatabaseTests {
    @Test func migratesLargeLegacyStoreWithGroupsImportAndSyncHistory() throws {
        try withDatabase { database, legacy in
            let practice = SolveGroup(id: "practice", event: "333", name: "练习", isDefault: true)
            let initial = SolveGroup(id: SolveGroup.initialID(for: "333"), event: "333", name: "", isDefault: false)
            let solves = (0..<8_126).map { index in
                Solve(seconds: Double(index) / 100, event: "333", scramble: "R U",
                      date: Date(timeIntervalSinceReferenceDate: Double(index)), penalty: index == 0 ? .dnf : .plusTwo,
                      groupID: index.isMultiple(of: 2) ? practice.id : nil)
            }
            let replicaID = UUID()
            let deleted = SyncRecord(id: UUID(), revision: 9, replicaID: replicaID, solve: nil)
            let saved = SyncRecord(id: solves[0].id, revision: 3, replicaID: replicaID, solve: solves[0])
            let preference = SyncedMetadata.preference(key: "scramble.standard", values: ["333"])
            let preferenceRecord = SyncRecord(id: preference.id, revision: 5, replicaID: replicaID, solve: nil, metadata: preference)
            let importedAt = Date(timeIntervalSinceReferenceDate: 102)
            let imported = Set(solves.prefix(25).map(\.id))
            let legacyStore = ResultsStore(
                solves: solves, groups: [practice, initial], lastImportedSolveIDs: imported, lastImportDate: importedAt,
                cloudState: .init(replicaID: replicaID, records: Dictionary(uniqueKeysWithValues:
                    [deleted, saved, preferenceRecord].map { ($0.id, $0) })),
                cloudAccount: "test-icloud-account"
            )
            let encoded = try JSONEncoder().encode(legacyStore)
            try encoded.write(to: legacy)

            let migrated = try database.load()

            #expect(migrated.store.solves == solves.sorted(by: Solve.newestFirst))
            #expect(migrated.store.groups == [practice, initial])
            #expect(migrated.store.lastImportedSolveIDs == imported)
            #expect(migrated.store.lastImportDate == importedAt)
            #expect(migrated.store.cloudAccount == legacyStore.cloudAccount)
            #expect(migrated.store.cloudState?.replicaID == replicaID)
            #expect(migrated.store.cloudState?.records == legacyStore.cloudState?.records)
            #expect(try Data(contentsOf: legacy) == encoded)

            try execute("""
                CREATE TRIGGER prevent_unchanged_solve_updates
                BEFORE UPDATE ON solves WHEN OLD.id != '\(solves[0].id.uuidString)'
                BEGIN SELECT RAISE(ABORT, 'Unchanged solve should not be rewritten'); END;
                """, in: database)
            var updated = migrated.store
            let editedIndex = try #require(updated.solves.firstIndex { $0.id == solves[0].id })
            updated.solves[editedIndex].penalty = nil
            updated.solves.removeAll { $0.id == solves[1].id }
            updated.lastImportedSolveIDs?.remove(solves[1].id)
            _ = try database.save(updated, replacing: migrated)

            let reopened = try database.load()
            #expect(reopened.store.solves == updated.solves)
            #expect(reopened.store.lastImportedSolveIDs == updated.lastImportedSolveIDs)
            #expect(reopened.store.cloudState?.records == legacyStore.cloudState?.records)
            #expect(try Data(contentsOf: legacy) == encoded)
        }
    }

    @Test func retriesAnUncommittedMigrationWithoutDiscardingTheLegacyFile() throws {
        try withDatabase { database, legacy in
            let solve = Solve(seconds: 12, event: "333", scramble: "R U")
            let duplicate = try JSONEncoder().encode([solve, solve])
            try duplicate.write(to: legacy)
            #expect(throws: ResultsDatabase.Failure.self) { try database.load() }
            #expect(try Data(contentsOf: legacy) == duplicate)

            try JSONEncoder().encode([solve]).write(to: legacy)
            let migrated = try database.load()
            #expect(migrated.store.solves == [solve])
            _ = try database.save(ResultsStore(), replacing: migrated)
            #expect(try database.load().store.solves.isEmpty)
        }
    }

    @Test func rollsBackAWriteToMultipleTablesAndRejectsAStaleSnapshot() throws {
        try withDatabase { database, _ in
            let first = Solve(seconds: 12, event: "333", scramble: "R U")
            let second = Solve(seconds: 14, event: "333", scramble: "U R")
            let group = SolveGroup(id: "practice", event: "333", name: "Practice", isDefault: true)
            let empty = try database.load()
            let original = try database.save(ResultsStore(solves: [first], groups: [group]), replacing: empty)

            #expect(throws: ResultsDatabase.Failure.self) {
                try database.save(ResultsStore(solves: [second], groups: [group, group]), replacing: original)
            }
            let rolledBack = try database.load()
            #expect(rolledBack.revision == original.revision)
            #expect(rolledBack.store.solves == [first])
            #expect(rolledBack.store.groups == [group])

            _ = try database.save(ResultsStore(solves: [second], groups: [group]), replacing: original)
            #expect(throws: ResultsDatabase.Failure.staleSnapshot) {
                try database.save(ResultsStore(solves: [first]), replacing: original)
            }
            #expect(try database.load().store.solves == [second])
        }
    }

    private func withDatabase(_ body: (ResultsDatabase, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sqlite-results-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ResultsDatabase(url: directory.appending(path: "solves.sqlite")), directory.appending(path: "solves.json"))
    }

    private func execute(_ sql: String, in database: ResultsDatabase) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(database.url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        defer { if let handle { sqlite3_close(handle) } }
        try #require(status == SQLITE_OK)
        try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
}
