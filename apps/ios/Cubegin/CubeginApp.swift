import SwiftUI
import UIKit

@main
struct CubeginApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var languageOverride = ""
    @AppStorage(AppTheme.preferenceKey) private var theme = AppTheme.system
    @State private var hasFinishedLaunch = false

    var body: some Scene {
        WindowGroup {
            LaunchRootView(hasFinishedLaunch: $hasFinishedLaunch)
                .environment(\.locale, AppLanguage.resolve(languageOverride).locale)
                .preferredColorScheme(theme.colorScheme)
                .scrollIndicators(.hidden)
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
