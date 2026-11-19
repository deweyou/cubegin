import Foundation

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
    static let schemaVersion = "1"

    let operation: FailedOperation
    let reason: FailureReason
    let impact: FailureImpact

    var fields: [String: String] {
        [
            "operation": operation.rawValue,
            "reason": reason.rawValue,
            "impact": impact.rawValue,
            "schema_version": Self.schemaVersion
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

@MainActor
enum AppTelemetry {
    static let consentKey = "telemetry.diagnosticsEnabled"
    private static let installationIDKey = "telemetry.installationID"

    static var installationID: String { installationID(in: .standard) }

    static func installationID(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: installationIDKey), UUID(uuidString: stored) != nil {
            return stored
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: installationIDKey)
        return id
    }

    static var showsDiagnosticsPreference: Bool {
#if DEBUG
        return false
#else
        return supportsReporting && (
            Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
                || Bundle.main.url(forResource: "sentry-dsn", withExtension: "txt") != nil
        )
#endif
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
    static var isDeviceQA: Bool {
        Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin.dev"
            && ProcessInfo.processInfo.arguments.contains("-cubegin-telemetry-qa")
    }
#endif

    static func startFromPreferences() {
#if DEBUG
        setEnabled(isDeviceQA)
#else
        setEnabled(UserDefaults.standard.bool(forKey: consentKey))
#endif
    }

    static func setEnabled(_ enabled: Bool) {
#if CUBEGIN_TELEMETRY
        guard supportsReporting else { return }
        if enabled {
            startReporting()
        } else {
            if analyticsEnabled {
                Analytics.setAnalyticsCollectionEnabled(false)
                Analytics.setUserID(nil)
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

    static func record(_ operation: FailedOperation, _ reason: FailureReason, impact: FailureImpact = .blocked) {
#if CUBEGIN_TELEMETRY
        let failure = OperationFailure(operation: operation, reason: reason, impact: impact)
        if analyticsEnabled {
            Analytics.logEvent(OperationFailure.eventName, parameters: analyticsParameters(failure.fields))
        }
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
    private static var sentryEnabled = false
    private static var lastReports: [String: ContinuousClock.Instant] = [:]

    private static func startReporting() {
        let id = installationID
        if !analyticsEnabled, Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            Analytics.setUserID(id)
            Analytics.setAnalyticsCollectionEnabled(true)
            analyticsEnabled = true
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
