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
    @FocusState private var hasTimerKeyboardFocus: Bool
    @State private var idlePageFrame: CGRect?
    private var isTiming: Bool { model.started != nil }
    @Binding var isInTimerCancelZone: Bool
    private static let cancelZoneHeight: CGFloat = 88
    private var showsTimingLayout: Bool { isTiming || model.inspectionStarted != nil || model.isReady || isInTimerCancelZone }
    @State private var showsProjectList = false
    @State private var timerTouchResumesAt: ContinuousClock.Instant?
    @State private var solveToDelete: Solve?
    @State private var showsGenerating = false
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private let controlIconSize: CGFloat = 20
    private let controlRowHeight: CGFloat = 44
    private let compactControlSize: CGFloat = 32
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .footnote) private var standardMegaminxFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title3) private var scrambleFontSize: CGFloat = 20
    static let landscapeBottomInset: CGFloat = 8

    // The native iPad TabView uses the top bar in regular-width layouts.
    private var usesTopNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationStack {
                    page
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(showsTimingLayout ? .hidden : .visible, for: .navigationBar)
                        .toolbar {
                            if !usesTopNavigation {
                                ToolbarItem(placement: .topBarLeading) {
                                    // Keep the icon and text together as custom toolbar content.
                                    HStack(spacing: 0) {
                                        projectMenu
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .disabled(model.busy || model.started != nil)
                                }
                                .sharedBackgroundVisibility(.hidden)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                trailingControls
                                    .padding(.trailing, usesTopNavigation ? 20 : 0)
                                    .disabled(model.busy || model.started != nil)
                            }
                            .sharedBackgroundVisibility(.hidden)
                        }
                }
            } else {
                page
            }
        }
        .appBackground()
        .focusable(isTimerActive)
        .focusEffectDisabled()
        .focused($hasTimerKeyboardFocus)
        .onKeyPress(.space, phases: [.down, .up, .repeat]) { press in
            guard isTimerActive, !showsProjectList, solveToDelete == nil else { return .ignored }
            switch press.phase {
            case .down: model.press(.keyboard, delayTenths: startDelayTenths)
            case .up: model.release(.keyboard)
            default: break
            }
            return .handled
        }
        .onChange(of: isTimerActive, initial: true) { _, active in
            hasTimerKeyboardFocus = active
            if !active {
                model.cancelPress()
                model.endInspection()
                isInTimerCancelZone = false
            }
        }
        .onChange(of: showsProjectList) { _, isShowing in
            model.cancelPress()
            if !isShowing {
                // The tap dismissing the popover can also reach the page beneath it.
                timerTouchResumesAt = .now.advanced(by: .milliseconds(250))
                if isTimerActive { hasTimerKeyboardFocus = true }
            }
        }
        .alert(language.text("确定删除这条成绩吗？", "Delete this solve?"), isPresented: Binding(
            get: { solveToDelete != nil },
            set: { if !$0 { solveToDelete = nil } }
        ), presenting: solveToDelete) { solve in
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("删除", "Delete"), role: .destructive) {
                guard model.lastSolve?.id == solve.id else { return }
                model.deleteLastSolve()
            }
        }
        .task(id: model.busy) {
            showsGenerating = false
            guard model.busy else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            if model.busy { showsGenerating = true }
        }
        .onChange(of: hasTimerKeyboardFocus) { _, focused in
            if !focused { model.cancelPress(.keyboard) }
        }
#if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--measure-picker") {
                measurePickerWidths()
            }
        }
