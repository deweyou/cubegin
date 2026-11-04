import SwiftUI

@main
struct CubeginApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.chinese
    @State private var hasFinishedLaunch = false

    var body: some Scene {
        WindowGroup {
            LaunchRootView(hasFinishedLaunch: $hasFinishedLaunch)
                .environment(\.locale, language.locale)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "app.language"
    static var saved: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .chinese
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
