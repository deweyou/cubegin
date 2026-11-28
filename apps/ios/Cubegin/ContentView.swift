import SwiftUI
import WebKit

struct ContentView: View {
    @Bindable var model: TimerModel
    let isTimerActive: Bool
    var leadingNavigationWidth: CGFloat = 0
    var trailingNavigationWidth: CGFloat = 0
    var navigationInset: CGFloat = 0
    var navigationOnLeft = false
    var isDuoInnerDisplay = false
    var isDuoOuterDisplay = false
    var landscapeContentInsets: LandscapeContentInsets?
    @AppStorage(TimerModel.startDelayKey) private var startDelayTenths = TimerModel.defaultStartDelayTenths
    @AppStorage(TimerModel.displayKey) private var displayDuringSolve = TimerDisplay.realtime
    @AppStorage(TimerModel.entryMethodKey) private var entryMethod = SolveEntryMethod.timer
    @AppStorage(TimerModel.hapticsKey) private var usesTimerHaptics = true
    @FocusState private var hasTimerKeyboardFocus: Bool
    @State private var idlePageFrame: CGRect?
    @State private var scrambleFrame: CGRect = .null
    @State private var postSolveControlsFrame: CGRect = .null
    @State private var padProjectAnchor: CGRect?
    private var isTiming: Bool { model.started != nil }
    @State private var isInTimerCancelZone = false
    let timerReadinessChanged: (Bool) -> Void
    private static let cancelZoneHeight: CGFloat = 88
    private var showsTimingLayout: Bool {
        isTiming || model.inspectionStarted != nil
    }
    private var showsCancelHint: Bool {
        (model.hasSettledPress && model.isTouchReady) || isInTimerCancelZone
    }
    private var timerPressColor: Color? {
        if isInTimerCancelZone { return .red }
        if model.isReady { return .green }
        return model.isPressing ? .red : nil
    }
    @State private var showsProjectList = false
    @State private var assistScramble: AssistScramble?
    @State private var timerTouchResumesAt: ContinuousClock.Instant?
    @State private var solveToDelete: Solve?
    @State private var manualContext: ManualSolveContext?
    @State private var showsGenerating = false
    @State private var displayedDiagram: String?
    private var isScrambleReady: Bool {
        guard let svg = model.scramble?.svg else { return false }
        return displayedDiagram == svg
    }
    private var isPreparingScramble: Bool {
        model.busy || (model.scramble != nil && !isScrambleReady)
    }
    @State private var confettiBurst: TimerConfettiBurst?
    @State private var showsCelebrationToast = false
    @State private var celebrationScoreMotion = CelebrationScoreMotion.rest
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private let controlIconSize: CGFloat = 20
    private let controlRowHeight: CGFloat = 44
    private let headerControlTargetWidth: CGFloat = 64
    private let padToolbarMargin: CGFloat = 20
    private var controlIconInset: CGFloat { (controlRowHeight - controlIconSize) / 2 }
    private var padProjectToolbarInset: CGFloat { padToolbarMargin + controlIconInset }
    private let compactControlSize: CGFloat = 32
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var celebrationPillLineHeight: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var standardMegaminxFontSize: CGFloat = 14
    private let celebrationPillPadding: CGFloat = 7
    @ScaledMetric(relativeTo: .title3) private var scrambleFontSize: CGFloat = 20
    static let landscapeBottomInset: CGFloat = 8

    // The native iPad TabView uses the top bar in regular-width layouts.
    private var usesTopNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    private var canUseTimerInput: Bool {
        isTimerActive && !showsProjectList && assistScramble == nil && solveToDelete == nil && manualContext == nil
    }
    private var canUseTimerTouch: Bool {
        canUseTimerInput && (timerTouchResumesAt.map { ContinuousClock.now >= $0 } ?? true)
    }
    private var presentedCelebration: SolveCelebration? {
        canUseTimerInput && !showsTimingLayout && !model.isPressing ? model.lastSolveCelebration : nil
    }

    private var scoreCelebration: ScoreCelebration? {
        guard !showsTimingLayout, let record = model.celebratedLastSolve else { return nil }
        let motion = showsCelebrationToast && !reduceMotion ? celebrationScoreMotion : .rest
        return ScoreCelebration(record: record, motion: motion)
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationStack {
                    page
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(showsTimingLayout ? .hidden : .visible, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                if usesTopNavigation {
                                    padProjectToolbarAnchor
                                } else {
                                    HStack(spacing: 0) { projectMenu }
                                        .fixedSize(horizontal: true, vertical: false)
                                        .disabled(model.busy || isTiming)
                                }
                            }
                            .sharedBackgroundVisibility(.hidden)
                            ToolbarItem(placement: .topBarTrailing) {
                                trailingControls
                                    .padding(.trailing, usesTopNavigation ? padToolbarMargin : 0)
                                    .disabled(model.busy || isTiming)
                            }
                            .sharedBackgroundVisibility(.hidden)
                        }
                }
                .overlay {
                    if usesTopNavigation && !showsTimingLayout {
                        padProjectToolbarButton
                    }
                }
            } else {
                page
            }
        }
        .appBackground()
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.hasSettledPress) { _, isShowing in
            isShowing && entryMethod == .timer && usesTimerHaptics && isTimerActive && !model.isTouchReady
                && !model.usesInspection && model.inspectionStarted == nil
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.lastSolveID) { _, solveID in
            solveID != nil && entryMethod == .timer && usesTimerHaptics && isTimerActive
        }
        .focusable(isTimerActive && assistScramble == nil && manualContext == nil)
        .focusEffectDisabled()
        .focused($hasTimerKeyboardFocus)
        .onKeyPress(.space, phases: [.down, .up, .repeat]) { press in
            guard canUseTimerInput else { return .ignored }
            if press.phase == .down, !isTiming, !isScrambleReady { return .ignored }
            if entryMethod == .manual, !isTiming {
                if press.phase == .up { openManualEntry() }
                return .handled
            }
            switch press.phase {
            case .down: model.press(.keyboard, delayTenths: startDelayTenths)
            case .up: model.release(.keyboard)
            default: break
            }
            return .handled
        }
        .onChange(of: isTimerActive, initial: true) { _, active in
            hasTimerKeyboardFocus = active && assistScramble == nil
            if !active {
                model.cancelPress()
                model.endInspection()
                isInTimerCancelZone = false
            }
        }
        .onChange(of: isTimerActive && isScrambleReady, initial: true) { _, ready in
            if ready { AppTelemetry.recordTimerReady() }
        }
        .onChange(of: canUseTimerInput && isScrambleReady, initial: true) { _, ready in
            timerReadinessChanged(ready)
        }
        .onChange(of: presentedCelebration) { _, celebration in
            if let confettiBurst, confettiBurst.record != celebration { stopCelebration() }
        }
        .task(id: presentedCelebration) { [presentedCelebration] in
            guard let presentedCelebration else { return }
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            guard !Task.isCancelled, self.presentedCelebration == presentedCelebration,
                  let record = model.takeAutomaticCelebration() else { return }
            playCelebration(record)
        }
        .onChange(of: showsProjectList) { _, isShowing in
            model.cancelPress()
            if !isShowing {
                // The tap dismissing the popover can also reach the page beneath it.
                timerTouchResumesAt = .now.advanced(by: .milliseconds(250))
                if isTimerActive { hasTimerKeyboardFocus = true }
            }
        }
        .sheet(item: assistPresentation(onDuo: false), onDismiss: resumeTimerInput) { scramble in
            if UIDevice.current.userInterfaceIdiom == .pad {
                AssistFormulaView(scramble: scramble, onPreferencesChanged: model.preferenceDidChange)
                    .presentationSizing(.form)
            } else {
                AssistFormulaView(scramble: scramble, onPreferencesChanged: model.preferenceDidChange)
            }
        }
        .fullScreenCover(item: assistPresentation(onDuo: true), onDismiss: resumeTimerInput) { scramble in
            AssistFormulaModal(scramble: scramble, onPreferencesChanged: model.preferenceDidChange)
                .presentationBackground(.clear)
        }
        .sheet(item: manualPresentation(edgeToEdge: false), onDismiss: resumeTimerInput) { context in
            manualEntryForm(context)
                .presentationSizing(.form)
                .presentationBackground(Color(uiColor: .systemBackground))
        }
        .fullScreenCover(item: manualPresentation(edgeToEdge: true), onDismiss: resumeTimerInput) { context in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { setManualContext(nil) }
                    .accessibilityHidden(true)
                manualEntryForm(context, close: { setManualContext(nil) })
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .presentationBackground(.clear)
        }
        .onChange(of: entryMethod) { _, method in
            if method == .manual {
                if !isTiming { model.interrupt() }
                isInTimerCancelZone = false
            } else {
                setManualContext(nil)
            }
        }
        .alert(language.text("确定删除这条成绩吗？", "Delete this solve?"), isPresented: Binding(
            get: { solveToDelete != nil },
            set: { if !$0 { solveToDelete = nil } }
        ), presenting: solveToDelete) { solve in
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("删除", "Delete"), role: .destructive) {
                model.deleteSolve(solve.id)
            }
        }
        .task(id: isPreparingScramble) {
            showsGenerating = false
            guard isPreparingScramble else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            if isPreparingScramble { showsGenerating = true }
        }
        .onChange(of: hasTimerKeyboardFocus) { _, focused in
            if !focused { model.cancelPress(.keyboard) }
        }
        .onChange(of: solveToDelete?.id) { _, id in
            if id == nil { resumeTimerInput() }
        }
#if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--measure-picker") {
                measurePickerWidths()
            }
        }
