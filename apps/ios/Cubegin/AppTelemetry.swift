import Foundation
import CloudKit

#if CUBEGIN_TELEMETRY
import FirebaseAnalytics
import FirebaseCore
import SentrySwift
#endif

enum FailedOperation: String {
    case loadResults = "load_results"
    case saveSolve = "save_solve"
    case editPenalty = "edit_penalty"
    case moveSolves = "move_solves"
    case deleteSolves = "delete_solves"
    case clearResults = "clear_results"
    case saveGroup = "save_group"
    case reorderGroups = "reorder_groups"
    case deleteGroup = "delete_group"
    case importDCTimer = "import_dctimer"
    case undoImport = "undo_import"
    case generateScramble = "generate_scramble"
    case loadAssist = "load_assist"
    case loadDiagram = "load_diagram"
    case renderDiagram = "render_diagram"
    case playInspectionAudio = "play_inspection_audio"
}

enum FailureImpact: String {
    case blocked
    case degraded
}

struct OperationFailure {
    static let eventName = "operation_failed"

    let operation: FailedOperation
    let reason: FailureReason
    let impact: FailureImpact

    var fields: [String: String] {
        [
            "operation": operation.rawValue,
            "reason": reason.rawValue,
            "impact": impact.rawValue
        ]
    }
}

enum FailureReason: String {
    case readFailed = "read_failed"
    case decodeFailed = "decode_failed"
    case encodeFailed = "encode_failed"
    case writeFailed = "write_failed"
    case diskFull = "disk_full"
    case openFailed = "open_failed"
    case invalidBackup = "invalid_backup"
    case invalidResult = "invalid_result"
    case emptyBackup = "empty_backup"
    case incompatibleBackup = "incompatible_backup"
    case engineFailed = "engine_failed"
    case validationFailed = "validation_failed"
    case webNavigationFailed = "web_navigation_failed"
    case webContentTerminated = "web_content_terminated"
    case audioResourceMissing = "audio_resource_missing"
    case audioDecodeFailed = "audio_decode_failed"
    case audioPrepareFailed = "audio_prepare_failed"
    case audioScheduleFailed = "audio_schedule_failed"

    func needsDiagnostic(for operation: FailedOperation) -> Bool {
        if operation == .loadDiagram || (operation == .importDCTimer && self == .readFailed) { return false }
        return switch self {
        case .readFailed, .decodeFailed, .encodeFailed, .writeFailed, .engineFailed, .validationFailed,
             .webNavigationFailed, .webContentTerminated, .audioResourceMissing, .audioDecodeFailed: true
        case .diskFull, .openFailed, .invalidBackup, .invalidResult, .emptyBackup, .incompatibleBackup,
             .audioPrepareFailed, .audioScheduleFailed: false
        }
    }

    static func writingResults(_ error: Error) -> Self {
        let failure = error as NSError
        return failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError
            || failure.domain == NSPOSIXErrorDomain && failure.code == Int(POSIXErrorCode.ENOSPC.rawValue)
            ? .diskFull : .writeFailed
    }
}

enum FeatureUse: Equatable {
    case assistOpened, assistMethodSelected(AssistMethod), assistReordered
    case assistMethodViewed(AssistMethod)
    case celebrationReplayed
    case groupCreated, groupReordered, groupSwitched
    case resultsMoved(ResultMoveScope)
    case chartSelected(ResultsChartMode), chartViewed(ResultsChartMode)
    case dctimerImportUndone
    case settingChanged(from: FeatureSettingValue, to: FeatureSettingValue)
    case syncRequested(isRetry: Bool)
    case resultsCleared(ClearResultsScope)

