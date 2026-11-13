import CryptoKit
import Foundation
import SQLite3
import SwiftUI
import UniformTypeIdentifiers

struct DCTimerBackup: Sendable {
    struct Entry: Sendable {
        let id: UUID
        let milliseconds: Int64
        let penalty: SolvePenalty?
        let scramble: String
        let date: Date
    }

    struct Session: Identifiable, Sendable {
        let id: Int64
        let name: String
        let entries: [Entry]
        var scrambleType: Int64?
    }

    let sessions: [Session]

    enum Failure: LocalizedError {
        case invalidBackup
        case invalidResult
        case noResults

        var errorDescription: String? {
            let language = AppLanguage.saved
            switch self {
            case .invalidBackup: return language.text("无法读取这份备份。请重新选择 DCTimer 的 spdcube.sqlite。", "Couldn’t read this backup. Select spdcube.sqlite from DCTimer and try again.")
            case .invalidResult: return language.text("有些成绩读不出来。请检查 DCTimer 的备份文件。", "Some results could not be read. Check your DCTimer backup.")
            case .noResults: return language.text("这份备份没有成绩。", "This backup has no results.")
            }
        }
    }

    static func read(_ url: URL, timeZone: TimeZone = .current) throws -> Self {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        // DCTimer or the file provider may still own the selected file.
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result { try readDatabase(readableURL, timeZone: timeZone) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.invalidBackup }
        return try result.get()
    }

    private static func readDatabase(_ url: URL, timeZone: TimeZone) throws -> Self {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(connection) }
        guard status == SQLITE_OK, let connection else { throw Failure.invalidBackup }
        try query(connection, "PRAGMA trusted_schema = OFF") { _ in }

        // DCTimer-iOS DCTData stores session zero separately from sessiontb.
        var names: [Int64: String] = [:]
        try query(connection, "SELECT rowid, name FROM sessiontb") {
            names[sqlite3_column_int64($0, 0)] = string($0, 1) ?? ""
        }

        var types: [Int64: Int64] = [:]
        var hasTypeTable = false
        try query(connection, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'scrtypetb'") { _ in
            hasTypeTable = true
        }
        if hasTypeTable {
            try query(connection, "SELECT sesid, type FROM scrtypetb ORDER BY rowid") { row in
                if sqlite3_column_type(row, 0) == SQLITE_INTEGER, sqlite3_column_type(row, 1) == SQLITE_INTEGER {
                    types[sqlite3_column_int64(row, 0)] = sqlite3_column_int64(row, 1)
                }
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var sessions: [Int64: [Entry]] = [:]
        try query(connection, "SELECT sesid, rest, resp, scr, date, id FROM resulttb ORDER BY id") { row in
            guard sqlite3_column_type(row, 0) == SQLITE_INTEGER,
                  sqlite3_column_type(row, 1) == SQLITE_INTEGER,
                  sqlite3_column_type(row, 2) == SQLITE_INTEGER,
                  sqlite3_column_type(row, 5) == SQLITE_INTEGER,
                  let timestamp = string(row, 4), let date = formatter.date(from: timestamp) else {
                throw Failure.invalidResult
            }
            let milliseconds = sqlite3_column_int64(row, 1)
            guard milliseconds >= 0 else { throw Failure.invalidResult }
            let penalty: SolvePenalty?
            switch sqlite3_column_int64(row, 2) {
            case 0: penalty = nil
            case 1: penalty = .plusTwo
            case 2: penalty = .dnf
            default: throw Failure.invalidResult
            }
            let sessionID = sqlite3_column_int64(row, 0)
            let rowID = sqlite3_column_int64(row, 5)
            let scramble = string(row, 3) ?? ""
            let id = solveID(session: sessionID, row: rowID, milliseconds: milliseconds, timestamp: timestamp, scramble: scramble)
            let entry = Entry(id: id, milliseconds: milliseconds, penalty: penalty, scramble: scramble, date: date)
            sessions[sessionID, default: []].append(entry)
        }
        let sessionIDs = Set(names.keys).union(sessions.keys).sorted()
        return Self(sessions: sessionIDs.map { id in
            Session(id: id, name: names[id] ?? "", entries: sessions[id] ?? [], scrambleType: types[id])
        })
    }

    private static func solveID(session: Int64, row: Int64, milliseconds: Int64, timestamp: String, scramble: String) -> UUID {
        // Use the source wall time and raw scramble so retries in a new time zone or import mode keep the same ID.
        let key = "dctimer-ios:\(session):\(row):\(milliseconds):\(timestamp):\(scramble)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func query(_ connection: OpaquePointer, _ sql: String, _ row: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure.invalidBackup
        }
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try row(statement)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw Failure.invalidBackup }
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
}

