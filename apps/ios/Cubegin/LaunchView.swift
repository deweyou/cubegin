import SwiftUI

struct LaunchRootView: View {
    @Binding var hasFinishedLaunch: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldPrepareTimer = false
    @State private var timerIsReady = false

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
            if shouldPrepareTimer || hasFinishedLaunch {
                AppTabsView(isActive: hasFinishedLaunch)
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
                        prepareTimer: { shouldPrepareTimer = true },
                        finish: { hasFinishedLaunch = true }
                    )
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, !holdsLaunchScreen {
                    hasFinishedLaunch = true
                }
            }

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
                prepareTimer()
            } else {
                // Match the original CSS: 0 → 378°, 1.1s, cubic-bezier(.16,.67,.27,1).
                withAnimation(.timingCurve(0.16, 0.67, 0.27, 1, duration: 1.1)) {
                    blueRotation = 378
                } completion: {
                    prepareTimer()
                }
            }
        }
        .task(id: timerIsReady) {
            guard timerIsReady, !holdsLaunchScreen else { return }
            // Mount and lay out the timer under the stationary final logo before fading.
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