    var fields: [String: String] {
        switch self {
        case .assistOpened:
            ["feature": "assist_formula", "action": "open"]
        case .assistMethodSelected(let method):
            ["feature": "assist_formula", "action": "select_method", "method": method.rawValue]
        case .assistMethodViewed(let method):
            ["feature": "assist_formula", "action": "view_method", "method": method.rawValue]
        case .assistReordered:
            ["feature": "assist_formula", "action": "reorder"]
        case .celebrationReplayed:
            ["feature": "celebration", "action": "replay"]
        case .groupCreated:
            ["feature": "result_group", "action": "create"]
        case .groupReordered:
            ["feature": "result_group", "action": "reorder"]
        case .groupSwitched:
            ["feature": "result_group", "action": "switch"]
        case .resultsMoved(let scope):
            ["feature": "result_group", "action": "move_results", "scope": scope.rawValue]
        case .chartSelected(let mode):
            ["feature": "statistics_chart", "action": "select", "chart_type": mode.rawValue]
        case .chartViewed(let mode):
            ["feature": "statistics_chart", "action": "view", "chart_type": mode.rawValue]
        case .dctimerImportUndone:
            ["feature": "dctimer_import", "action": "undo"]
        case .settingChanged(let previous, let current):
            ["feature": "settings", "action": "change", "setting": current.key,
             "setting_value": current.value, "previous_value": previous.value]
        case .syncRequested(let isRetry):
            ["feature": "settings", "action": isRetry ? "sync_retry" : "sync_refresh"]
        case .resultsCleared(let scope):
            ["feature": "settings", "action": "clear_results", "scope": scope.rawValue]
        }
    }
}

enum ClearResultsScope: String {
    case all, selectedGroups = "selected_groups"
}

enum ResultMoveScope: String {
    case single, batch
}

enum FeatureSettingValue: Equatable {
    case theme(AppTheme), language(AppLanguage?), iCloudSync(Bool)
    case keepScreenOn(Bool), entryMethod(SolveEntryMethod), display(TimerDisplay), haptics(Bool)
    case startDelay(Int), inspection(Bool), trainingInspection(Bool), inspectionVoice(InspectionVoice)
    case swipe(TimerSwipeDirection, TimerSwipeAction), includeDNF(Bool)

    var key: String {
        switch self {
        case .theme: "theme"
        case .language: "language"
        case .iCloudSync: "icloud_sync"
        case .keepScreenOn: "keep_screen_on"
        case .entryMethod: "entry_method"
        case .display: "timer_display"
        case .haptics: "timer_haptics"
        case .startDelay: "start_delay_tenths"
        case .inspection: "wca_inspection"
        case .trainingInspection: "training_inspection"
        case .inspectionVoice: "inspection_voice"
        case .swipe(let direction, _): "swipe_" + direction.rawValue
        case .includeDNF: "include_dnf_in_worst"
        }
    }

    var value: String {
        switch self {
        case .theme(let theme): theme.rawValue
        case .language(let language): language?.rawValue ?? "system"
        case .entryMethod(let method): method.rawValue
        case .display(let display): display.rawValue
        case .startDelay(let tenths): String(min(20, max(0, tenths)))
        case .inspectionVoice(let voice): voice.rawValue
        case .swipe(_, let action): action.rawValue
        case .iCloudSync(let enabled), .keepScreenOn(let enabled), .haptics(let enabled),
             .inspection(let enabled), .trainingInspection(let enabled), .includeDNF(let enabled):
            enabled ? "on" : "off"
        }
    }
}

enum ProductEvent: Equatable {
    case solveSaved(project: String, entryMethod: SolveEntryMethod)
    case statisticsViewed
    case dctimerImportStarted
    case dctimerImportCompleted
    case wcaInspectionStarted(InspectionVoice)
    case solveListViewed(includesDNF: Bool)
    case featureUsed(FeatureUse)

    var name: String {
        switch self {
        case .solveSaved: "solve_saved"
        case .statisticsViewed: "statistics_viewed"
        case .dctimerImportStarted: "dctimer_import_started"
        case .dctimerImportCompleted: "dctimer_import_completed"
        case .wcaInspectionStarted: "wca_inspection_started"
        case .solveListViewed: "solve_list_viewed"
        case .featureUsed: "feature_used"
        }
    }

