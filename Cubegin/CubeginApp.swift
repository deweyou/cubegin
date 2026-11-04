import SwiftUI
import UIKit

@main
struct CubeginApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.chinese
    @State private var hasFinishedLaunch = false

    var body: some Scene {
        WindowGroup {
            LaunchRootView(hasFinishedLaunch: $hasFinishedLaunch)
                .environment(\.locale, language.locale)
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