#endif
    }
    private func assistPresentation(onDuo: Bool) -> Binding<AssistScramble?> {
        Binding(
            get: { assistScramble?.usesDuoModal == onDuo ? assistScramble : nil },
            set: { if $0 == nil, assistScramble?.usesDuoModal == onDuo { assistScramble = nil } }
        )
    }

    private func resumeTimerInput() {
        timerTouchResumesAt = .now.advanced(by: .milliseconds(250))
        if isTimerActive { hasTimerKeyboardFocus = true }
    }

    private func cancelHint(atLowerDisplay: Bool) -> some View {
        Text(isInTimerCancelZone ? language.text("松开取消", "Release to cancel")
             : language.text("上滑到这里取消", "Slide here to cancel"))
            .font(.headline)
            .foregroundStyle(isInTimerCancelZone ? Color.red : Color.primary.opacity(0.8))
            .padding(.top, isDuoOuterDisplay ? 32 : 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Self.cancelZoneHeight, alignment: .top)
            .background(alignment: .top) {
                LinearGradient(
                    colors: [Color.primary.opacity(0.16), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: Self.cancelZoneHeight + 16)
                .ignoresSafeArea(edges: atLowerDisplay ? .horizontal : [.top, .horizontal])
            }
            .allowsHitTesting(false)
    }

    private var page: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            // The Duo outer display reserves horizontal space for its side rail.
            let hasSideRail = UIDevice.current.userInterfaceIdiom == .phone
                && geometry.size.height > geometry.size.width
                && max(insets.leading, insets.trailing) > 24
            let diagramBottomPadding = hasSideRail ? 18 - insets.bottom : 12
            let frame = geometry.frame(in: .global)
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
            let isLandscape = frame.width > frame.height
            let timerFrame = if showsTimingLayout, let idlePageFrame,
                                !isPhone || (idlePageFrame.width > idlePageFrame.height) == isLandscape {
                idlePageFrame
            } else {
                frame
            }
            let fold = isPhone && !isLandscape ? horizontalFold(in: geometry) : nil
            let usesDuoWideLayout = isLandscape && isDuoInnerDisplay
            Group {
                if let fold {
                    foldedPortraitPage(frame: frame, fold: fold)
                } else if usesDuoWideLayout {
                    page(frame: frame.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: trailingNavigationWidth)),
                         timerFrame: timerFrame.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: trailingNavigationWidth)),
                         diagramBottomPadding: diagramBottomPadding, usesDuoWideLayout: true)
                        .padding(.trailing, trailingNavigationWidth)
                } else if isPhone && isLandscape {
                    let screenCenter = CGPoint(
                        x: frame.midX + (insets.trailing - insets.leading) / 2,
                        y: frame.midY + (insets.bottom - insets.top) / 2
                    )
                    landscapePage(frame: frame, timerFrame: timerFrame, screenCenter: screenCenter)
                } else {
                    page(frame: frame, timerFrame: timerFrame, diagramBottomPadding: diagramBottomPadding)
                }
            }
            .overlay(alignment: .top) {
                if fold == nil, showsCancelHint {
                    cancelHint(atLowerDisplay: false)
                }
            }
            .overlay {
                if fold == nil {
                    celebrationConfetti
                        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measuredFrame in
                if !showsTimingLayout { idlePageFrame = measuredFrame }
            }
        }
        .task(id: confettiBurst?.start) {
            guard confettiBurst != nil else { return }
            do {
                if !reduceMotion { try await Task.sleep(for: .milliseconds(150)) }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                    showsCelebrationToast = true
                }
                if !reduceMotion {
                    for (motion, milliseconds) in CelebrationScoreMotion.steps {
                        withAnimation(.easeInOut(duration: Double(milliseconds) / 1000)) {
                            celebrationScoreMotion = motion
                        }
                        try await Task.sleep(for: .milliseconds(milliseconds))
                    }
                }
                try await Task.sleep(for: celebrationToastHoldDuration)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.34)) {
                    showsCelebrationToast = false
                }
                if !reduceMotion { try await Task.sleep(for: .milliseconds(340)) }
                stopCelebration()
            } catch { return }
        }
    }

    private var celebrationToastHoldDuration: Duration {
        let milliseconds = reduceMotion ? 1500 : 580
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CUBEGIN_UI_TEST_EXTENDED_CELEBRATION"] == "1",
           let session = environment["CUBEGIN_UI_TEST_SESSION"], UUID(uuidString: session) != nil {
            return .milliseconds(milliseconds + 5000)
        }
#endif
        return .milliseconds(milliseconds)
    }

    private func horizontalFold(in geometry: GeometryProxy) -> CGRect? {
        // The iOS 26 SDK does not declare SwiftUI's reserved region API.
#if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return Self.horizontalFold(in: geometry.reservedRegions(kind: .division).map(\.frame),
                                       pageHeight: geometry.size.height)
        }