    var fields: [String: String] {
        switch self {
        case .solveSaved(let project, let entryMethod):
            let base = ScrambleCatalog.training.contains { $0.id == project }
                ? project.split(separator: ".", maxSplits: 1).first.map(String.init)
                : project
            let supported = ScrambleCatalog.standard.first { $0.id == base }
            return ["cube_event": supported.map { "event_\($0.id)" } ?? "other",
                    "entry_method": entryMethod.rawValue]
        case .wcaInspectionStarted(let voice):
            return ["inspection_voice": voice.rawValue]
        case .solveListViewed(let includesDNF):
            return ["include_dnf_in_worst": includesDNF ? "on" : "off"]
        case .featureUsed(let use):
            return use.fields
        case .statisticsViewed, .dctimerImportStarted, .dctimerImportCompleted:
            return [:]
        }
    }
}

enum CloudAnalyticsIdentityLookup: Sendable {
    case found(UUID), missing, unavailable
}

@MainActor
final class AnalyticsIdentityStartup {
    private var lookupTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?

    func start(timeout: Duration = .seconds(1),
               lookup: @escaping @Sendable () async -> CloudAnalyticsIdentityLookup,
               create: @escaping @Sendable () async -> UUID?,
               apply: @escaping @MainActor (UUID?) -> Void) {
        guard lookupTask == nil else { return }
        var startedWithoutID = false
        let startWithoutID = {
            guard !startedWithoutID else { return }
            startedWithoutID = true
            apply(nil)
        }
        let deadline = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            startWithoutID()
        }
        deadlineTask = deadline
        lookupTask = Task { [weak self] in
            let result = await lookup()
            guard !Task.isCancelled else { return }
            deadline.cancel()
            defer {
                if !Task.isCancelled {
                    self?.lookupTask = nil
                    self?.deadlineTask = nil
                }
            }
            switch result {
            case .found(let id):
                apply(id)
            case .unavailable:
                startWithoutID()
            case .missing:
                startWithoutID()
                if let id = await create(), !Task.isCancelled { apply(id) }
            }
        }
    }

    func cancel() {
        lookupTask?.cancel()
        deadlineTask?.cancel()
        lookupTask = nil
        deadlineTask = nil
    }
}

#if CUBEGIN_TELEMETRY
private actor CloudAnalyticsIdentityStore {
    static let productionContainerID = "iCloud.io.github.deweyou.cubegin"
    private static let recordID = CKRecord.ID(recordName: "cubegin-analytics-user-id")
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
    }

    func lookup() async -> CloudAnalyticsIdentityLookup {
        do {
            return .found(try await fetchID())
        } catch let error as CKError where error.code == .unknownItem {
            return .missing
        } catch {
            return .unavailable
        }
    }

    func create() async -> UUID? {
        do {
            let account = try await container.userRecordID()
            let record = CKRecord(recordType: "CubeginAnalyticsIdentity", recordID: Self.recordID)
            let id = UUID()
            record["uuid"] = id.uuidString.lowercased()
            try Task.checkCancellation()
            let resolved: UUID
            do {
                let result = try await database.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged
                )
                guard let saved = result.saveResults[Self.recordID] else { return nil }
                _ = try saved.get()
                resolved = id
            } catch let error as CKError where error.code == .serverRecordChanged {
                resolved = try await fetchID()
            }
            guard try await container.userRecordID() == account, !Task.isCancelled else { return nil }
            return resolved
        } catch {
            return nil
        }
    }

    private func fetchID() async throws -> UUID {
        let record = try await database.record(for: Self.recordID)
        guard let raw = record["uuid"] as? String, let id = UUID(uuidString: raw) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return id
    }
}
#endif

@MainActor
enum AppTelemetry {
    enum SharingChoice: String {
        case undecided, declined, allowed
    }

    static let sharingChoiceKey = "telemetry.diagnosticsAndUsageChoice"
    private static let installationIDKey = "telemetry.installationID"

    static let sharingDefaults: UserDefaults = {
#if DEBUG && targetEnvironment(simulator)
        if previewsSharingConsent,
           let session = ProcessInfo.processInfo.environment["CUBEGIN_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)),
           let defaults = UserDefaults(suiteName: "telemetry.consent-preview.\(session.uuidString)") {
            return defaults
        }
#endif
        return .standard
    }()

    static var deviceID: String { deviceID(in: .standard) }

    static func deviceID(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: installationIDKey), UUID(uuidString: stored) != nil {
            return stored
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: installationIDKey)
        return id
    }