struct DCTimerImportPlan: Identifiable, Sendable {
    struct Session: Identifiable, Sendable {
        let id: Int64
        let name: String
        let event: String?
        let solves: [Solve]
        let skipped: Int
        let converted: Int
    }

    let id = UUID()
    let sessions: [Session]

    // WCA IDs follow DCTimer-Android's Scrambler table. Positive IDs below
    // follow the categories and subsets in DCTimer-iOS's Scrambler table.
    private static let events: [Int64: String] = [
        -32: "333", -31: "444", -30: "555", -29: "222", -28: "333bld", -27: "333oh",
        -24: "minx", -23: "pyram", -22: "sq1", -21: "clock", -20: "skewb", -19: "666",
        -18: "777", -17: "444bld", -16: "555bld",
        0: "222", 32: "333", 35: "333.ll", 64: "444", 96: "555", 128: "666", 160: "777",
        192: "minx", 224: "pyram", 256: "sq1", 288: "clock", 320: "skewb", 517: "fto",
    ]

    init(backup: DCTimerBackup, validate: (String, String) throws -> Bool) throws {
        guard backup.sessions.contains(where: { !$0.entries.isEmpty }) else { throw DCTimerBackup.Failure.noResults }
        sessions = try backup.sessions.filter { !$0.entries.isEmpty }.map { source in
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name != "2-7", let event = source.scrambleType.flatMap({ Self.events[$0] }) else {
                return Session(id: source.id, name: name, event: nil, solves: [], skipped: source.entries.count, converted: 0)
            }
            var solves: [Solve] = []
            var converted = 0
            for entry in source.entries {
                let trimmed = entry.scramble.trimmingCharacters(in: .whitespacesAndNewlines)
                let scramble = event == "clock" ? Self.normalizeClock(trimmed) : trimmed
                guard !scramble.isEmpty, try validate(event, scramble) else { continue }
                if scramble != trimmed { converted += 1 }
                solves.append(Solve(id: entry.id, seconds: Double(entry.milliseconds) / 1000, event: event,
                                    scramble: scramble, date: entry.date, penalty: entry.penalty))
            }
            return Session(id: source.id, name: name, event: event, solves: solves,
                           skipped: source.entries.count - solves.count, converted: converted)
        }
    }

    private static func normalizeClock(_ scramble: String) -> String {
        var tokens = scramble.split(whereSeparator: \.isWhitespace)
        let pins: Set<Substring> = ["UR", "UL", "DR", "DL"]
        let count = tokens.count
        while let last = tokens.last, pins.contains(last) { tokens.removeLast() }
        return tokens.count == count ? scramble : tokens.joined(separator: " ")
    }
}

enum DCTimerImportDestination: String, CaseIterable {
    case originalSessions
    case defaultGroups

    func title(in language: AppLanguage) -> String {
        switch self {
        case .originalSessions: language.text("按原分组新建", "Create a group for each session")
        case .defaultGroups: language.text("放入各项目的默认分组", "Add to each event’s default group")
        }
    }
}

