import SwiftUI

struct LaunchRootView: View {
    @Binding var hasFinishedLaunch: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var timerModel: TimerModel?
    @State private var timerIsReady = false
    @State private var showsSharingPrompt = false

    private var language: AppLanguage { locale.appLanguage }

    private var holdsLaunchScreen: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--hold-launch-screen")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let timerModel {
                AppTabsView(isActive: hasFinishedLaunch, model: timerModel)
                    .onAppear { timerIsReady = true }
                    .disabled(!hasFinishedLaunch)
                    .accessibilityHidden(!hasFinishedLaunch)
            }
        }
            .overlay {
                if !hasFinishedLaunch {
                    LaunchView(
                        holdsLaunchScreen: holdsLaunchScreen,
                        timerIsReady: timerIsReady,
                        prepareTimer: prepareTimer,
                        finish: { hasFinishedLaunch = true }
                    )
                }
            }
            .onChange(of: hasFinishedLaunch, initial: true) { _, finished in
                guard finished else { return }
                prepareTimer()
                if AppTelemetry.showsSharingPreference, AppTelemetry.sharingChoice() == .undecided {
                    showsSharingPrompt = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, !holdsLaunchScreen {
                    hasFinishedLaunch = true
                }
            }
            .alert(language.text("帮助改进 Cubegin", "Help improve Cubegin"), isPresented: $showsSharingPrompt) {
                Button(language.text("同意", "Agree")) { AppTelemetry.chooseSharing(.allowed) }
                    .keyboardShortcut(.defaultAction)
                Button(language.text("暂不共享", "Don’t share"), role: .cancel) { AppTelemetry.chooseSharing(.declined) }
            } message: {
                Text(language.text(
                    "是否共享崩溃报告、操作失败和功能使用情况，帮助我们修复问题、改进计时体验？",
                    "Share crash reports, failed operations, and feature usage to help us fix issues and improve the timer?"
                ))
            }

    }

    private func prepareTimer() {
        guard timerModel == nil else { return }
        timerModel = TimerModel(storage: Self.resultsStorage)
    }

    private static var resultsStorage: URL {
#if DEBUG
        // A UI test uses the same temporary file across both app launches.
        if let value = ProcessInfo.processInfo.environment["CUBEGIN_UI_TEST_SESSION"],
           let session = UUID(uuidString: value) {
            return URL.temporaryDirectory.appending(path: "ui-test-solves-\(session.uuidString).json")
        }
#endif
        return URL.documentsDirectory.appending(path: "solves.json")
    }
}

private struct LaunchView: View {
    let holdsLaunchScreen: Bool
    let timerIsReady: Bool
    let prepareTimer: () -> Void
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blueRotation = 0.0
    @State private var opacity = 1.0
    @State private var rotationIsFinished = false
    private var canRevealTimer: Bool { timerIsReady && rotationIsFinished }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                CubeginMark(blueRotation: blueRotation)
                    .frame(width: 80, height: 80)
                Image("CubeginWordmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 108, height: 108 * 97.7 / 350.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("cubegin")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .opacity(opacity)
        .accessibilityIdentifier("cold-launch")
        .task {
            if holdsLaunchScreen {
                blueRotation = 18
                return
            }
            // Commit the initial pose before changing the animated value.
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            if reduceMotion {
                blueRotation = 18
                rotationIsFinished = true
            } else {
                // Match the original CSS: 0 → 378°, 1.1s, cubic-bezier(.16,.67,.27,1).
                withAnimation(.timingCurve(0.16, 0.67, 0.27, 1, duration: 1.1)) {
                    blueRotation = 378
                } completion: {
                    rotationIsFinished = true
                }
            }
            prepareTimer()
        }
        .task(id: canRevealTimer) {
            guard canRevealTimer else { return }
            // Hold the final logo briefly before fading, independently of scramble loading.
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            revealTimer()
        }
    }

    private func revealTimer() {
        withAnimation(.easeOut(duration: 0.22)) {
            opacity = 0
        } completion: {
            finish()
        }
    }
}

struct CubeginMark: View {
    var blueRotation = 18.0

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 68
            ZStack(alignment: .topLeading) {
                tile(Color(red: 255 / 255, green: 198 / 255, blue: 46 / 255), radius: 7, unit: unit)
                    .position(x: 20 * unit, y: 20 * unit)
                tile(Color(red: 236 / 255, green: 59 / 255, blue: 59 / 255), radius: 7, unit: unit)
                    .position(x: 48 * unit, y: 20 * unit)
                tile(Color(red: 30 / 255, green: 184 / 255, blue: 119 / 255), radius: 7, unit: unit)
                    .position(x: 20 * unit, y: 48 * unit)
                tile(Color(red: 47 / 255, green: 124 / 255, blue: 224 / 255), radius: 8, unit: unit)
                    .rotationEffect(.degrees(blueRotation))
                    .position(x: 48 * unit, y: 48 * unit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
    }

    private func tile(_ color: Color, radius: CGFloat, unit: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * unit, style: .circular)
            .fill(color)
            .frame(width: 28 * unit, height: 28 * unit)
    }
}