    static var supportUserID: UUID? {
#if CUBEGIN_TELEMETRY
        boundUserID
#else
        nil
#endif
    }

    static var supportIdentifiers: String {
        formatSupportIdentifiers(deviceID: deviceID, userID: supportUserID)
    }

    static func formatSupportIdentifiers(deviceID: String, userID: UUID?) -> String {
        let deviceLine = "did: \(deviceID)"
        guard let userID else { return deviceLine }
        return deviceLine + "\nuid: \(userID.uuidString.lowercased())"
    }

    static var showsSharingPreference: Bool {
#if DEBUG
        return previewsSharingConsent || (isDeviceQA && exercisesQAConsent)
#else
        return supportsReporting && (
            Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
                || Bundle.main.url(forResource: "sentry-dsn", withExtension: "txt") != nil
        )
#endif
    }

#if DEBUG
    private static var previewsSharingConsent: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-cubegin-show-telemetry-consent")
#else
        false
#endif
    }
#endif

    static func sharingChoice(in defaults: UserDefaults = sharingDefaults) -> SharingChoice {
        guard let stored = defaults.string(forKey: sharingChoiceKey) else { return .undecided }
        return SharingChoice(rawValue: stored) ?? .undecided
    }

    static func chooseSharing(_ choice: SharingChoice, in defaults: UserDefaults = sharingDefaults) {
        defaults.set(choice.rawValue, forKey: sharingChoiceKey)
        setEnabled(choice == .allowed)
    }

    private static var supportsReporting: Bool {
#if CUBEGIN_TELEMETRY && !targetEnvironment(simulator)
        let process = ProcessInfo.processInfo
        guard process.environment["XCTestConfigurationFilePath"] == nil,
              process.environment["CUBEGIN_UI_TEST_SESSION"] == nil else { return false }
#if DEBUG
        return isDeviceQA
#else
        return Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin"
#endif
#else
        return false
#endif
    }

#if DEBUG
    private static var exercisesQAConsent: Bool {
        ProcessInfo.processInfo.arguments.contains("-cubegin-telemetry-qa-consent")
    }

    static var isDeviceQA: Bool {
        Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin.dev"
            && ProcessInfo.processInfo.arguments.contains("-cubegin-telemetry-qa")
    }