struct ResultsImportView: View {
    let model: TimerModel
    @Environment(\.locale) private var locale
    @State private var isPicking = false
    @State private var isReading = false
    @State private var plan: DCTimerImportPlan?
    @State private var notice: String?
    @State private var noticeIcon = "exclamationmark.circle"
    @State private var importedCount: Int?
    @State private var confirmUndo = false

    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        Form {
            Section {
                Button {
                    chooseBackup()
                } label: {
                    HStack {
                        Text(language.text("从 DCTimer 导入", "Import from DCTimer"))
                        Spacer()
                        if isReading { ProgressView() }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("settings.results.importDCTimer")
                .disabled(isReading || model.started != nil)
            } footer: {
                Text(language.text("选择文件：我的 iPhone → DCTimer² → spdcube.sqlite",
                                   "Choose: On My iPhone → DCTimer² → spdcube.sqlite"))
            }
            if model.lastImportCount > 0 {
                Section {
                    Button(language.text("撤回上次导入", "Undo last import"), role: .destructive) {
                        confirmUndo = true
                    }
                    .accessibilityIdentifier("settings.import.undo")
                    .disabled(isReading || model.started != nil)
                } footer: {
                    if let date = model.lastImportDate {
                        Text("DCTimer · " + date.formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
                            .accessibilityIdentifier("settings.import.lastImportDetails")
                    } else {
                        Text("DCTimer")
                    }
                }
            }
        }
        .navigationTitle(language.text("导入", "Import"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.item]) { selection in
            switch selection {
            case .success(let url): read(url)
            case .failure:
                noticeIcon = "exclamationmark.circle"
                notice = language.text("无法打开文件，请重试。", "Couldn’t open the file. Try again.")
            }
        }
        .sheet(item: $plan, onDismiss: {
            if let count = importedCount {
                noticeIcon = "checkmark.circle.fill"
                notice = language.text("已导入 \(count.formatted()) 条成绩。",
                                       count == 1 ? "Imported 1 result." : "Imported \(count.formatted()) results.")
                importedCount = nil
            }
        }) { plan in
            DCTimerImportPreview(plan: plan, model: model, language: language) { importedCount = $0 }
        }
        .alert(language.text("撤回上次导入？", "Undo last import?"), isPresented: $confirmUndo) {
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("撤回", "Undo"), role: .destructive) {
                if let count = model.undoLastImport() {
                    noticeIcon = "checkmark.circle.fill"
                    notice = language.text("已移除 \(count.formatted()) 条成绩。",
                                           count == 1 ? "Removed 1 result." : "Removed \(count.formatted()) results.")
                } else {
                    noticeIcon = "exclamationmark.circle"
                    notice = model.error ?? language.text("无法撤回导入。", "Couldn’t undo the import.")
                }
            }
            .accessibilityIdentifier("settings.import.confirmUndo")
        } message: {
            let count = model.lastImportCount
            Text(language.text("将移除上次导入的 \(count.formatted()) 条成绩。",
                               count == 1 ? "This will remove 1 result from the last import."
                                   : "This will remove \(count.formatted()) results from the last import."))
        }
        .overlay(alignment: .bottom) {
            if let notice {
                Label(notice, systemImage: noticeIcon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.24)))
                    .padding()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("import.notice")
                    .onAppear {
                        AccessibilityNotification.Announcement(notice).post()
                    }
            }
        }
        .task(id: notice) {
            guard notice != nil else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                notice = nil
            } catch {}
        }
    }

    private func chooseBackup() {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let session = environment["CUBEGIN_UI_TEST_SESSION"], UUID(uuidString: session) != nil,
           let fixture = environment["CUBEGIN_UI_TEST_DCTIMER_BACKUP"],
           let data = Data(base64Encoded: fixture) {
            let url = FileManager.default.temporaryDirectory.appending(path: "dctimer-\(session).sqlite")
            do {
                try data.write(to: url, options: .atomic)
                read(url, removeAfterRead: true)
            } catch {
                noticeIcon = "exclamationmark.circle"
                notice = error.localizedDescription
            }
            return
        }
#endif
        isPicking = true
    }

    private func read(_ url: URL, removeAfterRead: Bool = false) {
        notice = nil
        noticeIcon = "exclamationmark.circle"
        isReading = true
        Task {
            defer { isReading = false }
            do {
                plan = try await Task.detached(priority: .userInitiated) {
                    defer { if removeAfterRead { try? FileManager.default.removeItem(at: url) } }
                    return try DCTimerImportPlan(backup: DCTimerBackup.read(url), validate: Engine.acceptsImportedScramble)
                }.value
            } catch let error as DCTimerBackup.Failure {
                notice = error.localizedDescription
            } catch {
                notice = language.text("无法读取备份，请重新选择文件。", "Couldn’t read the backup. Select the file again.")
            }
        }
    }
}

private struct DCTimerImportPreview: View {
    let plan: DCTimerImportPlan
    let model: TimerModel
    let language: AppLanguage
    let onImport: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination = DCTimerImportDestination.originalSessions
    @State private var showError = false
    @State private var excludedSessions: Set<Int64> = []