#endif
        return nil
    }

    static func horizontalFold(in divisions: [CGRect], pageHeight: CGFloat) -> CGRect? {
        divisions.first { fold in
            !fold.isEmpty && fold.width > fold.height && fold.minY > 0 && fold.maxY < pageHeight
        }
    }

    private func foldedPortraitPage(frame: CGRect, fold: CGRect) -> some View {
        let size = frame.size
        let padding: CGFloat = 16
        let foldClearance: CGFloat = 8
        let rowSpacing: CGFloat = 8
        let width = max(1, size.width - 2 * padding)
        let upperHeight = max(0, fold.minY - 2 * foldClearance)
        let lowerHeight = max(0, size.height - fold.maxY - foldClearance)
        let formulaFraction = model.mode == .standard && model.event == "minx" ? 0.42 : 0.28
        let formulaHeight = upperHeight * formulaFraction
        let footerHeight = min(140, lowerHeight * 0.38)
        let summaryWidth = min(144, width * 0.38)
        let diagramWidth = max(0, width - summaryWidth - 12)
        let timerHeight = max(0, upperHeight - formulaHeight - 2 * rowSpacing)
        let centersReadout = showsTimingLayout
        let showsSolveActions = !centersReadout && model.lastSolve != nil
        let actionHeight = showsSolveActions ? compactControlSize + rowSpacing : 0
        let readoutAreaHeight = timerHeight - actionHeight
        let preferredTimerFontSize = min(90, upperHeight * 0.26)
        let timerFontSize = max(1, centersReadout ? preferredTimerFontSize
                                : min(preferredTimerFontSize, readoutAreaHeight / 1.2))
        let numberHeight = timerFontSize * 1.2
        let readoutY = centersReadout ? max(0, (upperHeight - frame.minY) / 2)
            : upperHeight - timerHeight + readoutAreaHeight / 2
        let actionCenterY = readoutY + numberHeight / 2 + rowSpacing + compactControlSize / 2
        let toastHeight = celebrationPillLineHeight + 2 * celebrationPillPadding
        let controlsBottom = readoutY + numberHeight / 2 + actionHeight
        let canCenterToast = controlsBottom + toastHeight + 2 * foldClearance <= upperHeight
        let showsScrambleDetails = !showsTimingLayout
        let detailsTop = showsTimingLayout ? foldClearance : controlRowHeight + 2 * foldClearance
        let positionAnimation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.2)

        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if !centersReadout {
                    currentScramble(width: width)
                        .frame(height: formulaHeight)
                        .padding(.top, rowSpacing)
                        .allowsHitTesting(false)
                }
                timerNumber(fontSize: timerFontSize, height: numberHeight)
                    .frame(width: width)
                    .animation(positionAnimation) { content in
                        content.position(x: width / 2, y: readoutY)
                    }
                if showsSolveActions {
                    postSolveControls
                        .position(x: width / 2, y: actionCenterY)
                }
            }
            .frame(width: width, height: upperHeight)
            .frame(width: size.width)
            .overlay(alignment: canCenterToast ? .bottom : .bottomTrailing) {
                celebrationToast
                    .padding(.trailing, canCenterToast ? 0 : padding)
                    .padding(.bottom, foldClearance)
            }
            .overlay {
                celebrationConfetti
                    .clipped()
            }
            .padding(.top, foldClearance)

            Color.clear.frame(height: fold.height + 2 * foldClearance)
                .accessibilityHidden(true)

            ZStack(alignment: .top) {
                timerTouchSurface(cancelZoneTop: frame.minY + fold.maxY + foldClearance)
                    .frame(width: size.width, height: lowerHeight)
                if !showsTimingLayout {
                    phoneControls
                        .frame(width: width)
                        .padding(.top, foldClearance)
                }
                HStack(alignment: .top, spacing: 12) {
                    TimerSummary(model: model, height: footerHeight, scoreCelebration: scoreCelebration)
                        .frame(width: summaryWidth)
                    scrambleDiagram(alignment: .topTrailing)
                        .frame(width: diagramWidth * 0.8, height: footerHeight)
                        .frame(width: diagramWidth, alignment: .trailing)
                }
                .frame(width: width, height: footerHeight)
                .padding(.top, detailsTop)
                .opacity(showsScrambleDetails ? 1 : 0)
                .accessibilityHidden(!showsScrambleDetails)
                .allowsHitTesting(false)

                if isTiming {
                    Text(language.text("轻点停止", "Tap to stop"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timer.folded-stop")
                        .position(x: size.width / 2, y: lowerHeight / 2)
                        .allowsHitTesting(false)
                }

                if showsCancelHint {
                    cancelHint(atLowerDisplay: true)
                }
            }
            .frame(width: size.width, height: lowerHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func landscapePage(frame: CGRect, timerFrame: CGRect, screenCenter: CGPoint) -> some View {
        let edgePadding: CGFloat = 8
        let columnSpacing: CGFloat = 16
        let rowSpacing: CGFloat = 8
        let headerTop = edgePadding + (landscapeContentInsets?.headerTopOffset ?? 0)
        let controlsHeight = headerTop + controlRowHeight
        let columnsTop = controlsHeight + rowSpacing
        let availableWidth = timerFrame.width - leadingNavigationWidth - trailingNavigationWidth
        let layoutWidth = min(availableWidth, 880)
        let centeredInset = (availableWidth - layoutWidth) / 2
        let columnShift = (trailingNavigationWidth - leadingNavigationWidth) / 2
        let headerLeadingInset = (landscapeContentInsets?.leading ?? edgePadding) + centeredInset
        let headerTrailingInset = (landscapeContentInsets?.trailing ?? trailingNavigationWidth + 12) + centeredInset
        let columnsWidth = max(2, layoutWidth - 2 * edgePadding - columnSpacing)
        let scrambleWidth = columnsWidth * (landscapeContentInsets?.scrambleColumnFraction ?? 0.55)
        let timerWidth = columnsWidth - scrambleWidth
        let columnsHeight = max(1, timerFrame.height - columnsTop - Self.landscapeBottomInset)
        let diagramWidth = scrambleWidth * 0.72
        let diagramAspectRatio = model.scramble?.diagramAspectRatio ?? (4.0 / 3)
        let diagramHeight = min(columnsHeight * 0.34, diagramWidth / CGFloat(diagramAspectRatio))
        let summaryHeight: CGFloat = 60
        let belowReadoutHeight = summaryHeight + compactControlSize + 2 * rowSpacing
        let numberHeight = max(1, min(132, columnsHeight - belowReadoutHeight))
        let summaryOffset = max(0, columnsHeight - numberHeight - belowReadoutHeight) / 2
        let touchOverhang = max(0, -navigationInset)
        let columnCenterX = timerFrame.midX + (scrambleWidth + columnSpacing) / 2 - columnShift
        let idleReadoutCenterY = timerFrame.minY + columnsTop + (columnsHeight - belowReadoutHeight) / 2
        let readoutShift = showsTimingLayout
            ? CGSize(width: screenCenter.x - columnCenterX, height: screenCenter.y - idleReadoutCenterY)
            : .zero

        return ZStack(alignment: .top) {
            timerTouchSurface()
                .frame(width: frame.width + touchOverhang,
                       height: frame.height)
                .frame(width: frame.width, alignment: navigationOnLeft ? .trailing : .leading)

            if !showsTimingLayout {
                phoneControls
                    .padding(.top, headerTop)
                    .frame(width: frame.width - headerLeadingInset - headerTrailingInset)
                    .offset(x: (headerLeadingInset - headerTrailingInset) / 2)
            }

            HStack(spacing: columnSpacing) {
                LandscapeScrambleLayout {
                    if !showsTimingLayout {
                        currentScramble(width: scrambleWidth, fontScale: 1.1)
                    }
                    scrambleDiagram(alignment: .center)
                        .frame(width: diagramWidth, height: diagramHeight)
                        .opacity(showsTimingLayout ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(showsTimingLayout)
                }
                .frame(width: scrambleWidth, height: columnsHeight)
                .allowsHitTesting(!showsTimingLayout)
                .accessibilityHidden(showsTimingLayout)

                VStack(spacing: rowSpacing) {
                    timerNumber(fontSize: numberHeight / 1.2, height: numberHeight, minimumScale: 0.35)
                        .frame(width: timerWidth, height: numberHeight)
                        .offset(readoutShift)
                    postSolveControls
                    ZStack {
                        // Reserve the summary's height while timing.
                        Color.clear
                            .accessibilityHidden(true)
                        if !showsTimingLayout {
                            TimerSummary(model: model, height: summaryHeight, scoreCelebration: scoreCelebration,
                                         twoColumns: true)
                                .frame(maxWidth: 220)
                        }
                    }
                    .frame(height: summaryHeight)
                    .offset(y: summaryOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(showsTimingLayout)
                }
                .frame(width: timerWidth, height: columnsHeight)
                .zIndex(1)
            }
            .padding(.top, columnsTop)
            .offset(x: timerFrame.midX - frame.midX - columnShift,
                    y: timerFrame.minY - frame.minY)
        }
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .overlay(alignment: .bottom) {
            celebrationToast
                .padding(.bottom, Self.landscapeBottomInset)
                .frame(width: frame.width - headerLeadingInset - headerTrailingInset)
                .offset(x: (headerLeadingInset - headerTrailingInset) / 2)
        }
    }

    private func page(frame: CGRect, timerFrame: CGRect, diagramBottomPadding: CGFloat,
                      usesDuoWideLayout: Bool = false) -> some View {
        let width = frame.width
        let height = frame.height
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let maximumWidth: CGFloat = isPad ? .infinity : 880
        let horizontalPadding: CGFloat = 24
        let contentWidth = max(1, min(width, maximumWidth) - 2 * horizontalPadding)
        let timerFontSize: CGFloat
        if isPad {
            let limit: CGFloat = timerFrame.width > timerFrame.height ? 140 : 120
            timerFontSize = max(1, min(limit, (timerFrame.width - 2 * horizontalPadding) * 0.16, timerFrame.height * 0.18))
        } else if usesDuoWideLayout {
            timerFontSize = 90
        } else {
            timerFontSize = timerFrame.width > 600 ? 110 : 76
        }
        let timerNumberHeight = timerFontSize * 1.2
        let showsControlsInPage = !isPad
        let controlsHeight = showsControlsInPage ? controlRowHeight : 0
        let topClearance: CGFloat = 8
        let controlSpacing: CGFloat = showsControlsInPage ? 8 : 0
        let timerTouchTop = showsTimingLayout ? 0 : topClearance + controlsHeight + controlSpacing
        let compactRecentRowHeight: CGFloat = 26
        let preferredRecentRowHeight: CGFloat = 30
        let recentColumnHalfRows: CGFloat = 3 // Title and five results, centered on the timer.
        let compactRecentHalfHeight = recentColumnHalfRows * compactRecentRowHeight
        let formulaClearance = usesDuoWideLayout ? max(timerNumberHeight / 2, compactRecentHalfHeight) : timerNumberHeight / 2
        let formulaHeight = max(1, min(height * 0.3,
            height / 2 - formulaClearance - controlsHeight - controlSpacing - topClearance - 8))
        let footerSpacing: CGFloat = 12
        let footerWidth = max(0, contentWidth - footerSpacing)
        let summaryWidth = min(144, footerWidth * 0.46)
        let diagramWidth = footerWidth - summaryWidth
        let diagramClearance: CGFloat = model.lastSolve == nil ? 68 : max(68, 14 + compactControlSize + diagramBottomPadding + 8)
        let diagramHeight = max(0, min(180, height / 2 - timerNumberHeight / 2 - diagramClearance))

        let diagramAspectRatio = CGFloat(model.scramble?.diagramAspectRatio ?? (4.0 / 3))
        let summaryHeight = min(diagramHeight, diagramWidth / diagramAspectRatio)
        let usesLargeSummary = isPad && width > height
        let visibleDiagramWidth = summaryHeight * diagramAspectRatio
        let availableSummaryWidth = max(summaryWidth, footerWidth - visibleDiagramWidth)
        let summaryTextWidth = usesLargeSummary ? min(220, availableSummaryWidth) : summaryWidth
        let timerWidth = max(1, min(timerFrame.width, maximumWidth) - 2 * horizontalPadding)
        let longestTimeParts = TimerModel.displayParts(.infinity)
        let longestSingle = longestTimeParts.joined() + "+"
        let recentValueStyle: Font = usesDuoWideLayout ? .subheadline : .body
        let recentValueTextStyle: UIFont.TextStyle = usesDuoWideLayout ? .subheadline : .body
        let recentColumnWidth = ceil((longestSingle as NSString).size(withAttributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: AppTypography.preferredFont(for: recentValueTextStyle).pointSize,
                                                    weight: .regular)
        ]).width)
        let recentColumnGap: CGFloat = 24
        let sideWidth = 2 * (recentColumnWidth + recentColumnGap)
        let timerHorizontalPadding: CGFloat = 12
        let availableRecentHalfHeight = height / 2 - max(
            topClearance + controlsHeight + controlSpacing + formulaHeight,
            diagramHeight + diagramBottomPadding
        )
        let recentRowHeight = max(compactRecentRowHeight,
                                  min(preferredRecentRowHeight, (availableRecentHalfHeight / recentColumnHalfRows).rounded(.down)))
        let fitsRecentResults = (isPad || usesDuoWideLayout)
            && timerWidth - sideWidth >= longestTimerWidth(parts: longestTimeParts, fontSize: timerFontSize)
                + 2 * timerHorizontalPadding
            && availableRecentHalfHeight >= compactRecentHalfHeight

        return ZStack {
            timerTouchSurface()
                .frame(width: width, height: max(0, height - timerTouchTop))
                .frame(width: contentWidth, height: height, alignment: .bottom)

            if !showsTimingLayout {
                VStack(spacing: 0) {
                    if showsControlsInPage {
                        phoneControls
                            .padding(.leading, usesDuoWideLayout ? controlIconInset : 0)
                    }
                    currentScramble(width: contentWidth)
                        .frame(height: formulaHeight)
                        .padding(.top, controlSpacing)
                }
                .padding(.top, topClearance)
                .frame(height: height, alignment: .top)
            }

            HStack(alignment: .bottom, spacing: footerSpacing) {
                if !showsTimingLayout && summaryHeight > 0 {
                    Color.clear
                        .frame(width: summaryWidth, height: summaryHeight)
                        .overlay(alignment: .bottomLeading) {
                            TimerSummary(model: model, height: summaryHeight, scoreCelebration: scoreCelebration,
                                         usesLargeType: usesLargeSummary)
                                .frame(width: summaryTextWidth)
                                .opacity(usesLargeSummary ? 0.8 : 1)
                        }
                }
                scrambleDiagram()
                    .frame(width: diagramWidth, height: diagramHeight)
            }
            .padding(.bottom, diagramBottomPadding)
            .frame(height: height, alignment: .bottom)
            .opacity(showsTimingLayout || diagramHeight == 0 ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(showsTimingLayout || diagramHeight == 0)

            if fitsRecentResults && !showsTimingLayout {
                recentResults(columnWidth: recentColumnWidth, rowHeight: recentRowHeight, valueFont: recentValueStyle)
                    .frame(width: contentWidth)
                    .allowsHitTesting(false)
            }

            timerDisplay(fontSize: timerFontSize, numberHeight: timerNumberHeight)
                .frame(width: fitsRecentResults && !showsTimingLayout ? timerWidth - sideWidth : timerWidth)
                .offset(x: timerFrame.midX - frame.midX, y: timerFrame.midY - frame.midY)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            celebrationToast
                .padding(.bottom, 24)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: maximumWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func recentResults(columnWidth: CGFloat, rowHeight: CGFloat, valueFont: Font) -> some View {
        let average = SolveAverage.ao5
        let recent = Array(model.groupSolves.sorted(by: Solve.newestFirst).prefix(5 + average.count - 1))
        if !recent.isEmpty {
            let singles = recent.prefix(5).map(\.resultText)
            let averages = singles.indices.prefix(max(0, recent.count - average.count + 1)).map { index in
                average.summarize(recent[index..<(index + average.count)]).mean.map(TimerModel.format) ?? "DNF"
            }
            HStack(alignment: .top, spacing: 0) {
                recentResultColumn("ao5", values: averages, rowHeight: rowHeight, valueFont: valueFont, alignment: .leading)
                    .frame(width: columnWidth, alignment: .leading)
                Spacer(minLength: 0)
                recentResultColumn("single", values: singles, rowHeight: rowHeight, valueFont: valueFont, alignment: .trailing)
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func recentResultColumn(
        _ title: String,
        values: [String],
        rowHeight: CGFloat,
        valueFont: Font,
        alignment: HorizontalAlignment
    ) -> some View {
        if !values.isEmpty {
            VStack(alignment: alignment, spacing: 0) {
                Text(verbatim: title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
                    .frame(height: rowHeight)
                    .offset(y: 4)
                ForEach(values.indices, id: \.self) { index in
                    Text(verbatim: values[index])
                        .font(valueFont.monospacedDigit())
                        .foregroundStyle(Color.primary.opacity(0.60 - 0.06 * Double(index)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: rowHeight)
                        .accessibilityIdentifier("timer-recent.\(title).\(index)")
                }
            }
        }
    }

    private func timerDisplay(fontSize: CGFloat, numberHeight: CGFloat) -> some View {
        VStack(spacing: UIDevice.current.userInterfaceIdiom == .phone ? 8 : 14) {
            // Mirror the reserved action row so the digits stay centered.
            Color.clear.frame(height: compactControlSize)
            timerNumber(fontSize: fontSize, height: numberHeight)
            postSolveControls
        }
    }

    private var usesEdgeToEdgeManualEntry: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .regular
            && !isDuoInnerDisplay && !dynamicTypeSize.isAccessibilitySize
    }

    private func manualPresentation(edgeToEdge: Bool) -> Binding<ManualSolveContext?> {
        Binding(
            get: { usesEdgeToEdgeManualEntry == edgeToEdge ? manualContext : nil },
            set: { if $0 == nil, usesEdgeToEdgeManualEntry == edgeToEdge { setManualContext(nil) } }
        )
    }

    private func setManualContext(_ context: ManualSolveContext?) {
        var transaction = Transaction()
        // Only the keyboard should move the bottom panel. The full-screen backdrop stays in place.
        transaction.disablesAnimations = usesEdgeToEdgeManualEntry
        withTransaction(transaction) { manualContext = context }
    }

    private func manualEntryForm(_ context: ManualSolveContext, close: (() -> Void)? = nil) -> some View {
        ManualSolveEntryView(save: { milliseconds, penalty in
            model.saveManualSolve(milliseconds: milliseconds, penalty: penalty, context: context)
        }, close: close)
    }

    private func openManualEntry() {
        guard canUseTimerTouch, isScrambleReady else { return }
        setManualContext(model.manualSolveContext())
    }

    private func performSwipeAction(_ direction: TimerSwipeDirection) {
        guard canUseTimerTouch, model.allowsIdleActions else { return }
        switch direction.action() {
        case .none: break
        case .deleteLastSolve: solveToDelete = model.groupSolves.min(by: Solve.newestFirst)
        case .newScramble: model.refresh(.manual)
        case .manualEntry: openManualEntry()
        }
    }

    private func timerTouchSurface(cancelZoneTop: CGFloat? = nil) -> some View {
        TimerTouchSurface(
            isEnabled: canUseTimerInput,
            scrambleFrame: showsTimingLayout ? .null : scrambleFrame,
            solveControlsFrame: !showsTimingLayout && model.lastSolve != nil ? postSolveControlsFrame : .null,
            canHoldOverControls: { canUseTimerTouch && isScrambleReady && entryMethod == .timer },
            onDown: { feedback, minimumHold in
                guard canUseTimerTouch, isTiming || isScrambleReady else { return }
                guard entryMethod == .timer || isTiming else { return }
                if usesTimerHaptics, !model.usesInspection {
                    feedback.prepare()
                }
                model.press(.touch, delayTenths: startDelayTenths, minimumHold: minimumHold) {
                    guard usesTimerHaptics, !isInTimerCancelZone else { return }
                    // Request feedback while the touch is still held.
                    feedback.impactOccurred()
                }
            },
            onUp: {
                if entryMethod == .manual {
                    openManualEntry()
                } else if isInTimerCancelZone {
                    model.cancelPress(.touch)
                } else {
                    model.release(.touch)
                }
                isInTimerCancelZone = false
            },
            onCancel: {
                model.cancelPress(.touch)
                isInTimerCancelZone = false
            },
            canBeginSwipe: { canUseTimerTouch && model.allowsIdleActions },
            onSwipe: performSwipeAction,
            isReady: model.isTouchReady,
            hasSettledPress: model.hasSettledPress,
            cancelZoneHeight: Self.cancelZoneHeight,
            cancelZoneTop: cancelZoneTop,
            onCancelZoneChange: { isInTimerCancelZone = $0 }
        )
        .allowsHitTesting(canUseTimerInput)
        .accessibilityHidden(true)
    }

    private var phoneControls: some View {
        HStack(spacing: 0) {
            projectMenu
            Spacer(minLength: 12)
            trailingControls
        }
        .frame(height: controlRowHeight)
        .disabled(model.busy || isTiming)
    }

    private func currentScramble(width: CGFloat, fontScale: CGFloat = 1) -> some View {
        Group {
            if isPreparingScramble {
                if showsGenerating {
                    Text(language.text("生成中…", "Generating…"))
                        .foregroundStyle(.secondary)
                }
            } else {
                scrambleFormula(width: width, fontScale: fontScale)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { scrambleFrame = $0 }
    }

    private func scrambleDiagram(alignment: SVGView.ContentAlignment = .bottomTrailing) -> some View {
        SVGView(svg: model.scramble?.svg, nextSVG: model.nextScramble?.svg, alignment: alignment,
                displayedSVG: $displayedDiagram)
            .opacity(isScrambleReady ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.text("当前打乱状态图", "Current scramble diagram"))
            .accessibilityIdentifier("timer.scramble-diagram")
            .accessibilityHidden(!isScrambleReady)
            .onDisappear { displayedDiagram = nil }
    }

    private func timerNumber(fontSize: CGFloat, height: CGFloat, minimumScale: CGFloat = 0.5) -> some View {
        Group {
            if let inspectionStart = model.inspectionStarted {
                let color = timerPressColor ?? .red
                TimelineView(.animation(minimumInterval: 0.1)) { _ in
                    let elapsed = inspectionStart.duration(to: .now)
                    let readout = switch TimerModel.penalty(forInspection: elapsed) {
                    case .dnf: "DNF"
                    case .plusTwo: "+2"
                    case nil: String(max(0, elapsed.components.seconds))
                    }
                    Text(readout)
                        .font(.system(size: fontSize, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(minimumScale)
                        .offset(y: readoutCenterAdjustment(fontSize: fontSize, scale: 1, weight: .light))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .accessibilityLabel(language.text("WCA 观察", "WCA inspection"))
                        .accessibilityValue(readout)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.activateAccessibleTimer() }
                        .accessibilityIdentifier("timer.inspection")
                }
                .overlay(alignment: .bottom) {
                    Text(language.text("WCA 观察", "WCA inspection"))
                        .font(.footnote)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.secondary)
                        .alignmentGuide(.bottom) { $0[.top] - 6 }
                        .accessibilityHidden(true)
                }
            } else if isTiming, displayDuringSolve == .observation {
                let prompt = language.text("还原中", "Solving")
                timerPrompt(prompt, fontSize: fontSize, height: height, minimumScale: minimumScale)
                    .accessibilityLabel(language.text("停止计时", "Stop timer"))
                    .accessibilityValue(prompt)
                    .accessibilityIdentifier("timer.readout")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.activateAccessibleTimer() }
            } else {
                timerReadoutView(fontSize: fontSize, height: height, minimumScale: minimumScale)
            }
        }
        .allowsHitTesting(false)
    }

    private func timerPrompt(_ prompt: String, fontSize: CGFloat, height: CGFloat,
                             minimumScale: CGFloat) -> some View {
        let scale: CGFloat = 0.45
        return Text(prompt)
            .font(.system(size: fontSize * scale, weight: .regular, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .offset(y: readoutCenterAdjustment(fontSize: fontSize, scale: scale, weight: .regular))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .transition(.identity)
    }

    private func timerReadoutView(fontSize: CGFloat, height: CGFloat, minimumScale: CGFloat) -> some View {
        let entersManually = entryMethod == .manual && !isTiming
        let actionTitle = if entersManually {
            language.text("录入成绩", "Enter result")
        } else if isTiming {
            language.text("停止计时", "Stop timer")
        } else {
            language.text("开始计时", "Start timer")
        }
        let color = timerPressColor ?? .primary
        let crown = !showsTimingLayout && !model.isPressing && model.lastSolve?.resultSeconds != nil
            ? model.lastSolveCelebration?.crownKind : nil
        return TimelineView(.animation(minimumInterval: displayDuringSolve == .seconds ? 0.1 : 0.03,
                                paused: !isTiming)) { _ in
            let readout = timerReadoutContent(fontSize: fontSize)
            timerText(readout, crown: crown)
                .foregroundStyle(color)
                .contentTransition(.identity)
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .accessibilityLabel(actionTitle)
                .accessibilityValue((isTiming ? nil : model.lastSolve?.resultText) ?? String(readout.characters))
                .accessibilityHint(crown.flatMap { SolveCelebration.toastTitle(for: [$0], in: language) } ?? "")
                .accessibilityIdentifier("timer.readout")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if entersManually {
                        openManualEntry()
                    } else if isTiming || isScrambleReady {
                        model.activateAccessibleTimer()
                    }
                }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func timerText(_ readout: AttributedString, crown: SolveCelebration.Kind?) -> some View {
        if let crown {
            let digits: String? = switch crown {
            case .ao5: "5"
            case .ao12: "12"
            default: nil
            }
            Text(readout)
                .textRenderer(RecordCrownRenderer(digits: digits, hasTrailingPlus: readout.characters.last == "+"))
        } else {
            Text(readout)
        }
    }

    private func timerReadoutContent(fontSize: CGFloat) -> AttributedString {
        let font = Font.system(size: fontSize, design: .rounded)
        if let start = model.started {
            let duration = start.duration(to: .now)
            if displayDuringSolve == .seconds {
                let readout = TimerDisplay.wholeSeconds(duration)
                return AttributedString(readout, attributes: AttributeContainer.font(font.monospacedDigit()))
            }
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return timerReadout(seconds, fontSize: fontSize, showsPlus: false)
        }
        return finishedTimerReadout(model.lastSolve, fontSize: fontSize,
                                    showsPlus: UIDevice.current.userInterfaceIdiom == .pad)
    }

    private func finishedTimerReadout(_ solve: Solve?, fontSize: CGFloat, showsPlus: Bool) -> AttributedString {
        if solve?.penalty == .dnf {
            return AttributedString("DNF", attributes: AttributeContainer.font(.system(size: fontSize, design: .rounded)))
        }
        return timerReadout(solve?.resultSeconds ?? 0, fontSize: fontSize,
                            showsPlus: showsPlus && solve?.penalty == .plusTwo)
    }

    private func readoutCenterAdjustment(fontSize: CGFloat, scale: CGFloat, weight: UIFont.Weight) -> CGFloat {
        func capCenterOffset(size: CGFloat, weight: UIFont.Weight) -> CGFloat {
            let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            let font = UIFont(descriptor: descriptor, size: size)
            return (font.ascender + font.descender - font.capHeight) / 2
        }
        return capCenterOffset(size: fontSize, weight: .regular)
            - capCenterOffset(size: fontSize * scale, weight: weight)
    }

    private var postSolveControls: some View {
        Group {
            if !showsTimingLayout, let solve = model.lastSolve {
                let celebration = model.lastSolveCelebration
                let offsetStep: CGFloat = layoutDirection == .leftToRight ? 3 : -3
                let leadingOffset = offsetStep * (celebration == nil ? 1 : 1.5)

                HStack(spacing: 0) {
                    penaltyButton("+2", label: language.text("加两秒", "Add two seconds"),
                                  penalty: .plusTwo, solve: solve, horizontalOffset: leadingOffset)
                    penaltyButton("DNF", label: language.text("标记成绩无效", "Mark as did not finish"),
                                  penalty: .dnf, solve: solve, horizontalOffset: leadingOffset - offsetStep)
                    Button(role: .destructive) {
                        model.cancelPress()
                        solveToDelete = solve
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.secondary)
                            .modifier(CompactControlTarget(minimumWidth: compactControlSize,
                                                           horizontalOffset: leadingOffset - 2 * offsetStep, visualScale: 0.82))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text("删除这条成绩", "Delete this solve"))
                    if let celebration {
                        Button {
                            // A replay during the delay also satisfies the first playback.
                            _ = model.takeAutomaticCelebration()
                            playCelebration(celebration)
                            AppTelemetry.record(.featureUsed(.celebrationReplayed))
                        } label: {
                            Image(systemName: "party.popper")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.secondary)
                                .modifier(CompactControlTarget(minimumWidth: compactControlSize,
                                                               horizontalOffset: leadingOffset - 3 * offsetStep, visualScale: 0.74))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.text("重播庆祝", "Replay celebration"))
                        .accessibilityIdentifier("timer.celebration-replay")
                    }
                }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { postSolveControlsFrame = $0 }
                .offset(x: layoutDirection == .leftToRight ? 2 : -2)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        // Keep the readout and summary layout tied to the original row height.
        .frame(height: compactControlSize)
    }

    private func penaltyButton(_ title: String, label: String, penalty: SolvePenalty, solve: Solve,
                               horizontalOffset: CGFloat) -> some View {
        Button {
            model.togglePenalty(penalty)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(solve.penalty == penalty ? Color.accentColor : Color.secondary)
                .opacity(solve.allowsPenaltyChange || solve.penalty == penalty ? 1 : 0.5)
                .modifier(CompactControlTarget(minimumWidth: compactControlSize, horizontalOffset: horizontalOffset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("timer.penalty.\(penalty.rawValue)")
        .accessibilityAddTraits(solve.penalty == penalty ? .isSelected : [])
        .disabled(!solve.allowsPenaltyChange)
    }

    private func longestTimerWidth(parts: [String], fontSize: CGFloat) -> CGFloat {
        let wholeTime = parts.dropLast().joined()
        let fraction = (parts.last ?? "") + "+"
        func width(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
            let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let rounded = font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor
            return (text as NSString).size(withAttributes: [.font: UIFont(descriptor: rounded, size: size)]).width
        }
        return ceil(width(wholeTime, size: fontSize, weight: .regular)
            + width(fraction, size: fontSize * 0.55, weight: .bold))
    }

    private func timerReadout(_ seconds: Double, fontSize: CGFloat, showsPlus: Bool) -> AttributedString {
        var parts = TimerModel.displayParts(seconds)
        if showsPlus {
            parts[parts.count - 1] += "+"
        }
        var readout = AttributedString()
        for (index, part) in parts.enumerated() {
            let isMilliseconds = index == parts.count - 1
            let size = isMilliseconds ? fontSize * 0.55 : fontSize
            var run = AttributedString(part)
            run.font = .system(size: size, weight: isMilliseconds ? .bold : .regular, design: .rounded).monospacedDigit()
            readout.append(run)
        }
        return readout
    }

    private func scrambleFormula(width: CGFloat, fontScale: CGFloat) -> some View {
        let algorithm = model.scramble?.algorithm ?? language.text("准备你的下一次挑战", "Ready for your next solve")
        let preservesMegaminxRows = model.mode == .standard && model.event == "minx"
        let alignsMegaminxRows = preservesMegaminxRows && model.scramble != nil
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let padWidthProgress = min(1, max(0, (width - 600) / 600))
        let preferredSize = isPad
            ? scrambleFontSize * (1 + 0.6 * padWidthProgress)
            : (preservesMegaminxRows ? standardMegaminxFontSize : scrambleFontSize)
        var fontSize = preferredSize * fontScale
        if alignsMegaminxRows {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let widestLine = algorithm.components(separatedBy: .newlines).map { line in
                (line as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            if widestLine > width - 2 {
                fontSize *= max(1, width - 2) / widestLine
            }
        }
        let minimumSize = min(fontSize, 1)
        let sizes = Array(stride(from: fontSize, to: minimumSize, by: -0.5)) + [minimumSize]
        return ViewThatFits(in: .vertical) {
            ForEach(sizes, id: \.self) { size in
                Text(algorithm)
                    .font(.system(size: size, design: .monospaced))
                    .multilineTextAlignment(alignsMegaminxRows ? .leading : .center)
                    .lineSpacing((preservesMegaminxRows ? 4 : 7) * size / fontSize)
                    .fixedSize(horizontal: alignsMegaminxRows, vertical: true)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(algorithm)
        .accessibilityIdentifier(model.scramble == nil ? "timer.placeholder" : "timer.scramble")
    }

    private var projectMenu: some View {
        EventPicker(model: model, isPresented: $showsProjectList, minimumTargetWidth: headerControlTargetWidth)
    }

    private var padProjectToolbarAnchor: some View {
        // Let the system make room for the window controls and place the project on the tab row.
        Color.clear
            .frame(width: EventPicker.minimumButtonWidth, height: controlRowHeight)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if frame.minY >= 0 { padProjectAnchor = frame }
            }
            .padding(.leading, padProjectToolbarInset)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var padProjectToolbarButton: some View {
        GeometryReader { geometry in
            if let anchor = padProjectAnchor {
                let bounds = geometry.frame(in: .global)
                let isRightToLeft = layoutDirection == .rightToLeft
                let leading = isRightToLeft ? bounds.maxX - anchor.maxX : anchor.minX - bounds.minX
                // The three icon-only tabs occupy about 154 pt at the center of the window.
                let tabBarReserve: CGFloat = 96
                let titleSpace = bounds.width / 2 - leading - tabBarReserve - EventPicker.minimumButtonWidth
                EventPicker(model: model, isPresented: $showsProjectList, large: true,
                            titleWidthLimit: titleSpace >= 24 ? titleSpace : 0,
                            minimumTargetWidth: headerControlTargetWidth)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(model.busy || isTiming)
                    .offset(x: isRightToLeft ? -leading : leading, y: anchor.minY - bounds.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

#if DEBUG
    // Measure each production button without a constrained parent.
    @MainActor
    private func measurePickerWidths() {
        func width<V: View>(_ view: V, language: AppLanguage) -> CGFloat {
            let host = UIHostingController(rootView: view
                .fixedSize(horizontal: true, vertical: true)
                .environment(\.locale, language.locale)
                .dynamicTypeSize(.large))
            return host.sizeThatFits(in: CGSize(width: 2_000, height: 100)).width
        }
        let choices = ScrambleCatalog.standard + ScrambleCatalog.training
        let rows = AppLanguage.allCases.flatMap { language in
            choices.map { choice in
                ["language": language.rawValue, "id": choice.id,
                 "title": ScrambleCatalog.trainingSelectionTitle(choice.id, in: language) ?? choice.title(in: language),
                 "compactPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: false,
                                                                  minimumTargetWidth: headerControlTargetWidth, action: {}),
                                        language: language),
                 "regularPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: true,
                                                                  minimumTargetWidth: headerControlTargetWidth, action: {}),
                                        language: language)] as [String: Any]
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL.documentsDirectory.appending(path: "picker-widths.json"), options: .atomic)
        } catch {
            assertionFailure("Could not save Picker measurements: \(error)")
        }
    }
#endif
    @ViewBuilder private var trailingControls: some View {
        if canShowAssist {
            assistButton
        }
    }

    private func playCelebration(_ record: SolveCelebration) {
        showsCelebrationToast = false
        celebrationScoreMotion = .rest
        confettiBurst = TimerConfettiBurst(record: record)
    }

    private func stopCelebration() {
        showsCelebrationToast = false
        celebrationScoreMotion = .rest
        confettiBurst = nil
    }

    @ViewBuilder
    private var celebrationConfetti: some View {
        if let confettiBurst, isTimerActive, !showsTimingLayout {
            confettiBurst.view(reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var celebrationToast: some View {
        if let confettiBurst, showsCelebrationToast, isTimerActive, !showsTimingLayout,
           let title = SolveCelebration.toastTitle(for: Set(confettiBurst.record.achievements.map(\.kind)), in: language) {
            celebrationPill(title)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
                .transition(reduceMotion ? .identity : .opacity)
        }
    }

    private func celebrationPill(_ title: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } icon: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.secondary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, celebrationPillPadding)
        .background(.thickMaterial, in: .capsule)
        .background {
            Capsule()
                .fill(.black.opacity(0.04))
                .blur(radius: 5)
                .offset(y: 3)
        }
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("timer.celebration-toast")
    }

    private var assistButton: some View {
        Button {
            guard !model.isPressing, let algorithm = model.scramble?.algorithm else { return }
            model.cancelPress()
            isInTimerCancelZone = false
            hasTimerKeyboardFocus = false
            assistScramble = AssistScramble(event: model.event,
                                            groupID: model.currentGroup?.id ?? SolveGroup.initialID(for: model.event),
                                            algorithm: algorithm,
                                            usesDuoModal: isDuoInnerDisplay || isDuoOuterDisplay)
            AppTelemetry.record(.featureUsed(.assistOpened))
        } label: {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .frame(width: headerControlTargetWidth, height: controlRowHeight, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(language.text("辅助公式", "Formula hints"))
        .accessibilityIdentifier("timer.formula-hints")
    }

    private var canShowAssist: Bool {
        !AssistMethod.available(for: model.event).isEmpty
            && isScrambleReady && !showsTimingLayout
    }
}

extension SolveCelebration {
    static func toastTitle(for kinds: Set<Kind>, in language: AppLanguage) -> String? {
        switch kinds {
        case [.first]: language.text("首次成绩", "First result")
        case [.single]: language.text("单次新纪录", "Single PB")
        case [.ao5]: language.text("Ao5 新纪录", "Ao5 PB")
        case [.ao12]: language.text("Ao12 新纪录", "Ao12 PB")
        case [.single, .ao5]: language.text("单次、Ao5 新纪录", "Single & Ao5 PBs")
        case [.single, .ao12]: language.text("单次、Ao12 新纪录", "Single & Ao12 PBs")
        case [.ao5, .ao12]: language.text("Ao5、Ao12 新纪录", "Ao5 & Ao12 PBs")
        case [.single, .ao5, .ao12]: language.text("单次、Ao5、Ao12 新纪录", "Single, Ao5 & Ao12 PBs")
        default: nil
        }
    }
}

private struct RecordCrownRenderer: TextRenderer {
    let digits: String?
    let hasTrailingPlus: Bool

    var displayPadding: EdgeInsets { EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout { context.draw(line) }
        guard !layout.isTruncated, let line = layout.last,
              let glyph = line.reversed().lazy.flatMap({ $0.reversed() }).dropFirst(hasTrailingPlus ? 1 : 0).first else {
            return
        }

        let digit = glyph.typographicBounds
        let width = min(24, digit.width * 0.9)
        let height = width * 0.54
        let capTop = digit.origin.y - digit.ascent * 0.79
        let position = CGPoint(x: digit.rect.maxX - width * 0.35, y: capTop - height * 0.65)
        let gold = context.environment.colorScheme == .dark
            ? Color(red: 0.78, green: 0.65, blue: 0.42)
            : Color(red: 0.56, green: 0.40, blue: 0.16)

        // Keep the knockout in its own layer so it can only erase the gold.
        context.drawLayer { layer in
            layer.translateBy(x: position.x, y: position.y)
            layer.rotate(by: .degrees(17))
            layer.translateBy(x: -width / 2, y: -height / 2)
            layer.fill(crownPath(width: width, height: height), with: .color(gold))
            if let digits {
                layer.blendMode = .destinationOut
                layer.draw(Text(digits).font(.system(size: height * 0.60, weight: .heavy, design: .rounded)),
                           at: CGPoint(x: width / 2, y: height * 0.70))
            }
        }
    }

    private func crownPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.addLines([
                .zero,
                CGPoint(x: width * 0.25, y: height * 0.37),
                CGPoint(x: width * 0.50, y: 0),
                CGPoint(x: width * 0.75, y: height * 0.37),
                CGPoint(x: width, y: 0),
                CGPoint(x: width * 0.94, y: height),
                CGPoint(x: width * 0.06, y: height)
            ])
            path.closeSubpath()
        }
    }
}

private struct TimerConfettiBurst {
    static let duration = 1.2
    private static let colors: [Color] = [
        .pink, .orange, .yellow, .green, .cyan, .blue, .purple
    ]

    private struct Particle {
        let side: CGFloat
        let inwardReach: CGFloat
        let riseHeight: CGFloat
        let spin: Double
        let phase: Double
        let width: CGFloat
        let color: Color
    }

    let record: SolveCelebration
    let start = ContinuousClock.now

    private let particles = (0..<64).map { index in
        Particle(
            side: index.isMultiple(of: 2) ? -1 : 1,
            inwardReach: .random(in: 0.22...0.64),
            riseHeight: .random(in: 0.48...0.72),
            spin: .random(in: -12...12),
            phase: .random(in: 0...(2 * .pi)),
            width: .random(in: 4...8),
            color: Self.colors[index % Self.colors.count]
        )
    }

    @ViewBuilder
    func view(reduceMotion: Bool) -> some View {
        if reduceMotion {
            paper(at: 0.40)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                paper(at: start.duration(to: .now) / .seconds(1))
            }
        }
    }

    private func paper(at elapsed: Double) -> some View {
        Canvas { context, size in
            guard elapsed < Self.duration else { return }
            let opacity = min(1, max(0, (Self.duration - elapsed) / 0.28))
            let rise = 1 - exp(-7 * elapsed)
            let drift = 1 - exp(-3.5 * elapsed)
            let fallTime = max(0, elapsed - 0.26)
            let fall = 0.30 * fallTime * fallTime
            for particle in particles {
                let inwardTravel = particle.inwardReach * drift
                let x = size.width * (0.5 + particle.side * (0.5 - inwardTravel))
                let y = size.height * (1 - particle.riseHeight * rise + fall)
                let width = particle.width * max(0.22, abs(cos(particle.phase + 11 * elapsed)))
                let shape = CGRect(x: -width / 2, y: -particle.width * 0.75, width: width, height: particle.width * 1.5)
                var piece = context
                piece.opacity = opacity
                piece.translateBy(x: x, y: y)
                piece.rotate(by: .radians(particle.phase + particle.spin * elapsed))
                piece.fill(Path(roundedRect: shape, cornerRadius: 1), with: .color(particle.color))
            }
        }
    }
}

private struct LandscapeScrambleLayout: Layout {
    private let minimumGap: CGFloat = 16
    private let maximumGap: CGFloat = 48

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let diagram = subviews.last else { return }
        let diagramSize = diagram.sizeThatFits(.unspecified)
        let formula = subviews.count > 1 ? subviews.first : nil
        let formulaProposal = ProposedViewSize(width: bounds.width,
                                              height: max(0, bounds.height - diagramSize.height - minimumGap))
        let formulaHeight = formula?.sizeThatFits(formulaProposal).height ?? 0
        let unusedHeight = max(0, bounds.height - formulaHeight - diagramSize.height)
        let gap = formula == nil ? 0 : min(maximumGap, max(minimumGap, unusedHeight / 3))
        let top = bounds.minY + max(0, unusedHeight - gap) / 2
        formula?.place(at: CGPoint(x: bounds.midX, y: top), anchor: .top, proposal: formulaProposal)
        diagram.place(at: CGPoint(x: bounds.midX, y: top + formulaHeight + gap),
                      anchor: .top, proposal: ProposedViewSize(diagramSize))
    }
}

private struct CompactControlTarget: ViewModifier {
    let minimumWidth: CGFloat
    let horizontalOffset: CGFloat
    var visualScale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(visualScale)
            .offset(x: horizontalOffset)
            .padding(.horizontal, 10)
            .frame(minWidth: minimumWidth)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

// Observe timer touches even when a selectable formula or result button is in front of the surface.
private struct TimerTouchSurface: UIViewRepresentable {
    var isEnabled: Bool
    var scrambleFrame: CGRect
    var solveControlsFrame: CGRect
    var canHoldOverControls: () -> Bool
    var onDown: (UIImpactFeedbackGenerator, Duration) -> Void
    var onUp: () -> Void
    var onCancel: () -> Void
    var canBeginSwipe: () -> Bool
    var onSwipe: (TimerSwipeDirection) -> Void
    var isReady: Bool
    var hasSettledPress: Bool
    var cancelZoneHeight: CGFloat
    var cancelZoneTop: CGFloat?
    var onCancelZoneChange: (Bool) -> Void

    func makeCoordinator() -> PressRecognizer { PressRecognizer() }

    func makeUIView(context: Context) -> Surface {
        Surface(recognizer: context.coordinator)
    }

    func updateUIView(_ view: Surface, context: Context) {
        view.update(with: self)
    }

    final class Surface: UIView {
        private let recognizer: PressRecognizer
        private let coveredRecognizer = PressRecognizer()

        init(recognizer: PressRecognizer) {
            self.recognizer = recognizer
            super.init(frame: .zero)
            coveredRecognizer.observesCoveredTouches = true
            let feedback = UIImpactFeedbackGenerator(style: .heavy, view: self)
            for recognizer in [recognizer, coveredRecognizer] {
                recognizer.surface = self
                recognizer.readyFeedback = feedback
            }
            addGestureRecognizer(recognizer)
        }

        required init?(coder: NSCoder) { nil }

        func update(with callbacks: TimerTouchSurface) {
            for recognizer in [recognizer, coveredRecognizer] {
                recognizer.callbacks = callbacks
                if recognizer.isEnabled != callbacks.isEnabled { recognizer.isEnabled = callbacks.isEnabled }
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow !== window { window?.removeGestureRecognizer(coveredRecognizer) }
            super.willMove(toWindow: newWindow)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window, coveredRecognizer.view !== window { window.addGestureRecognizer(coveredRecognizer) }
        }
    }

    final class PressRecognizer: UIGestureRecognizer {
        private enum Movement { case press, cancelZone, swipe }
        private enum Zone { case timer, scramble, controls }
        private static let controlHold = Duration.milliseconds(250)

        var callbacks: TimerTouchSurface?
        var readyFeedback: UIImpactFeedbackGenerator?
        weak var surface: Surface?
        var observesCoveredTouches = false
        private var initialPoint: CGPoint?
        private var movement = Movement.press
        private var canSwipe = false
        private var zone = Zone.timer
        private var holdTask: Task<Void, Never>?

        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            // A result button starts tracking on touch-down. Let it track until the timer wins the hold.
            if zone == .controls { return false }
            return super.canBePrevented(by: preventingGestureRecognizer)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard initialPoint == nil, touches.count == 1, let touch = touches.first,
                  let readyFeedback, let callbacks, let surface else {
                state = .failed
                return
            }
            let point = touch.location(in: surface.window)
            canSwipe = callbacks.canBeginSwipe()
            let hitsSurface = touch.view === surface || touch.view?.isDescendant(of: surface) == true
            guard hitsSurface != observesCoveredTouches else {
                state = .failed
                return
            }
            if hitsSurface {
                zone = .timer
            } else if callbacks.solveControlsFrame.contains(point), callbacks.canHoldOverControls() {
                zone = .controls
            } else if callbacks.scrambleFrame.contains(point), canSwipe {
                zone = .scramble
                initialPoint = point
                return
            } else {
                state = .failed
                return
            }
            initialPoint = point
            callbacks.onDown(readyFeedback, zone == .controls ? Self.controlHold : .zero)
            if zone == .controls {
                holdTask = Task { [weak self] in
                    do { try await Task.sleep(for: Self.controlHold) }
                    catch { return }
                    guard let self, self.state == .possible, self.movement == .press else { return }
                    // Take over before release so a long hold can't also activate the button.
                    self.state = .began
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let point = touches.first?.location(in: surface?.window) else { return }
            trackMovement(to: point)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let initialPoint, let point = touches.first?.location(in: surface?.window) else { return }
            trackMovement(to: point)
            guard state != .failed else { return }
            let movement = self.movement
            if movement == .press, (zone == .scramble || (zone == .controls && state == .possible)) {
                state = .failed
                return
            }
            self.initialPoint = nil
            state = .recognized
            if movement == .swipe {
                let translation = CGSize(width: point.x - initialPoint.x, height: point.y - initialPoint.y)
                if let direction = TimerSwipeDirection(translation: translation) {
                    callbacks?.onSwipe(direction)
                }
            } else {
                callbacks?.onUp()
            }
        }

        private func trackMovement(to point: CGPoint) {
            guard let initialPoint, let callbacks, movement != .swipe else { return }
            let dx = point.x - initialPoint.x
            let dy = point.y - initialPoint.y
            if movement == .cancelZone {
                updateCancelZone(at: point, callbacks: callbacks)
            } else if hypot(dx, dy) > 10 {
                if callbacks.isReady, -dy > abs(dx) {
                    movement = .cancelZone
                    updateCancelZone(at: point, callbacks: callbacks)
                } else if canSwipe, !callbacks.hasSettledPress, abs(dx) > abs(dy) {
                    // Abandon the press at its movement limit. A swipe still needs to travel far enough.
                    movement = .swipe
                    if zone != .scramble { callbacks.onCancel() }
                    if zone != .timer, state == .possible { state = .began }
                } else if !callbacks.isReady {
                    state = .failed
                }
            }
        }

        private func updateCancelZone(at point: CGPoint, callbacks: TimerTouchSurface) {
            let top = callbacks.cancelZoneTop ?? surface?.window?.safeAreaInsets.top ?? 0
            let withinUpperBoundary = callbacks.cancelZoneTop == nil || point.y >= top
            callbacks.onCancelZoneChange(withinUpperBoundary && point.y <= top + callbacks.cancelZoneHeight)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .cancelled
        }

        override func reset() {
            holdTask?.cancel()
            holdTask = nil
            if initialPoint != nil, zone != .scramble { callbacks?.onCancel() }
            initialPoint = nil
            movement = .press
            canSwipe = false
            zone = .timer
            super.reset()
        }
    }
}

private struct CelebrationScoreMotion {
    let emphasis: CGFloat
    let sway: CGFloat

    static let rest = Self(emphasis: 0, sway: 0)
    static let steps: [(motion: Self, milliseconds: Int)] = [
        (Self(emphasis: 1, sway: -1), 180),
        (Self(emphasis: 1, sway: 1), 160),
        (Self(emphasis: 1, sway: -0.72), 160),
        (Self(emphasis: 1, sway: 0.56), 160),
        (.rest, 260)
    ]
}

private struct ScoreCelebration {
    let record: SolveCelebration
    let motion: CelebrationScoreMotion

    func motion(for kind: SolveCelebration.Kind) -> CelebrationScoreMotion? {
        record.achievements.contains { $0.kind == kind } ? motion : nil
    }
}

private struct TimerSummary: View {
    let model: TimerModel
    let height: CGFloat
    let scoreCelebration: ScoreCelebration?
    var twoColumns = false
    var usesLargeType = false
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var preferredFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title3) private var largeFontSize: CGFloat = 20

    private static let averageKinds: [SolveAverage] = [.mo3, .ao5, .ao12]

    var body: some View {
        let solves = model.groupSolves
        if !solves.isEmpty {
            summary(for: solves)
        }
    }

    private func summary(for solves: [Solve]) -> some View {
        let language = locale.appLanguage
        let latestCount = SolveAverage.ao12.count
        var validCount = 0
        var total = 0.0
        var best: Solve?
        var recent: [Solve] = []

        for solve in solves {
            if let seconds = solve.resultSeconds {
                validCount += 1
                total += seconds
                if let fastest = best, let fastestSeconds = fastest.resultSeconds {
                    if seconds < fastestSeconds || (seconds == fastestSeconds && Solve.newestFirst(solve, fastest)) {
                        best = solve
                    }
                } else {
                    best = solve
                }
            }

            if recent.count < latestCount || Solve.newestFirst(solve, recent[latestCount - 1]) {
                let index = recent.firstIndex { Solve.newestFirst(solve, $0) } ?? recent.endIndex
                recent.insert(solve, at: index)
                if recent.count > latestCount { recent.removeLast() }
            }
        }

        let preferredSize = usesLargeType ? largeFontSize : preferredFontSize
        let maximumRowHeight = usesLargeType ? preferredSize / 0.76 : 20
        let rowHeight = min(maximumRowHeight, height / (twoColumns ? 3 : 6))
        let fontSize = min(preferredSize, rowHeight * 0.76)

        let overall = VStack(spacing: 0) {
            row(nil, value: "\(validCount.formatted()) / \(solves.count.formatted())",
                accessibilityName: language.text("有效成绩次数 / 总次数", "Valid solves / Total attempts"),
                id: "count", fontSize: fontSize, height: rowHeight)
            if let best {
                row("mean", value: TimerModel.format(total / Double(validCount)),
                    accessibilityName: language.text("总平均", "Overall mean"),
                    id: "mean", fontSize: fontSize, height: rowHeight)
                row("best", value: best.resultText, accessibilityName: language.text("最好单次", "Best single"),
                    id: "best", fontSize: fontSize, height: rowHeight,
                    celebrationMotion: scoreCelebration?.motion(for: .single) ?? scoreCelebration?.motion(for: .first))
            }
        }
        let rolling = VStack(spacing: 0) {
            ForEach(Self.averageKinds.filter { recent.count >= $0.count }, id: \.self) { kind in
                let value = kind.summarize(recent.prefix(kind.count)).mean.map(TimerModel.format) ?? "DNF"
                let motion: CelebrationScoreMotion? = switch kind {
                case .ao5: scoreCelebration?.motion(for: .ao5)
                case .ao12: scoreCelebration?.motion(for: .ao12)
                default: nil
                }
                row(kind.title, value: value, accessibilityName: kind.title,
                    id: kind.title, fontSize: fontSize, height: rowHeight, celebrationMotion: motion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        return Group {
            if twoColumns {
                HStack(spacing: 12) {
                    overall
                    rolling
                }
            } else {
                VStack(spacing: 0) {
                    overall
                    rolling
                }
            }
        }
    }

    private func row(_ title: String?, value: String, accessibilityName: String,
                     id: String, fontSize: CGFloat, height: CGFloat,
                     celebrationMotion: CelebrationScoreMotion? = nil) -> some View {
        let motion = celebrationMotion ?? .rest
        let color = celebrationMotion == nil ? Color.primary : resultBestColor(for: colorScheme)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let title {
                Text("\(title):")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(value)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18)) { content in
                    content.foregroundStyle(color)
                }
                .scaleEffect(1 + 0.22 * motion.emphasis, anchor: .leading)
                .offset(x: 2 * motion.sway)
        }
            .font(.system(size: fontSize, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(value)
            .accessibilityIdentifier("timer-summary.\(id)")
    }
}

struct SVGView: UIViewRepresentable {
    enum ContentAlignment: String {
        case bottomTrailing = "right bottom"
        case topTrailing = "right top"
        case center
    }

    let svg: String?
    let nextSVG: String?
    var alignment: ContentAlignment = .bottomTrailing
    var displayedSVG: Binding<String?>?

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.setAlignment(alignment)
        context.coordinator.displayedSVG = displayedSVG
        context.coordinator.update(in: view, svg: svg, nextSVG: nextSVG)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    struct RenderRecovery {
        enum Action { case ignore, retry, report }

        private(set) var desiredSVG: String?
        private var attemptedRetry = false
        private(set) var exhausted = false

        mutating func request(_ svg: String?) {
            guard desiredSVG != svg else { return }
            desiredSVG = svg
            attemptedRetry = false
            exhausted = false
        }

        mutating func displayed() {
            attemptedRetry = false
        }

        mutating func failed(_ svg: String?) -> Action {
            guard let svg, svg == desiredSVG, !exhausted else { return .ignore }
            if !attemptedRetry {
                attemptedRetry = true
                return .retry
            }
            exhausted = true
            return .report
        }
    }

    // Keep the visible diagram intact while the other WebView loads its replacement.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var alignment = ContentAlignment.bottomTrailing
        private let onFailure: @MainActor (FailureReason) -> Void

        init(onFailure: @escaping @MainActor (FailureReason) -> Void = {
            AppTelemetry.record(.renderDiagram, $0, impact: .degraded)
        }) {
            self.onFailure = onFailure
        }

        func setAlignment(_ value: ContentAlignment) {
            guard alignment != value else { return }
            alignment = value
            for slot in slots {
                slot.svg = nil
                slot.navigation = nil
                slot.ready = false
            }
        }
        @MainActor private final class Slot {
            let view: WKWebView
            var svg: String?
            var navigation: WKNavigation?
            var ready = false

            init() {
                let configuration = WKWebViewConfiguration()
                configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                configuration.ignoresViewportScaleLimits = false
                view = WKWebView(frame: .zero, configuration: configuration)
                view.isOpaque = false
                view.backgroundColor = .clear
                view.scrollView.isScrollEnabled = false
                view.scrollView.pinchGestureRecognizer?.isEnabled = false
            }
        }

        private var slots: [Slot] = []
        private var visible: Slot?
        private var recovery = RenderRecovery()
        private var pendingPerformance: (
            start: AppTelemetry.PerformanceMeasurement,
            path: TimerPerformanceMetric.PreparationPath
        )?
        var displayedSVG: Binding<String?>?

        func update(in container: UIView, svg: String?, nextSVG: String?) {
            if svg != recovery.desiredSVG {
                pendingPerformance = nil
                if let svg, displayedSVG != nil, let start = AppTelemetry.performanceStart() {
                    let slot = slots.first { $0.svg == svg }
                    let path: TimerPerformanceMetric.PreparationPath = if slot?.ready == true {
                        .prefetchReady
                    } else if slot?.navigation != nil {
                        .prefetchPending
                    } else {
                        .onDemand
                    }
                    pendingPerformance = (start, path)
                }
            }
            recovery.request(svg)
            guard !recovery.exhausted else { return }
            if let svg, visible?.svg != svg {
                if let loaded = slots.first(where: { $0.svg == svg && $0.ready }) {
                    show(loaded)
                } else {
                    load(svg, in: container)
                    return
                }
            }
            reportDisplayedSVG()
            if let nextSVG, !slots.contains(where: { $0.svg == nextSVG }) {
                load(nextSVG, in: container)
            }
        }

        func stop() {
            recovery.request(nil)
            pendingPerformance = nil
            displayedSVG = nil
            for slot in slots {
                slot.view.navigationDelegate = nil
                slot.view.stopLoading()
            }
            visible = nil
            slots.removeAll()
        }

        private func load(_ svg: String, in container: UIView) {
            let slot: Slot
            if let spare = slots.first(where: { $0 !== visible }) {
                slot = spare
            } else {
                slot = Slot()
                slots.append(slot)
                slot.view.navigationDelegate = self
                slot.view.frame = container.bounds
                slot.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(slot.view)
            }
            guard slot.svg != svg || (!slot.ready && slot.navigation == nil) else { return }
            slot.svg = svg
            slot.ready = false
            // Keep the first page renderable. Hide only a replacement or preload.
            slot.view.isHidden = visible != nil
            let encodedSVG = Data(svg.utf8).base64EncodedString()
            slot.navigation = slot.view.loadHTMLString("""
                <!doctype html>
                <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
                <style>
                  html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
                  img { display: block; width: 100%; height: 100%; object-fit: contain; object-position: \(alignment.rawValue); }
                </style>
                <img src="data:image/svg+xml;base64,\(encodedSVG)" alt="">
                """, baseURL: nil)
            if slot.navigation == nil { fail(slot, reason: .webNavigationFailed) }
        }

        private func show(_ slot: Slot) {
            visible?.view.isHidden = true
            slot.view.isHidden = false
            visible = slot
            recovery.displayed()
        }

        private func fail(_ slot: Slot, reason: FailureReason) {
            slot.navigation = nil
            slot.ready = false
            if visible === slot {
                slot.view.isHidden = true
                visible = nil
            }
            guard let svg = slot.svg, let container = slot.view.superview else { return }
            switch recovery.failed(svg) {
            case .ignore:
                break
            case .retry:
                load(svg, in: container)
            case .report:
                pendingPerformance = nil
                visible?.view.isHidden = true
                visible = nil
                onFailure(reason)
            }
        }

        private func navigationFailed(_ webView: WKWebView, _ navigation: WKNavigation?, error: Error) {
            guard let navigation, let slot = slots.first(where: { $0.view === webView }),
                  slot.navigation === navigation else { return }
            let error = error as NSError
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                slot.navigation = nil
                return
            }
            fail(slot, reason: .webNavigationFailed)
        }

        private func reportDisplayedSVG() {
            guard let svg = recovery.desiredSVG, visible?.svg == svg else { return }
            if let measurement = pendingPerformance {
                pendingPerformance = nil
                AppTelemetry.record(.scrambleDiagram(measurement.path), since: measurement.start)
            }
            guard let displayedSVG, displayedSVG.wrappedValue != svg else { return }
            // Cached diagrams can be selected during updateUIView. Publish after that update.
            Task { @MainActor [weak self] in
                guard let self, self.recovery.desiredSVG == svg, self.visible?.svg == svg,
                      let displayedSVG = self.displayedSVG else { return }
                displayedSVG.wrappedValue = svg
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let navigation, let slot = slots.first(where: { $0.view === webView }),
                  slot.navigation === navigation else { return }
            slot.ready = true
            if let desiredSVG = recovery.desiredSVG, slot.svg == desiredSVG {
                show(slot)
                reportDisplayedSVG()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            navigationFailed(webView, navigation, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            navigationFailed(webView, navigation, error: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard let slot = slots.first(where: { $0.view === webView }) else { return }
            fail(slot, reason: .webContentTerminated)
        }
    }
}

struct EventPicker: View {
    static let minimumButtonWidth: CGFloat = 44
    @Bindable var model: TimerModel
    @Binding var isPresented: Bool
    var large = false
    var titleWidthLimit: CGFloat?
    var minimumTargetWidth = Self.minimumButtonWidth
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    @State private var browsingMode = ScrambleMode.standard
    @State private var expandedTrainingGroups: Set<String> = []

    var body: some View {
        Self.projectButton(event: model.event, language: language, large: large, titleWidthLimit: titleWidthLimit,
                           minimumTargetWidth: minimumTargetWidth) {
            guard !model.isPressing else { return }
            browsingMode = model.mode
            expandedTrainingGroups.removeAll()
            isPresented = true
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(ScrambleMode.allCases) { mode in
                        CapsuleSegmentButton(mode.title(in: language), isSelected: mode == browsingMode) {
                            browsingMode = mode
                        }
                        .accessibilityIdentifier("event.mode.\(mode.rawValue)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                List {
                    if browsingMode == .standard {
                        ForEach(ScrambleCatalog.standard, content: projectRow)
                    } else {
                        ForEach(ScrambleCatalog.trainingGroups(in: language), id: \.self) { group in
                            trainingGroupRow(group)
                            if expandedTrainingGroups.contains(group) {
                                ForEach(ScrambleCatalog.training.filter { $0.group(in: language) == group }) { choice in
                                    projectRow(choice)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
                .id(browsingMode)
                .listStyle(.plain)
            }
            .frame(width: 300)
            .frame(idealHeight: 400, maxHeight: 400)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func trainingGroupRow(_ group: String) -> some View {
        let isExpanded = expandedTrainingGroups.contains(group)
        return Button {
            withAnimation {
                if isExpanded {
                    expandedTrainingGroups.remove(group)
                } else {
                    expandedTrainingGroups.insert(group)
                }
            }
        } label: {
            HStack {
                Text(group)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? language.text("已展开", "Expanded") : language.text("已折叠", "Collapsed"))
    }

    private func projectRow(_ choice: ScrambleChoice) -> some View {
        Button {
            isPresented = false
            model.mode = browsingMode
            model.eventSelection = choice.id
        } label: {
            HStack {
                Text(choice.title(in: language))
                Spacer()
                if choice.id == model.event {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice.id == model.event ? .isSelected : [])
        .accessibilityIdentifier("event.choice.\(choice.id)")
    }

    static func projectButton(event: String, language: AppLanguage, large: Bool,
                              titleWidthLimit: CGFloat? = nil, minimumTargetWidth: CGFloat = minimumButtonWidth,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            projectMenuLabel(event: event, language: language, large: large, titleWidthLimit: titleWidthLimit)
                .frame(minWidth: minimumTargetWidth, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSize(large ? .regular : .small)
        .accessibilityLabel(language.text("打乱项目", "Event"))
        .accessibilityValue(ScrambleCatalog.title(event, in: language))
    }

    private static func projectMenuLabel(event: String, language: AppLanguage, large: Bool, titleWidthLimit: CGFloat?) -> some View {
        let iconID = String(event.prefix { $0 != "." })
        return HStack(spacing: 6) {
            Image("Event-\(iconID)")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            if titleWidthLimit != 0, let title = ScrambleCatalog.trainingSelectionTitle(event, in: language) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: titleWidthLimit, alignment: .leading)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(large ? .body.weight(.medium) : .subheadline.weight(.medium))
        .foregroundStyle(.primary)
    }

}

struct CapsuleSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minWidth: 44)
                .background(isSelected ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.cyan.opacity(0.14), Color(.systemBackground), Color.indigo.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { AppBackground() }
    }
}