#endif

    static func startFromPreferences() {
#if DEBUG
        setEnabled(isDeviceQA && (!exercisesQAConsent || sharingChoice() == .allowed))
#else
        setEnabled(sharingChoice() == .allowed)
#endif
    }

    static func refreshCloudIdentity() {
#if CUBEGIN_TELEMETRY
        guard analyticsRequested, boundUserID == nil else { return }
        guard ICloudSyncPreference.isEnabled(in: .standard), let store = cloudIdentityStore else {
            applyAnalyticsIdentity(nil)
            return
        }
        identityStartup.start(lookup: { await store.lookup() }, create: { await store.create() },
                              apply: applyAnalyticsIdentity)
#endif
    }

    static func cloudIdentityDidChange() {
#if CUBEGIN_TELEMETRY
        guard analyticsRequested else { return }
        identityStartup.cancel()
        applyAnalyticsIdentity(nil)
        refreshCloudIdentity()
#endif
    }

    private static func setEnabled(_ enabled: Bool) {
#if CUBEGIN_TELEMETRY
        guard supportsReporting else { return }
        if enabled {
            startReporting()
        } else {
            analyticsRequested = false
            identityStartup.cancel()
            pendingAnalyticsEvents.removeAll()
            boundUserID = nil
            if analyticsEnabled {
                Analytics.setUserID(nil)
                Analytics.setAnalyticsCollectionEnabled(false)
                Analytics.resetAnalyticsData()
                analyticsEnabled = false
            }
            if sentryEnabled {
                SentrySDK.close()
                sentryEnabled = false
                lastReports.removeAll()
            }
        }
#endif
    }

    static func analyticsParameters(_ fields: [String: String]) -> [String: String] {
        var parameters = fields
        parameters["app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return parameters
    }

    static func record(_ event: ProductEvent) {
#if CUBEGIN_TELEMETRY
        recordAnalyticsEvent(event.name, fields: event.fields)
#endif
    }

    static func record(_ operation: FailedOperation, _ reason: FailureReason, impact: FailureImpact = .blocked) {
#if CUBEGIN_TELEMETRY
        let failure = OperationFailure(operation: operation, reason: reason, impact: impact)
        recordAnalyticsEvent(OperationFailure.eventName, fields: failure.fields)
        guard sentryEnabled, reason.needsDiagnostic(for: operation) else { return }
        let key = "\(operation.rawValue).\(reason.rawValue)"
        let now = ContinuousClock.now
        if let last = lastReports[key], last.duration(to: now) < .seconds(60) { return }
        lastReports[key] = now

        // Rebuild the error from known values. Cocoa and engine errors can contain paths or user data.
        let error = NSError(domain: "Cubegin.\(key)", code: 1, userInfo: [
            NSLocalizedDescriptionKey: key
        ])
        SentrySDK.capture(error: error) { scope in
            scope.setTags(failure.fields)
            scope.setFingerprint([key])
        }
#endif
    }

#if CUBEGIN_TELEMETRY
    private static var analyticsEnabled = false
    private static var analyticsRequested = false
    private static var boundUserID: UUID?
    private static var pendingAnalyticsEvents: [(name: String, parameters: [String: String])] = []
    private static let identityStartup = AnalyticsIdentityStartup()
    private static var sentryEnabled = false
    private static var lastReports: [String: ContinuousClock.Instant] = [:]

    private static let cloudIdentityStore: CloudAnalyticsIdentityStore? = {
#if targetEnvironment(simulator)
        nil
#elseif DEBUG
        CloudKitResultsTransport.isAvailable
            ? CloudAnalyticsIdentityStore(containerID: CloudKitResultsTransport.containerID)
            : nil
#else
        CloudAnalyticsIdentityStore(containerID: CloudAnalyticsIdentityStore.productionContainerID)
#endif
    }()

    private static func recordAnalyticsEvent(_ name: String, fields: [String: String]) {
        guard analyticsRequested else { return }
        let parameters = analyticsParameters(fields)
        if analyticsEnabled {
            Analytics.logEvent(name, parameters: parameters)
        } else if pendingAnalyticsEvents.count < 50 {
            pendingAnalyticsEvents.append((name, parameters))
        }
    }

    private static func applyAnalyticsIdentity(_ userID: UUID?) {
        guard analyticsRequested else { return }
        if analyticsEnabled {
            guard userID != boundUserID else { return }
            Analytics.setUserID(userID?.uuidString.lowercased())
        } else {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            // Firebase drops user-property writes while collection is disabled.
            Analytics.setAnalyticsCollectionEnabled(true)
            Analytics.setUserID(userID?.uuidString.lowercased())
            analyticsEnabled = true
        }
        boundUserID = userID
        let pending = pendingAnalyticsEvents
        pendingAnalyticsEvents.removeAll()
        for event in pending { Analytics.logEvent(event.name, parameters: event.parameters) }
    }

    private static func startReporting() {
        let id = deviceID
        if !analyticsRequested, Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            analyticsRequested = true
            refreshCloudIdentity()
        }
        if !sentryEnabled,
           let url = Bundle.main.url(forResource: "sentry-dsn", withExtension: "txt"),
           let dsn = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !dsn.isEmpty {
            SentrySDK.start { options in
                options.dsn = dsn
                options.sendDefaultPii = false
                options.maxBreadcrumbs = 0
                options.enableAutoBreadcrumbTracking = false
                options.enableWatchdogTerminationTracking = false
                options.enableAppHangTracking = false
                options.enableAutoPerformanceTracing = false
                options.enableCaptureFailedRequests = false
                options.enableNetworkTracking = false
                options.enableSwizzling = false
                options.enableAutoSessionTracking = false
                options.attachStacktrace = true
#if DEBUG
                options.environment = "device_qa"
                options.debug = true
#else
                options.environment = "production"
#endif
            }
            SentrySDK.setUser(User(userId: id))
            sentryEnabled = true
        }
    }
#endif
}