    var body: some View {
        let existingIDs = Set(model.solves.map(\.id))
        let matched = plan.sessions.filter { $0.event != nil }
        let unmatched = plan.sessions.filter { $0.event == nil }
        let incompatible = matched.reduce(0) { $0 + $1.skipped }
        let converted = matched.reduce(0) { $0 + $1.converted }
        let newCounts = Dictionary(uniqueKeysWithValues: matched.map { session in
            (session.id, session.solves.count { !existingIDs.contains($0.id) })
        })
        let newSessions = matched.filter { newCounts[$0.id, default: 0] > 0 }
        let duplicates = matched.reduce(0) { $0 + $1.solves.count - newCounts[$1.id, default: 0] }
        let excludedCount = newSessions.filter { excludedSessions.contains($0.id) }
            .reduce(0) { $0 + newCounts[$1.id, default: 0] }
        let importCount = newCounts.values.reduce(0, +) - excludedCount

        NavigationStack {
            Form {
                Section {
                    LabeledContent(language.text("可导入", "Ready to import")) {
                        Text(importCount.formatted())
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("dctimer.preview.total")
                    LabeledContent(language.text("将跳过", "To skip"),
                                   value: (unmatched.reduce(0) { $0 + $1.skipped } + incompatible + duplicates + excludedCount).formatted())
                    if excludedCount > 0 {
                        LabeledContent(language.text("未选分组", "Unselected groups"), value: excludedCount.formatted())
                            .accessibilityIdentifier("dctimer.preview.excluded")
                    }
                    if incompatible > 0 {
                        LabeledContent(language.text("打乱与项目不符", "Incompatible scrambles"),
                                       value: incompatible.formatted())
                    }
                    if duplicates > 0 {
                        LabeledContent(language.text("已导入过", "Already imported"), value: duplicates.formatted())
                            .accessibilityIdentifier("dctimer.preview.duplicates")
                    }
                } header: {
                    Text(language.text("成绩概览", "Results summary"))
                } footer: {
                    if converted > 0 {
                        Text(language.text("已适配 \(converted.formatted()) 条魔表打乱。",
                                           "Updated \(converted.formatted()) Clock scrambles for import."))
                    }
                }
                Section {
                    Picker(language.text("分组", "Groups"), selection: $destination) {
                        ForEach(DCTimerImportDestination.allCases, id: \.self) { option in
                            Text(option.title(in: language)).tag(option)
                        }
                    }
                    .accessibilityIdentifier("dctimer.destination")
                } header: {
                    Text(language.text("导入位置", "Destination"))
                } footer: {
                    if duplicates > 0 {
                        Text(language.text("仅对新增成绩生效。",
                                           "Applies to new results only."))
                    }
                }
                if !unmatched.isEmpty {
                    Section(language.text("无法匹配的分组", "Skipped sessions")) {
                        ForEach(unmatched) { session in
                            LabeledContent(name(for: session), value: session.skipped.formatted())
                        }
                    }
                }
                if !newSessions.isEmpty {
                    Section(language.text("选择要导入的分组", "Select groups to import")) {
                        ForEach(newSessions) { session in
                            let selected = !excludedSessions.contains(session.id)
                            Button {
                                if selected { excludedSessions.insert(session.id) }
                                else { excludedSessions.remove(session.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(name(for: session))
                                        if let event = session.event {
                                            let title = ScrambleCatalog.title(event, in: language)
                                            let count = newCounts[session.id, default: 0].formatted()
                                            Text(language.text("\(title) · \(count) 条", "\(title) · \(count)"))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("dctimer.preview.group.\(session.id)")
                        }
                    }
                }
            }
            .navigationTitle(language.text("导入预览", "Import preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("导入", "Import")) {
                        do {
                            onImport(try model.importDCTimer(plan, destination: destination, language: language,
                                                           excluding: excludedSessions))
                            dismiss()
                        } catch {
                            showError = true
                        }
                    }
                    .accessibilityIdentifier("dctimer.confirmImport")
                    .disabled(importCount == 0 || model.started != nil)
                }
            }
            .alert(language.text("导入失败", "Import failed"), isPresented: $showError) {
                Button(language.text("好", "OK"), role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
        }
    }

    private func name(for session: DCTimerImportPlan.Session) -> String {
        if !session.name.isEmpty { return session.name }
        return session.id == 0 ? language.text("默认分组", "Default session")
            : language.text("分组 \(session.id)", "Session \(session.id)")
    }
}
