import SwiftUI
import UIKit

@main
struct CubeginApp: App {
    @UIApplicationDelegateAdaptor(CubeginAppDelegate.self) private var delegate
    @AppStorage(AppLanguage.preferenceKey) private var languageOverride = AppLanguage.systemPreference
    @AppStorage(AppTheme.preferenceKey) private var theme = AppTheme.system
    @State private var hasFinishedLaunch = false

    var body: some Scene {
        WindowGroup {
            LaunchRootView(hasFinishedLaunch: $hasFinishedLaunch)
                .environment(\.locale, AppLanguage.resolve(languageOverride).locale)
                .dynamicTypeSize(.large)
                .preferredColorScheme(theme.colorScheme)
                .scrollIndicators(.hidden)
                .task { SettingsSync.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    SettingsSync.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) {
                    SettingsSync.receive($0)
                }
                .background {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        MinimumWindowHeight()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }
}

enum AppTypography {
    static func preferredFont(for style: UIFont.TextStyle) -> UIFont {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
    }
}

final class CubeginAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppTelemetry.startFromPreferences()
        return true
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private var language: AppLanguage { locale.appLanguage }

    private var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return [language.text("暂时无法读取隐私政策。", "The privacy policy couldn’t be loaded.")]
        }
        let sections = markdown.components(separatedBy: "\n<!-- English -->\n")
        let section = language == .english ? sections.last : sections.first
        return (section ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.hasPrefix("# ") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        if paragraph.hasPrefix("## ") {
                            Text(paragraph.dropFirst(3))
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text((try? AttributedString(markdown: paragraph)) ?? AttributedString(paragraph))
                        }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding()
            }
            .navigationTitle(language.text("隐私政策", "Privacy Policy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("完成", "Done")) { dismiss() }
                }
            }
        }
    }
}

private struct MinimumWindowHeight: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowObserver {
        WindowObserver()
    }

    func updateUIView(_ uiView: WindowObserver, context: Context) {}

    final class WindowObserver: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let restrictions = window?.windowScene?.sizeRestrictions else { return }

            // At 375 pt wide, allow roughly one extra 14 pt scramble line
            // beyond the measured seven-layer scramble within the 40% height cap.
            var minimumSize = restrictions.minimumSize
            minimumSize.height = max(minimumSize.height, 700)
            if minimumSize != restrictions.minimumSize {
                restrictions.minimumSize = minimumSize
            }
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "app.language"
    static let systemPreference = ""
    static var saved: Self {
        resolve(UserDefaults.standard.string(forKey: preferenceKey))
    }
    static func resolve(_ override: String?, preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        if let override, let selected = Self(rawValue: override) { return selected }
        for identifier in preferredLanguages {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "zh": return .chinese
            case "en": return .english
            default: continue
            }
        }
        return .english
    }

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }
    var name: String { text("简体中文", "English") }

    func text(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }
}

extension Locale {
    var appLanguage: AppLanguage {
        AppLanguage(rawValue: identifier) ?? .chinese
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let preferenceKey = "app.theme"
    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .system: language.text("跟随系统", "System")
        case .light: language.text("浅色", "Light")
        case .dark: language.text("深色", "Dark")
        }
    }
}

enum ICloudSyncPreference {
    static let key = "app.icloudSync"
    private static let legacyResultsKey = "results.icloudSync"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        if defaults.object(forKey: legacyResultsKey) != nil { return defaults.bool(forKey: legacyResultsKey) }
        return true
    }
}

@MainActor
enum SettingsSync {
    private static let keys = [
        AppLanguage.preferenceKey, AppTheme.preferenceKey, TimerModel.startDelayKey,
        TimerModel.keepTimerScreenOnKey, TimerModel.inspectionKey, TimerModel.trainingInspectionKey,
        TimerModel.inspectionVoiceKey, TimerModel.hapticsKey, TimerModel.displayKey, TimerModel.entryMethodKey,
        ResultExtremes.includeDNFPreferenceKey
    ] + TimerSwipeDirection.allCases.map(\.preferenceKey)

    static var isAvailable: Bool {
#if targetEnvironment(simulator)
        false
#else
        Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin" || CloudKitResultsTransport.isAvailable
#endif
    }

    private static var isEnabled: Bool {
        isAvailable && ICloudSyncPreference.isEnabled(in: .standard)
    }

    static func binding<Value: Equatable>(_ local: Binding<Value>, key: String, encode: @escaping (Value) -> Any) -> Binding<Value> {
        Binding {
            local.wrappedValue
        } set: { value in
            guard local.wrappedValue != value else { return }
            local.wrappedValue = value
            guard isEnabled else { return }
            NSUbiquitousKeyValueStore.default.set(encode(value), forKey: key)
        }
    }

    static func refresh() {
        guard isEnabled, NSUbiquitousKeyValueStore.default.synchronize() else { return }
        apply(keys)
    }

    static func receive(_ notification: Notification) {
        guard isEnabled,
              let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
        switch reason {
        case NSUbiquitousKeyValueStoreInitialSyncChange, NSUbiquitousKeyValueStoreAccountChange:
            apply(keys)
        case NSUbiquitousKeyValueStoreServerChange:
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? keys
            apply(keys.filter { changed.contains($0) })
        default:
            break
        }
    }

    private static func apply(_ keys: [String]) {
        let cloud = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = cloud.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