#endif
    }
    private func cancelHint(atLowerDisplay: Bool) -> some View {
        Text(language.text("上滑到这里取消", "Slide here to cancel"))
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.top, isDuoOuterDisplay ? 24 : 12)
            .frame(maxWidth: .infinity)
            .frame(height: Self.cancelZoneHeight, alignment: .top)
            .background {
                LinearGradient(
                    colors: [Color.primary.opacity(0.07), .clear],
                    startPoint: .top, endPoint: .bottom
                )
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
            let fold = isDuoInnerDisplay && !isLandscape ? horizontalFold(in: geometry) : nil
            let usesDuoWideLayout = isLandscape && isDuoInnerDisplay
            Group {
                if let fold {
                    foldedPortraitPage(size: geometry.size, fold: fold, cancelZoneTop: frame.minY + fold.maxY)
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
                if model.isTouchReady || isInTimerCancelZone {
                    cancelHint(atLowerDisplay: fold != nil)
                        .offset(y: fold?.maxY ?? 0)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measuredFrame in
                if !showsTimingLayout { idlePageFrame = measuredFrame }
            }
        }
    }

    private func horizontalFold(in geometry: GeometryProxy) -> CGRect? {
        // The iOS 26 SDK does not declare SwiftUI's reserved region API.
#if compiler(>=6.4)
        if #available(iOS 27.1, *),
           let fold = geometry.reservedRegions(kind: .division).first?.frame,
           fold.width > fold.height, fold.minY > 0, fold.maxY < geometry.size.height {
            return fold
        }
#endif
        return nil
    }

    private func foldedPortraitPage(size: CGSize, fold: CGRect, cancelZoneTop: CGFloat) -> some View {
        let padding: CGFloat = 16
        let foldClearance: CGFloat = 8
        let width = max(1, size.width - 2 * padding)
        let upperHeight = max(0, fold.minY - 2 * foldClearance)
        let lowerHeight = max(0, size.height - fold.maxY - foldClearance)
        let formulaHeight = upperHeight * 0.48
        let footerHeight = max(0, upperHeight - formulaHeight - 8)
        let summaryWidth = min(144, width * 0.38)
        let diagramWidth = max(0, width - summaryWidth - 12)
        let timerAreaHeight = max(0, lowerHeight - controlRowHeight)
        let timerFontSize = max(1, min(90, timerAreaHeight * 0.36))

        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                currentScramble(width: width)
                    .frame(height: formulaHeight)
                HStack(alignment: .bottom, spacing: 12) {
                    TimerSummary(model: model, height: footerHeight)
                        .frame(width: summaryWidth)
                    scrambleDiagram()
                        .frame(width: diagramWidth * 0.8, height: min(140, footerHeight))
                        .frame(width: diagramWidth, alignment: .trailing)
                }
                .frame(height: footerHeight, alignment: .bottom)
            }
            .frame(width: width, height: upperHeight)
            .opacity(showsTimingLayout ? 0 : 1)
            .accessibilityHidden(showsTimingLayout)
            .padding(.top, foldClearance)

            Color.clear.frame(height: fold.height + 2 * foldClearance)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                phoneControls
                    .opacity(showsTimingLayout ? 0 : 1)
                    .allowsHitTesting(!showsTimingLayout)
                    .accessibilityHidden(showsTimingLayout)
                ZStack {
                    timerTouchSurface(cancelZoneTop: cancelZoneTop)
                    timerDisplay(fontSize: timerFontSize, numberHeight: timerFontSize * 1.2)
                }
                .frame(height: timerAreaHeight)
            }
            .frame(width: width, height: lowerHeight)
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
                            TimerSummary(model: model, height: summaryHeight, twoColumns: true)
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
        let showsControlsInPage = usesTopNavigation || UIDevice.current.userInterfaceIdiom != .pad
        let controlsHeight = showsControlsInPage ? controlRowHeight : 0
        let topClearance: CGFloat = 8
        let controlSpacing: CGFloat = showsControlsInPage ? 8 : 0
        let timerTouchTop = showsTimingLayout ? 0 : topClearance + controlsHeight + controlSpacing
        let recentRowHeight: CGFloat = 26
        let recentHalfHeight = 3 * recentRowHeight
        let formulaClearance = usesDuoWideLayout ? max(timerNumberHeight / 2, recentHalfHeight) : timerNumberHeight / 2
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
            .font: UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: recentValueTextStyle).pointSize,
                                                    weight: .regular)
        ]).width)
        let recentColumnGap: CGFloat = 24
        let sideWidth = 2 * (recentColumnWidth + recentColumnGap)
        let timerHorizontalPadding: CGFloat = 12
        let fitsRecentResults = (isPad || usesDuoWideLayout)
            && timerWidth - sideWidth >= longestTimerWidth(parts: longestTimeParts, fontSize: timerFontSize)
                + 2 * timerHorizontalPadding
            && height / 2 - recentHalfHeight >= topClearance + controlsHeight + controlSpacing + formulaHeight
            && height / 2 - recentHalfHeight >= diagramHeight + diagramBottomPadding

        return ZStack {
            timerTouchSurface()
                .frame(width: width, height: max(0, height - timerTouchTop))
                .frame(width: contentWidth, height: height, alignment: .bottom)

            if !showsTimingLayout {
                VStack(spacing: 0) {
                    if usesTopNavigation {
                        projectMenu
                            .frame(maxWidth: .infinity)
                            .frame(height: controlRowHeight)
                            .disabled(model.busy || model.started != nil)
                    } else if showsControlsInPage {
                        phoneControls
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
                            TimerSummary(model: model, height: summaryHeight, usesLargeType: usesLargeSummary)
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

    private func timerTouchSurface(cancelZoneTop: CGFloat? = nil) -> some View {
        TimerTouchSurface(
            onDown: {
                guard isTimerActive, !showsProjectList, solveToDelete == nil else { return }
                if let timerTouchResumesAt, ContinuousClock.now < timerTouchResumesAt { return }
                model.press(.touch, delayTenths: startDelayTenths)
            },
            onUp: {
                if isInTimerCancelZone {
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
            isReady: model.isTouchReady,
            cancelZoneHeight: Self.cancelZoneHeight,
            cancelZoneTop: cancelZoneTop,
            onCancelZoneChange: { isInTimerCancelZone = $0 }
        )
        .allowsHitTesting(isTimerActive && !showsProjectList && solveToDelete == nil)
        .accessibilityHidden(true)
    }

    private var phoneControls: some View {
        HStack(spacing: 0) {
            projectMenu
            Spacer(minLength: 12)
            trailingControls
        }
        .frame(height: controlRowHeight)
        .disabled(model.busy || model.started != nil)
    }

    private func currentScramble(width: CGFloat, fontScale: CGFloat = 1) -> some View {
        Group {
            if model.busy {
                if showsGenerating {
                    Text(language.text("生成中…", "Generating…"))
                        .foregroundStyle(.secondary)
                }
            } else {
                scrambleFormula(width: width, fontScale: fontScale)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scrambleDiagram(alignment: SVGView.ContentAlignment = .bottomTrailing) -> some View {
        SVGView(svg: model.scramble?.svg, nextSVG: model.nextScramble?.svg, alignment: alignment)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.text("当前打乱状态图", "Current scramble diagram"))
            .accessibilityIdentifier("timer.scramble-diagram")
    }

    private func timerNumber(fontSize: CGFloat, height: CGFloat, minimumScale: CGFloat = 0.5) -> some View {
        Group {
            if let inspectionStart = model.inspectionStarted {
                TimelineView(.animation(minimumInterval: 0.1)) { _ in
                    let elapsed = inspectionStart.duration(to: .now)
                    let readout = switch TimerModel.penalty(forInspection: elapsed) {
                    case .dnf: "DNF"
                    case .plusTwo: "+2"
                    case nil: String(max(0, elapsed.components.seconds))
                    }
                    Text(readout)
                        .font(.system(size: fontSize, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.isReady && !isInTimerCancelZone ? Color.green : Color.red)
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
            } else if model.isReady || isInTimerCancelZone {
                Text(isInTimerCancelZone
                     ? language.text("松开取消", "Release to cancel")
                     : language.text("松开开启", "Release to start"))
                    .font(.system(size: fontSize * 0.45, weight: .regular, design: .rounded))
                    .foregroundStyle(isInTimerCancelZone ? Color.red : Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(minimumScale)
                    .offset(y: readoutCenterAdjustment(fontSize: fontSize, scale: 0.45,
                                                       weight: .regular))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .transition(.identity)
                    .accessibilityIdentifier("timer.start-prompt")
            } else {
                timerReadoutView(fontSize: fontSize, height: height, minimumScale: minimumScale)
            }
        }
        .allowsHitTesting(false)
    }

    private func timerReadoutView(fontSize: CGFloat, height: CGFloat, minimumScale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03, paused: !isTiming)) { _ in
            let duration = model.started.map { $0.duration(to: .now) }
            let solve = model.lastSolve
            let seconds = duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? solve?.resultSeconds ?? 0
            let readout = solve?.penalty == .dnf
                ? AttributedString("DNF", attributes: AttributeContainer.font(.system(size: fontSize, design: .rounded)))
                : timerReadout(seconds, fontSize: fontSize,
                               showsPlus: UIDevice.current.userInterfaceIdiom == .pad && solve?.penalty == .plusTwo)
            Text(readout)
                .contentTransition(.identity)
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .accessibilityLabel(isTiming ? language.text("停止计时", "Stop timer") : language.text("开始计时", "Start timer"))
                .accessibilityValue(solve?.resultText ?? TimerModel.format(seconds))
                .accessibilityIdentifier("timer.readout")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.activateAccessibleTimer() }
        }
        .allowsHitTesting(false)
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
                HStack(spacing: 10) {
                    penaltyButton("+2", label: language.text("加两秒", "Add two seconds"), penalty: .plusTwo, selected: solve.penalty)
                    penaltyButton("DNF", label: language.text("标记成绩无效", "Mark as did not finish"), penalty: .dnf, selected: solve.penalty)
                    Button(role: .destructive) {
                        model.cancelPress()
                        solveToDelete = solve
                    } label: {
                        Image(systemName: "trash")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Color.secondary)
                            .modifier(CompactControlTarget(size: compactControlSize))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text("删除这条成绩", "Delete this solve"))
                }
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(height: compactControlSize)
    }

    private func penaltyButton(_ title: String, label: String, penalty: SolvePenalty, selected: SolvePenalty?) -> some View {
        Button {
            model.togglePenalty(penalty)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected == penalty ? Color.accentColor : Color.secondary)
                .modifier(CompactControlTarget(size: compactControlSize))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("timer.penalty.\(penalty.rawValue)")
        .accessibilityAddTraits(selected == penalty ? .isSelected : [])
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
        EventPicker(model: model, isPresented: $showsProjectList, large: usesTopNavigation)
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
                 "compactPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: false, action: {}), language: language),
                 "regularPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: true, action: {}), language: language)] as [String: Any]
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
    private var trailingControls: some View {
        HStack(spacing: 8) {
            trainingButton
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: controlRowHeight)
                .accessibilityHidden(true)
        }
    }

    private var trainingButton: some View { TrainingButton(model: model) }

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
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

// The touch surface sits behind page controls and cancels an armed start on drag.
private struct TimerTouchSurface: UIViewRepresentable {
    var onDown: () -> Void
    var onUp: () -> Void
    var onCancel: () -> Void
    var isReady: Bool
    var cancelZoneHeight: CGFloat
    var cancelZoneTop: CGFloat?
    var onCancelZoneChange: (Bool) -> Void

    func makeCoordinator() -> PressRecognizer { PressRecognizer() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addGestureRecognizer(context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.callbacks = self
    }

    final class PressRecognizer: UIGestureRecognizer {
        var callbacks: TimerTouchSurface?
        private var initialPoint: CGPoint?
        private var isDraggingUp = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard initialPoint == nil, touches.count == 1, let touch = touches.first else {
                state = .failed
                return
            }
            initialPoint = touch.location(in: view?.window)
            callbacks?.onDown()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let initialPoint,
                  let point = touches.first?.location(in: view?.window) else { return }
            let dx = point.x - initialPoint.x
            let dy = point.y - initialPoint.y
            if let callbacks, callbacks.isReady, isDraggingUp || -dy > abs(dx) {
                isDraggingUp = true
                updateCancelZone(at: point, callbacks: callbacks)
            } else if hypot(dx, dy) > 10 {
                state = .failed
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard initialPoint != nil else { return }
            if isDraggingUp, let callbacks, let touch = touches.first {
                updateCancelZone(at: touch.location(in: view?.window), callbacks: callbacks)
            }
            initialPoint = nil
            state = .recognized
            callbacks?.onUp()
        }

        private func updateCancelZone(at point: CGPoint, callbacks: TimerTouchSurface) {
            let top = callbacks.cancelZoneTop ?? view?.window?.safeAreaInsets.top ?? 0
            let withinUpperBoundary = callbacks.cancelZoneTop == nil || point.y >= top
            callbacks.onCancelZoneChange(withinUpperBoundary && point.y <= top + callbacks.cancelZoneHeight)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .cancelled
        }

        override func reset() {
            if initialPoint != nil { callbacks?.onCancel() }
            initialPoint = nil
            isDraggingUp = false
            super.reset()
        }
    }
}

private struct TimerSummary: View {
    let model: TimerModel
    let height: CGFloat
    var twoColumns = false
    var usesLargeType = false
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .footnote) private var preferredFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title3) private var largeFontSize: CGFloat = 20

    private static let averageKinds: [SolveAverage] = [.mo3, .ao5, .ao12]

    var body: some View {
        let solves = model.groupSolves
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
        let mean = validCount > 0 ? TimerModel.format(total / Double(validCount)) : "—"

        let overall = VStack(spacing: 0) {
            row(nil, value: "\(validCount.formatted()) / \(solves.count.formatted())",
                accessibilityName: language.text("有效成绩次数 / 总次数", "Valid solves / Total attempts"),
                id: "count", fontSize: fontSize, height: rowHeight)
            row("mean", value: mean, accessibilityName: language.text("总平均", "Overall mean"),
                id: "mean", fontSize: fontSize, height: rowHeight)
            row("best", value: best?.resultText ?? "—", accessibilityName: language.text("最好单次", "Best single"),
                id: "best", fontSize: fontSize, height: rowHeight)
        }
        let rolling = VStack(spacing: 0) {
            ForEach(Self.averageKinds, id: \.self) { kind in
                let value = recent.count >= kind.count
                    ? kind.summarize(recent.prefix(kind.count)).mean.map(TimerModel.format) ?? "DNF"
                    : "—"
                row(kind.title, value: value, accessibilityName: kind.title,
                    id: kind.title, fontSize: fontSize, height: rowHeight)
            }
        }

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
                     id: String, fontSize: CGFloat, height: CGFloat) -> some View {
        let text = if let title {
            Text("\(Text("\(title):").foregroundColor(.secondary)) \(value)")
        } else {
            Text(value)
        }
        return text
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
        case center
    }

    let svg: String?
    let nextSVG: String?
    var alignment: ContentAlignment = .bottomTrailing

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.setAlignment(alignment)
        context.coordinator.update(in: view, svg: svg, nextSVG: nextSVG)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // Keep the visible diagram intact while the other WebView loads its replacement.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var alignment = ContentAlignment.bottomTrailing

        func setAlignment(_ value: ContentAlignment) {
            guard alignment != value else { return }
            alignment = value
            slots.forEach { $0.svg = nil }
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
                view.isHidden = true
            }
        }

        private var slots: [Slot] = []
        private var visible: Slot?
        private var desiredSVG: String?

        func update(in container: UIView, svg: String?, nextSVG: String?) {
            desiredSVG = svg
            if let svg, visible?.svg != svg {
                if let loaded = slots.first(where: { $0.svg == svg && $0.ready }) {
                    show(loaded)
                } else {
                    load(svg, in: container)
                    return
                }
            }
            if let nextSVG, nextSVG != visible?.svg {
                load(nextSVG, in: container)
            }
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
            guard slot.svg != svg else { return }
            slot.svg = svg
            slot.ready = false
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
        }

        private func show(_ slot: Slot) {
            visible?.view.isHidden = true
            slot.view.isHidden = false
            visible = slot
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let slot = slots.first(where: { $0.view === webView }),
                  slot.navigation === navigation else { return }
            slot.ready = true
            if let desiredSVG, slot.svg == desiredSVG { show(slot) }
        }
    }
}

struct EventPicker: View {
    @Bindable var model: TimerModel
    @Binding var isPresented: Bool
    var large = false
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private var showsProjectList: Bool {
        get { isPresented }
        nonmutating set { isPresented = newValue }
    }
    var body: some View {
        Self.projectButton(event: model.event, language: language, large: large) {
            showsProjectList = true
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            List {
                if model.mode == .standard {
                    ForEach(ScrambleCatalog.standard, content: projectRow)
                } else {
                    ForEach(ScrambleCatalog.trainingGroups(in: language), id: \.self) { group in
                        DisclosureGroup(group) {
                            ForEach(ScrambleCatalog.training.filter { $0.group(in: language) == group }, content: projectRow)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(width: 300)
            .frame(idealHeight: 400, maxHeight: 400)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func projectRow(_ choice: ScrambleChoice) -> some View {
        Button {
            showsProjectList = false
            model.eventSelection = choice.id
        } label: {
            HStack {
                Text(choice.title(in: language))
                Spacer()
                if choice.id == model.event {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice.id == model.event ? .isSelected : [])
    }

    static func projectButton(event: String, language: AppLanguage, large: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            projectMenuLabel(event: event, language: language, large: large)
        }
        .buttonStyle(.plain)
        .controlSize(large ? .regular : .small)
        .accessibilityLabel(language.text("打乱项目", "Event"))
        .accessibilityValue(ScrambleCatalog.title(event, in: language))
    }

    static func projectMenuLabel(event: String, language: AppLanguage, large: Bool) -> some View {
        let iconID = String(event.prefix { $0 != "." })
        return HStack(spacing: 6) {
            Image("Event-\(iconID)")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            if let title = ScrambleCatalog.trainingSelectionTitle(event, in: language) {
                Text(title).lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(large ? .body.weight(.medium) : .subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

}

struct TrainingButton: View {
    @Bindable var model: TimerModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    var body: some View {
        Button {
            model.mode = model.mode == .training ? .standard : .training
        } label: {
            Image(systemName: "dumbbell")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(model.mode == .training ? Color.accentColor : Color.secondary)
                .modifier(CompactControlTarget(size: 32))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("训练模式", "Training"))
        .accessibilityValue(model.mode == .training ? language.text("已开启", "On") : language.text("已关闭", "Off"))
        .accessibilityAddTraits(model.mode == .training ? .isSelected : [])
        .accessibilityHint(language.text("切换标准打乱与训练打乱", "Switch between standard and training scrambles"))
        .frame(minHeight: 44)
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
