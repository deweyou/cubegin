import StoreKit
import SwiftUI
import UIKit

enum DuoDisplay: Equatable {
    case outer, inner, other

    init(hasHinge: Bool, matchesDuoModel: Bool, nativeShortEdge: CGFloat) {
        if hasHinge || (matchesDuoModel && nativeShortEdge == 2007) {
            self = .inner
        } else if matchesDuoModel && nativeShortEdge == 1398 {
            self = .outer
        } else {
            self = .other
        }
    }
}

struct LandscapeContentInsets {
    static let contentMargin: CGFloat = 24
    private static let clearEdgeMargin: CGFloat = 44
    private static let cutoutMargin: CGFloat = 16
    private static let railGap: CGFloat = 16

    let leading: CGFloat
    let trailing: CGFloat
    let headerTopOffset: CGFloat
    let scrambleColumnFraction: CGFloat
    private let safeLeading: CGFloat
    private let safeTrailing: CGFloat

    init(safeLeading: CGFloat, safeTrailing: CGFloat, cutoutOnRight: Bool, railWidth: CGFloat,
         leadingRailWidth: CGFloat? = nil, isDuoOuterDisplay: Bool = false) {
        scrambleColumnFraction = isDuoOuterDisplay ? 0.5 : 0.55
        self.safeLeading = safeLeading
        self.safeTrailing = safeTrailing
        if let leadingRailWidth {
            leading = leadingRailWidth + Self.railGap
            trailing = Self.clearEdgeMargin
        } else {
            leading = cutoutOnRight || safeLeading <= Self.contentMargin
                ? Self.clearEdgeMargin - safeLeading : Self.cutoutMargin
            trailing = railWidth + Self.railGap
        }
        // The cover camera center is 48 pt from the top; the controls normally center at 30 pt.
        headerTopOffset = leadingRailWidth != nil ? 18 : 0
    }

    // Lists and headers supply the inner margin; these are the remaining offsets.
    var containerLeading: CGFloat { leading - Self.contentMargin }
    var containerTrailing: CGFloat { trailing - Self.contentMargin }

    // A grouped Form extends its scroll content to the display edge when the
    // container crosses the safe area; the card margin then starts at that edge.
    var formLeadingMargin: CGFloat {
        containerLeading < 0 ? safeLeading + leading : Self.contentMargin
    }

    var formTrailingMargin: CGFloat {
        containerTrailing < 0 ? safeTrailing + trailing : Self.contentMargin
    }
}

private extension View {
    // Keep the same transition behind pinned headers on Results, Statistics, and Settings.
    func pinnedScrollHeader<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top, spacing: 0, content: header)
    }
}

struct AppTabsView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    var isActive: Bool
    let model: TimerModel

    @AppStorage(TimerModel.keepTimerScreenOnKey) private var keepsTimerScreenOn = true
    @AppStorage(ResultExtremes.includeDNFPreferenceKey) private var includesDNFInWorst = ResultExtremes.defaultIncludesDNF
    @State private var isInTimerCancelZone = false
    private var shouldKeepScreenOn: Bool {
        isActive && scenePhase == .active && selection == .home
            && (keepsTimerScreenOn || model.started != nil || model.inspectionStarted != nil)
    }
    private var showsTimingLayout: Bool {
        model.started != nil || model.inspectionStarted != nil || model.showsReadyFeedback || isInTimerCancelZone
    }
    @State private var selection = Destination.initial
    @State private var resultsPage = ResultsPage.solves
    @State private var viewedCharts: Set<ResultsChartMode> = []
    private var visibleResultsPage: ResultsPage? {
        isActive && scenePhase != .background && selection == .results ? resultsPage : nil
    }
    @State private var isSelectingResults = false
    @State private var interfaceOrientation: UIInterfaceOrientation = .unknown
    @State private var isDuoOuterDisplay = false
    @State private var isDuoInnerDisplay = false
    @Environment(\.scenePhase) private var scenePhase
    private let sideNavigationWidth: CGFloat = 52
    // Measured from the portrait tab capsule to the display edge on iPhone 17 Pro.
    private let sideNavigationEdgeGap: CGFloat = 21

    private enum Destination: String, CaseIterable {
        case home, results, settings

        @MainActor static var initial: Self {
            SettingsView.opensAboutForQA || SettingsView.opensFeedbackForQA
                || CloudKitResultsTransport.showsSyncPreview ? .settings : .home
        }

        func title(in language: AppLanguage) -> String {
            switch self {
            case .home: language.text("首页", "Home")
            case .results: language.text("成绩", "Results")
            case .settings: language.text("设置", "Settings")
            }
        }

        @MainActor var icon: Image {
            switch self {
            case .home: Image("NavigationHome")
            case .results: Image(uiImage: NavigationIcons.results)
            case .settings: Image(uiImage: NavigationIcons.settings)
            }
        }
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                GeometryReader { geometry in
                    let insets = geometry.safeAreaInsets
                    let trailingInset = insets.trailing
                    // Landscape right places the phone's top cutout on the left.
                    let canUseRightEdge = interfaceOrientation == .landscapeRight
                    // Safe area insets move with the camera during a 180-degree rotation.
                    let coverCameraOnLeft = insets.leading == insets.trailing
                        ? canUseRightEdge : insets.leading > insets.trailing
                    let railOnLeft = isDuoOuterDisplay && coverCameraOnLeft
                    let hasLowerRightCamera = isDuoOuterDisplay && !coverCameraOnLeft
                    // On the cover display the rail shares the lower camera's centerline.
                    let edgeGap = hasLowerRightCamera ? 11
                        : (canUseRightEdge ? sideNavigationEdgeGap : max(sideNavigationEdgeGap, trailingInset))
                    let usesSideNavigation = geometry.size.width > geometry.size.height
                    let usesRightStatusColumn = isDuoInnerDisplay
                        && trailingInset > insets.leading && trailingInset >= sideNavigationWidth
                    let trailingRailInset = usesRightStatusColumn
                        ? -(trailingInset + sideNavigationWidth) / 2 : edgeGap - trailingInset
                    // The cover camera sits 48 pt from the left edge.
                    let railInset = railOnLeft ? 48 - sideNavigationWidth / 2 - insets.leading : trailingRailInset
                    let contentRailWidth: CGFloat = usesRightStatusColumn ? 0
                        : sideNavigationWidth + railInset + (hasLowerRightCamera ? 4 : 0)
                    let contentInsets = usesSideNavigation ? LandscapeContentInsets(
                        safeLeading: insets.leading, safeTrailing: trailingInset, cutoutOnRight: isDuoOuterDisplay
                            ? hasLowerRightCamera : interfaceOrientation == .landscapeLeft,
                        railWidth: contentRailWidth,
                        leadingRailWidth: railOnLeft ? sideNavigationWidth + railInset : nil,
                        isDuoOuterDisplay: isDuoOuterDisplay
                    ) : nil
                    tabs(sideNavigationInset: usesSideNavigation ? railInset : nil,
                         railOnLeft: railOnLeft,
                         alignsSideNavigationWithCoverCamera: hasLowerRightCamera,
                         alignsSideNavigationWithStatusIndicators: usesRightStatusColumn,
                         contentInsets: contentInsets)
                }
                .background {
                    InterfaceOrientationReader(orientation: $interfaceOrientation,
                                               isDuoOuterDisplay: $isDuoOuterDisplay,
                                               isDuoInnerDisplay: $isDuoInnerDisplay)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
                .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
            } else {
                tabs(sideNavigationInset: nil)
            }
        }
        .task(id: model.event) {
            model.refresh()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.requestCloudSync()
            } else {
                model.interrupt()
            }
        }
        .onChange(of: shouldKeepScreenOn, initial: true) { _, keepScreenOn in
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
        .onChange(of: visibleResultsPage, initial: true) { _, page in
            if page != .statistics { viewedCharts.removeAll() }
            switch page {
            case .statistics:
                AppTelemetry.record(.statisticsViewed)
            case .solves where !model.groupSolves.isEmpty:
                AppTelemetry.record(.solveListViewed(includesDNF: includesDNFInWorst))
            default:
                break
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert(language.text("提示", "Notice"), isPresented: Binding(get: { isActive && model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(language.text("好", "OK")) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private func tabs(sideNavigationInset: CGFloat?,
                      railOnLeft: Bool = false,
                      alignsSideNavigationWithCoverCamera: Bool = false,
                      alignsSideNavigationWithStatusIndicators: Bool = false,
                      contentInsets: LandscapeContentInsets? = nil) -> some View {
        let usesSideNavigation = sideNavigationInset != nil
        let railSpace = sideNavigationInset.map { max(0, sideNavigationWidth + $0) } ?? 0

        return TabView(selection: $selection) {
            Tab(value: Destination.home) {
                ContentView(
                    model: model,
                    isTimerActive: isActive && selection == .home && scenePhase == .active,
                    leadingNavigationWidth: railOnLeft ? railSpace : 0,
                    trailingNavigationWidth: railOnLeft ? 0 : railSpace,
                    navigationInset: sideNavigationInset ?? 0,
                    navigationOnLeft: railOnLeft,
                    isDuoInnerDisplay: isDuoInnerDisplay,
                    isDuoOuterDisplay: isDuoOuterDisplay,
                    landscapeContentInsets: contentInsets,
                    isInTimerCancelZone: $isInTimerCancelZone
                )
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .labelStyle(.titleAndIcon)
                    .toolbar(usesSideNavigation || showsTimingLayout ? .hidden : .automatic, for: .tabBar)
            } label: {
                tabLabel(.home)
            }
            Tab(value: Destination.results) {
                ResultsView(model: model, page: $resultsPage,
                            isSelecting: $isSelectingResults, usesSideNavigation: usesSideNavigation,
                            isReviewContextActive: { isActive && selection == .results && !showsTimingLayout },
                            contentInsets: isSelectingResults ? nil : contentInsets,
                            showsStatistics: visibleResultsPage == .statistics) { mode in
                    if visibleResultsPage == .statistics, viewedCharts.insert(mode).inserted {
                        AppTelemetry.record(.featureUsed(.chartViewed(mode)))
                    }
                }
                    .labelStyle(.titleAndIcon)
                    .toolbar(usesSideNavigation || isSelectingResults ? .hidden : .automatic, for: .tabBar)
            } label: {
                tabLabel(.results)
            }
            Tab(value: Destination.settings) {
                SettingsView(model: model, contentInsets: contentInsets, isSelected: selection == .settings)
                    .labelStyle(.titleAndIcon)
                    .toolbar(usesSideNavigation ? .hidden : .automatic, for: .tabBar)
            } label: {
                tabLabel(.settings)
            }
        }
        .labelStyle(.iconOnly)
        .overlay(alignment: railOnLeft ? .bottomLeading : .bottomTrailing) {
            ZStack {
                if let sideNavigationInset, !showsTimingLayout, !(selection == .results && isSelectingResults) {
                    sideNavigation
                        .padding(railOnLeft ? .leading : .trailing, sideNavigationInset)
                        .padding(.bottom, ContentView.landscapeBottomInset + (alignsSideNavigationWithCoverCamera ? 44 : 0))
                        .offset(x: alignsSideNavigationWithCoverCamera || alignsSideNavigationWithStatusIndicators ? 10 : 0)
                }
            }
            .allowsHitTesting(!showsTimingLayout)
            .accessibilityHidden(showsTimingLayout)
        }
    }

    private func tabLabel(_ destination: Destination) -> some View {
        Label {
            Text(destination.title(in: language))
        } icon: {
            destination.icon
        }
    }

    private var sideNavigation: some View {
        VStack(spacing: 2) {
            ForEach(Destination.allCases, id: \.self) { destination in
                Button {
                    selection = destination
                } label: {
                    destination.icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .background {
                            if selection == destination {
                                Circle().fill(.primary.opacity(0.10))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title(in: language))
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
                .accessibilityIdentifier("side-nav.\(destination.rawValue)")
            }
        }
        .padding(.vertical, 4)
        .frame(width: sideNavigationWidth)
        .glassEffect(.regular, in: .capsule)
    }

}

private struct InterfaceOrientationReader: UIViewRepresentable {
    @Binding var orientation: UIInterfaceOrientation
    @Binding var isDuoOuterDisplay: Bool
    @Binding var isDuoInnerDisplay: Bool

    func makeUIView(context: Context) -> OrientationView {
        OrientationView()
    }

    func updateUIView(_ view: OrientationView, context: Context) {
        view.onChange = { value, outerDisplay, innerDisplay in
            if orientation != value { orientation = value }
            if isDuoOuterDisplay != outerDisplay { isDuoOuterDisplay = outerDisplay }
            if isDuoInnerDisplay != innerDisplay { isDuoInnerDisplay = innerDisplay }
        }
        view.reportOrientation()
    }

    final class OrientationView: UIView {
        var onChange: ((UIInterfaceOrientation, Bool, Bool) -> Void)?
#if DEBUG
        private var requestedQAOrientation = false
#endif

        private static let isDuo: Bool = {
#if targetEnvironment(simulator)
            let environment = ProcessInfo.processInfo.environment
#if DEBUG
            if environment["CUBEGIN_UI_TEST_UNRECOGNIZED_DUO"] == "1" { return false }
#endif
            return environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"
#else
            var device = utsname()
            uname(&device)
            return withUnsafeBytes(of: device.machine) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) == "iPhone19,4"
            }
#endif
        }()

        init() {
            super.init(frame: .zero)
            NotificationCenter.default.addObserver(self, selector: #selector(reportOrientation),
                name: UIDevice.orientationDidChangeNotification, object: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportOrientation()
        }

        @objc func reportOrientation() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, let scene = window.windowScene else { return }
                let nativeSize = scene.screen.nativeBounds.size
                let display = DuoDisplay(
                    hasHinge: hasHinge(in: window),
                    matchesDuoModel: Self.isDuo,
                    nativeShortEdge: min(nativeSize.width, nativeSize.height)
                )
#if DEBUG
                if display == .outer, !requestedQAOrientation,
                   let tabSide = ProcessInfo.processInfo.environment["CUBEGIN_UI_TEST_DUO_TAB_SIDE"] {
                    requestedQAOrientation = true
                    let orientation: UIInterfaceOrientationMask = tabSide == "left" ? .landscapeRight : .landscapeLeft
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
                        print("Duo QA orientation request failed: \(error)")
                    }
                }
#endif
                onChange?(scene.effectiveGeometry.interfaceOrientation, display == .outer, display == .inner)
            }
        }

        private func hasHinge(in window: UIWindow) -> Bool {
#if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                return !window.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            }
#endif
            return false
        }
    }
}

// Fixed-size images keep native bars from overriding symbol point sizes.
@MainActor private enum NavigationIcons {
    static let results = icon("list.bullet")
    static let settings = icon("gearshape")
    static let solveDetailDelete = icon("trash", side: 20)

    private static func icon(_ name: String, side: CGFloat = 28) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return UIImage() }
        let scale = min(side / symbol.size.width, side / symbol.size.height)
        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(
                x: (side - size.width) / 2, y: (side - size.height) / 2,
                width: size.width, height: size.height
            ))
        }.withRenderingMode(.alwaysTemplate)
    }
}

private enum ResultsPage: String, CaseIterable, Identifiable {
    case solves, statistics
    var id: Self { self }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .solves: language.text("成绩", "Results")
        case .statistics: language.text("统计", "Statistics")
        }
    }
}

enum ResultsReviewEligibility {
    static func qualifies(_ solves: [Solve], calendar: Calendar = .current) -> Bool {
        guard solves.count >= 12 else { return false }
        var validCount = 0
        var practiceDays: Set<Date> = []
        for solve in solves where solve.resultSeconds != nil {
            validCount += 1
            if practiceDays.count < 3 {
                practiceDays.insert(calendar.startOfDay(for: solve.date))
            }
            if validCount >= 12, practiceDays.count >= 3 { return true }
        }
        return false
    }
}

private struct AverageDestination: Hashable {
    let kind: SolveAverage
    let newestSolveID: Solve.ID
}

private struct AverageHighlightInput: Equatable {
    let kind: SolveAverage
    let times: [Double?]
    let includesDNF: Bool
}

private struct ResultsView: View {
    @AppStorage(ResultExtremes.includeDNFPreferenceKey) private var includesDNFInWorst = ResultExtremes.defaultIncludesDNF
    @AppStorage("results.didRequestAppStoreReview") private var didRequestAppStoreReview = false
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .caption) private var averageSolveTileWidth = 104.0
    private var language: AppLanguage { locale.appLanguage }
    @Bindable var model: TimerModel
    @State private var detailPath = NavigationPath()
    @State private var averageKind: SolveAverage?
    @State private var resultTypeOverflow: HorizontalScrollOverflow = []
    @State private var averageHighlights: (input: AverageHighlightInput, extremes: ResultExtremes)?
    @State private var showsProjects = false
    @Binding var page: ResultsPage
    @State private var lastStatisticsGroup: StatisticsGroup?
    private var statisticsVisible: Bool { showsStatistics && detailPath.isEmpty }

    private struct StatisticsGroup: Hashable {
        let project: String
        let id: String?
    }
    @State private var showsGroups = false
    @State private var solvesToDelete: Set<Solve.ID> = []
    @State private var showsMoveGroups = false
    @Binding var isSelecting: Bool
    let usesSideNavigation: Bool
    let isReviewContextActive: () -> Bool
    let contentInsets: LandscapeContentInsets?
    let showsStatistics: Bool
    let onChartViewed: (ResultsChartMode) -> Void
    @State private var selectedSolveIDs: Set<Solve.ID> = []
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var usesTopNavigation: Bool { isPad && horizontalSizeClass == .regular }
    // Put part of the row inset outside the List so row actions clear the rail.
    private var listRailInset: CGFloat { contentInsets == nil ? 0 : 12 }
    private var resultRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: LandscapeContentInsets.contentMargin,
                   bottom: 0, trailing: LandscapeContentInsets.contentMargin - listRailInset)
    }
    private var results: [Solve] {
        model.groupSolves.sorted(by: Solve.newestFirst)
    }

    private var canRequestReview: Bool {
        guard isReviewContextActive(), scenePhase == .active, page == .solves, !didRequestAppStoreReview,
              !isSelecting, detailPath.isEmpty, !showsMoveGroups, !showsProjects, !showsGroups,
              model.error == nil, !model.groupSolves.isEmpty else { return false }
#if DEBUG
        if ProcessInfo.processInfo.environment["CUBEGIN_UI_TEST_SESSION"] != nil { return false }
#endif
        return ResultsReviewEligibility.qualifies(model.solves)
    }

    var body: some View {
        let groupSolves = model.groupSolves
        let showsPageContent = page == .statistics || !groupSolves.isEmpty
        let availableKinds = SolveAverage.allCases.filter { $0.count <= groupSolves.count }
        let selectedKind = averageKind.flatMap { availableKinds.contains($0) ? $0 : nil }
        NavigationStack(path: $detailPath) {
            VStack(spacing: 0) {
                if showsPageContent {
                    pageContent(selectedKind: selectedKind, availableKinds: availableKinds)
                        .pinnedScrollHeader {
                            VStack(spacing: 0) {
                                resultsHeader
                                if page == .solves && !isSelecting && !availableKinds.isEmpty {
                                    resultTypePicker(availableKinds, selected: selectedKind)
                                }
                            }
                        }
                } else {
                    resultsHeader
                    VStack(spacing: 12) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 36, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(language.text("暂无成绩", "No results yet"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.leading, contentInsets?.containerLeading ?? 0)
            .padding(.trailing, contentInsets?.containerTrailing ?? 0)
            .appBackground()
            .navigationDestination(for: Solve.ID.self) { id in
                SolveDetailsView(model: model, solveID: id)
            }
            .navigationDestination(for: AverageDestination.self) { destination in
                averageDetails(destination)
            }
            .toolbar(usesSideNavigation || isSelecting ? .hidden : .automatic, for: .tabBar)
            .safeAreaPadding(.bottom, isSelecting ? 72 : 0)
            .sheet(isPresented: $showsMoveGroups) {
                MoveSolvesSheet(model: model, ids: selectedSolveIDs, usesCenteredPresentation: usesTopNavigation) {
                    endSelection()
                }
            }
            .onChange(of: model.currentGroup?.id) { _, _ in
                averageKind = nil
                endSelection()
            }
            .onChange(of: page) { _, _ in
                endSelection()
            }
            .onChange(of: statisticsVisible) { _, visible in
                if !visible { lastStatisticsGroup = nil }
            }
            .toolbar(isPad ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPad {
                    if !usesTopNavigation {
                        ToolbarItem(placement: .topBarLeading) {
                            HStack(spacing: 0) { projectPicker }
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                selectionControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
        .task(id: canRequestReview) {
            guard canRequestReview else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
            } catch {
                return
            }
            guard canRequestReview else { return }
            didRequestAppStoreReview = true
            requestReview()
        }
    }

    private var resultsHeader: some View {
        VStack(spacing: 0) {
            if usesTopNavigation {
                HStack(spacing: 12) {
                    if isSelecting {
                        selectAllButton.frame(maxWidth: .infinity, alignment: .leading)
                        groupPicker.frame(maxWidth: .infinity)
                    } else {
                        groupPicker.frame(maxWidth: .infinity, alignment: .leading)
                        projectPicker.frame(maxWidth: .infinity)
                    }
                    viewPicker.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(minHeight: 44)
            } else {
                if !isPad {
                    resultsProjectRow
                }
                resultsPickerRow
            }
        }
        .padding(.horizontal, LandscapeContentInsets.contentMargin)
        .padding(.top, 8 + (contentInsets?.headerTopOffset ?? 0))
        .frame(maxWidth: usesTopNavigation ? .infinity : 880)
    }

    private var resultsProjectRow: some View {
        projectPicker
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
    }

    private var resultsPickerRow: some View {
        HStack {
            groupPicker
            Spacer(minLength: 12)
            viewPicker
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private var projectPicker: some View {
        Group {
            if isSelecting {
                selectAllButton
            } else {
                EventPicker(model: model, isPresented: $showsProjects, large: usesTopNavigation)
                    .disabled(model.busy || model.started != nil)
            }
        }
    }
    private var viewPicker: some View {
        Menu {
            Picker(language.text("视图", "View"), selection: $page) {
                ForEach(ResultsPage.allCases) { item in
                    Text(item.title(language)).tag(item)
                }
            }
        } label: {
            pickerLabel(page.title(language))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(language.text("视图", "View"))
        .accessibilityValue(page.title(language))
        .accessibilityIdentifier("results.view")
        .disabled(isSelecting)
    }

    private var groupPicker: some View {
        Button {
            showsGroups = true
        } label: {
            pickerLabel(model.currentGroup.map(\.displayName) ?? "Default")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .disabled(model.started != nil)
        .disabled(isSelecting)
        .accessibilityLabel(language.text("分组", "Group"))
        .accessibilityValue(model.currentGroup.map(\.displayName) ?? "")
        .sheet(isPresented: $showsGroups) {
            GroupManager(model: model, usesCenteredPresentation: usesTopNavigation,
                         recordsGroupSwitch: page == .solves)
        }
    }

    private func pickerLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .frame(minHeight: 24)
    }

    @ViewBuilder private func pageContent(selectedKind: SolveAverage?, availableKinds: [SolveAverage]) -> some View {
        switch (page, selectedKind) {
        case (.solves, .some(let kind)):
            averagesView(kind: kind, availableKinds: availableKinds)
        case (.solves, nil):
            let orderedResults = results
            let extremes = orderedResults.enumerated().reduce(into: ResultExtremes(includesDNF: includesDNFInWorst)) { extremes, entry in
                extremes.record(entry.element.resultSeconds, at: entry.offset)
            }
            List(Array(orderedResults.enumerated()), id: \.element.id) { index, solve in
                let highlight = resultHighlight(at: index, best: extremes.best, worst: extremes.worst)
                Group {
                    if isSelecting {
                        Button {
                            if !selectedSolveIDs.insert(solve.id).inserted {
                                selectedSolveIDs.remove(solve.id)
                            }
                        } label: {
                            solveRowLabel(solve, number: orderedResults.count - index, total: orderedResults.count, highlight: highlight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedSolveIDs.contains(solve.id) ? .isSelected : [])
                    } else {
                        NavigationLink(value: solve.id) {
                            solveRowLabel(solve, number: orderedResults.count - index, total: orderedResults.count, highlight: highlight)
                        }
                        .accessibilityAction(named: Text(language.text("多选", "Select multiple"))) {
                            selectedSolveIDs = [solve.id]
                            isSelecting = true
                        }
                    }
                }
                .listRowInsets(resultRowInsets)
                .listRowBackground(selectedSolveIDs.contains(solve.id) ? Color.accentColor.opacity(0.06) : Color.clear)
                .accessibilityIdentifier("solve-row-\(orderedResults.count - index)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isSelecting {
                        Button {
                            solvesToDelete = [solve.id]
                        } label: {
                            Image(uiImage: GroupSwipeIcons.standaloneDelete)
                        }
                        .accessibilityLabel(language.text("删除", "Delete"))
                        .tint(.clear)
                        .disabled(model.started != nil)
                    }
                }
            }
            .listStyle(.plain)
            .padding(.trailing, listRailInset)
            .background {
                SolveRangeSelection(ids: orderedResults.map(\.id), selectedIDs: selectedSolveIDs,
                    enabled: model.started == nil) { ids in
                    selectedSolveIDs = ids
                    isSelecting = true
                }
            }
            .alert(solvesToDelete.count == 1
                ? language.text("确定删除这条成绩吗？", "Delete this solve?")
                : language.text("删除选中的 \(solvesToDelete.count) 条成绩？", "Delete \(solvesToDelete.count) selected solves?"), isPresented: Binding(
                get: { !solvesToDelete.isEmpty },
                set: { if !$0 { solvesToDelete = [] } }
            ), presenting: solvesToDelete) { ids in
                Button(language.text("取消", "Cancel"), role: .cancel) {}
                Button(language.text("删除", "Delete"), role: .destructive) {
                    withAnimation {
                        if model.deleteSolves(ids) { endSelection() }
                    }
                }
            } message: { _ in
                Text(language.text("删除后，成绩无法恢复。", "Deleted solves cannot be recovered."))
            }
        case (.statistics, _):
            let group = StatisticsGroup(project: model.event, id: model.currentGroup?.id)
            let solves = results
            ResultsOverview(solves: solves, contentInsets: contentInsets,
                            tracksChartVisibility: showsStatistics, onChartViewed: onChartViewed,
                            isVisible: statisticsVisible) { start in
                guard lastStatisticsGroup != group else { return }
                let trigger: TimerPerformanceMetric.StatisticsTrigger = lastStatisticsGroup == nil ? .open : .groupChange
                lastStatisticsGroup = group
                AppTelemetry.record(.statisticsReady(trigger: trigger, solveCount: solves.count), since: start)
            }
            .id(group)
        }
    }

    private struct HorizontalScrollOverflow: OptionSet {
        let rawValue: Int

        static let leading = Self(rawValue: 1 << 0)
        static let trailing = Self(rawValue: 1 << 1)
    }

    private func resultTypePicker(_ availableKinds: [SolveAverage], selected: SolveAverage?) -> some View {
        let options: [SolveAverage?] = [nil] + availableKinds.map(Optional.some)
        return ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        CapsuleSegmentButton(option?.title ?? language.text("单次", "Single"), isSelected: option == selected) {
                            averageKind = option
                        }
                        .accessibilityIdentifier("results.average-type.\(option?.title ?? "single")")
                        .id(option)
                    }
                }
            }
            .onScrollGeometryChange(for: HorizontalScrollOverflow.self) { geometry in
                let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                let scrollableWidth = geometry.contentSize.width + geometry.contentInsets.leading
                    + geometry.contentInsets.trailing - geometry.containerSize.width
                var overflow: HorizontalScrollOverflow = []
                if scrollableWidth > 1 {
                    if offset > 1 { overflow.insert(.leading) }
                    if scrollableWidth - offset > 1 { overflow.insert(.trailing) }
                }
                return overflow
            } action: { _, overflow in
                resultTypeOverflow = overflow
            }
            .mask {
                HStack(spacing: 0) {
                    if resultTypeOverflow.contains(.leading) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                    Rectangle()
                    if resultTypeOverflow.contains(.trailing) {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                }
            }
            .accessibilityLabel(language.text("成绩类型", "Result type"))
            .accessibilityIdentifier("results.average-types")
            .onChange(of: selected, initial: true) { _, selected in
                scroll.scrollTo(selected, anchor: .center)
            }
        }
        .frame(height: 44)
        .padding(.leading, resultRowInsets.leading)
        .padding(.trailing, resultRowInsets.trailing + listRailInset)
        .padding(.vertical, 4)
    }

    private func averagesView(kind: SolveAverage, availableKinds: [SolveAverage]) -> some View {
        let orderedResults = results
        let input = AverageHighlightInput(kind: kind, times: orderedResults.map(\.resultSeconds), includesDNF: includesDNFInWorst)
        let extremes = averageHighlights?.input == input ? averageHighlights?.extremes : nil
        return List(orderedResults.indices, id: \.self) { index in
            let number = orderedResults.count - index
            Group {
                if number >= kind.count {
                    let window = orderedResults[index..<(index + kind.count)]
                    NavigationLink(value: AverageDestination(kind: kind, newestSolveID: orderedResults[index].id)) {
                        averageRowLabel(
                            number: number,
                            total: orderedResults.count,
                            summary: kind.summarize(window),
                            highlight: resultHighlight(at: index, best: extremes?.best, worst: extremes?.worst)
                        )
                    }
                } else {
                    averageRowLabel(number: number, total: orderedResults.count, summary: nil)
                }
            }
            .listRowInsets(resultRowInsets)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("average-row-\(index)")
        }
        .listStyle(.plain)
        .padding(.trailing, listRailInset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { swipe in
                let distance = swipe.translation.width
                guard abs(distance) >= 48,
                      abs(distance) > 1.5 * abs(swipe.translation.height),
                      let index = availableKinds.firstIndex(of: kind) else { return }
                let next = index + (distance < 0 ? 1 : -1)
                if next == -1 {
                    averageKind = nil
                } else if availableKinds.indices.contains(next) {
                    averageKind = availableKinds[next]
                }
            }
        )
        .id(kind)
        .task(id: input) {
            let extremes = await kind.rollingExtremes(input.times, includesDNF: input.includesDNF)
            guard !Task.isCancelled else { return }
            averageHighlights = (input, extremes)
        }
    }

    private func averageRowLabel(number: Int, total: Int, summary: SolveAverage.Summary?, highlight: (label: String, color: Color)? = nil) -> some View {
        HStack(spacing: 12) {
            solveNumberLabel(number, total: total)
            Text(summary.map(averageScoreText) ?? "N/A")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(highlight?.color ?? (summary?.mean == nil ? .secondary : .primary))
                .accessibilityValue(highlight?.label ?? "")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let standardDeviation = summary?.standardDeviation {
                let deviation = TimerModel.format(standardDeviation)
                Text("σ \(deviation)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("标准差", "Standard deviation"))
                    .accessibilityValue(deviation)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func averageDetails(_ destination: AverageDestination) -> some View {
        let orderedResults = results
        let kind = destination.kind
        return Group {
            if let start = orderedResults.firstIndex(where: { $0.id == destination.newestSolveID }),
               orderedResults.count - start >= kind.count {
                let window = orderedResults[start..<(start + kind.count)]
                let summary = kind.summarize(window)
                let extremes = window.indices.reduce(into: ResultExtremes(includesDNF: includesDNFInWorst)) { extremes, index in
                    extremes.record(window[index].resultSeconds, at: index)
                }
                let bestSingle = extremes.best.map { window[$0].resultText } ?? "—"
                let worstSingle = summary.hasDNF ? "DNF" : (extremes.worst.map { window[$0].resultText } ?? "—")
                GeometryReader { geometry in
                    let spacing: CGFloat = 8
                    let availableWidth = geometry.size.width - 32
                    let columns = max(1, min(5, Int((availableWidth + spacing) / (averageSolveTileWidth + spacing))))
                    List {
                        Section {
                            LabeledContent(language.text("平均成绩", "Average"), value: averageScoreText(summary))
                            if let standardDeviation = summary.standardDeviation {
                                LabeledContent("σ", value: TimerModel.format(standardDeviation))
                                    .accessibilityLabel(language.text("标准差", "Standard deviation"))
                            }
                            LabeledContent(language.text("最快单次", "Fastest single"), value: bestSingle)
                            LabeledContent(language.text("最差单次", "Worst single"), value: worstSingle)
                        }
                        .monospacedDigit()

                        Section {
                            let rowCount = (window.count + columns - 1) / columns
                            ForEach(0..<rowCount, id: \.self) { row in
                                HStack(spacing: spacing) {
                                    ForEach(0..<columns, id: \.self) { column in
                                        let index = start + row * columns + column
                                        if index < window.endIndex {
                                            averageSolveTile(window[index], highlight: resultHighlight(at: index, best: extremes.best, worst: extremes.worst))
                                                .accessibilityIdentifier("average-solve-\(index - start)")
                                        } else {
                                            Color.clear
                                                .frame(maxWidth: .infinity)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(language.text("成绩列表", "Solves"))
                                .padding(.leading, 16)
                        }
                        // Inset the tiles inside the section mask to preserve their own corner radius.
                        .listSectionMargins(.horizontal, 0)
                    }
                }
            } else {
                ContentUnavailableView(language.text("此平均成绩已不可用", "This average is no longer available"), systemImage: "stopwatch")
            }
        }
        .appBackground()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func resultHighlight(at index: Int, best: Int?, worst: Int?) -> (label: String, color: Color)? {
        if index == best {
            return (language.text("最快", "Fastest"), resultBestColor(for: colorScheme))
        }
        if index == worst {
            return (language.text("最差", "Worst"), resultWorstColor(for: colorScheme))
        }
        return nil
    }

    private func averageSolveTile(_ solve: Solve, highlight: (label: String, color: Color)?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            detailPath.append(solve.id)
        } label: {
            Text(solve.resultText)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(solve.penalty == .dnf ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(highlight?.color.opacity(0.15) ?? .clear, in: shape)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityValue(highlight?.label ?? "")
    }

    private func solveNumberLabel(_ number: Int, total: Int) -> some View {
        Text("#\(total)")
            .hidden()
            .overlay(alignment: .leading) { Text("#\(number)") }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(minWidth: 36, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func solveRowLabel(_ solve: Solve, number: Int, total: Int, highlight: (label: String, color: Color)?) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedSolveIDs.contains(solve.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedSolveIDs.contains(solve.id) ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            solveNumberLabel(number, total: total)
            Text(solve.resultText)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(highlight?.color ?? (solve.penalty == .dnf ? .secondary : .primary))
                .accessibilityValue(highlight?.label ?? "")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(SolveDateLabel.text(for: solve.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var selectAllButton: some View {
        let allIDs = Set(results.map(\.id))
        let allSelected = selectedSolveIDs == allIDs
        return Button(allSelected ? language.text("取消全选", "Deselect all") : language.text("全选", "Select all")) {
            selectedSolveIDs = allSelected ? [] : allIDs
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var selectionControls: some View {
        HStack(spacing: 12) {
            Text(language.text("已选 \(selectedSolveIDs.count) 条", "\(selectedSolveIDs.count) selected"))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("solves.selection-count")
            Spacer(minLength: 0)
            Button {
                showsMoveGroups = true
            } label: {
                Image(systemName: "folder").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(selectedSolveIDs.isEmpty || model.started != nil)
            .accessibilityLabel(language.text("移动所选成绩", "Move selected solves"))
            Button {
                solvesToDelete = selectedSolveIDs
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(selectedSolveIDs.isEmpty ? Color.secondary : Color.red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selectedSolveIDs.isEmpty || model.started != nil)
            .accessibilityLabel(language.text("删除所选成绩", "Delete selected solves"))
            Button {
                endSelection()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("取消", "Cancel"))
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(maxWidth: 420, minHeight: 56)
        .glassEffect(.regular, in: .capsule)
    }

    private func endSelection() {
        showsMoveGroups = false
        isSelecting = false
        selectedSolveIDs = []
        solvesToDelete = []
    }

    private func timeText(_ time: Double?) -> String { time.map(TimerModel.format) ?? "—" }
    private func averageScoreText(_ summary: SolveAverage.Summary) -> String {
        summary.mean.map(TimerModel.format) ?? "DNF"
    }
}

func resultBestColor(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(uiColor: .systemGreen) : Color(red: 0.10, green: 0.45, blue: 0.24)
}

private func resultWorstColor(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(uiColor: .systemRed) : Color(red: 0.75, green: 0.14, blue: 0.18)
}

private struct ResultsOverview: View {
    let solves: [Solve]
    let contentInsets: LandscapeContentInsets?
    let tracksChartVisibility: Bool
    let onChartViewed: (ResultsChartMode) -> Void
    let isVisible: Bool
    let onReady: (AppTelemetry.PerformanceMeasurement?) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var dailyColumnWidth = 74.0
    @State private var bestAverages: (times: [Double?], scores: [SolveAverage: String])?
    private var language: AppLanguage { locale.appLanguage }

    private struct ReadinessInput: Equatable {
        let times: [Double?]
        let isVisible: Bool
    }

    var body: some View {
        let times = solves.map(\.resultSeconds)
        let valid = times.compactMap { $0 }
        let mean = valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        let singles = times.enumerated().reduce(into: ResultExtremes(includesDNF: false)) { extrema, entry in
            extrema.record(entry.element, at: entry.offset)
        }
        let availableKinds = SolveAverage.allCases.filter { solves.count >= $0.count }
        let bestScores = bestAverages?.times == times ? bestAverages?.scores : nil

        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    metric(language.text("有效 / 总次数", "Valid / Total"), value: "\(valid.count) / \(solves.count)")
                    metric(language.text("总平均", "Overall mean"), value: mean.map(TimerModel.format) ?? "—")
                    metric(language.text("单次最快", "Fastest single"), value: singles.best.map { solves[$0].resultText } ?? "—", color: resultBestColor(for: colorScheme))
                    metric(language.text("单次最慢", "Slowest single"), value: singles.worst.map { solves[$0].resultText } ?? "—", color: resultWorstColor(for: colorScheme))
                }
                .padding(.vertical, 10)
            }

            if !availableKinds.isEmpty {
                Section {
                    Grid(alignment: .trailing, horizontalSpacing: 7, verticalSpacing: 7) {
                        GridRow {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 1)
                                .accessibilityHidden(true)
                            Text(language.text("当前", "Current"))
                            Text("/")
                            Text(language.text("最佳", "Best"))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)

                        ForEach(availableKinds, id: \.self) { kind in
                            let current = averageText(kind, window: solves.prefix(kind.count))
                            comparisonRow(kind.title, current: current, best: bestScores?[kind] ?? "…")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if !solves.isEmpty {
                Section {
                    ResultsCharts(solves: solves, tracksVisibility: tracksChartVisibility, onViewed: onChartViewed)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                let days = recentDays()
                StatisticsCardSection(title: language.text("练习量", "Practice volume")) {
                    Group {
                        if days.isEmpty {
                            Text(language.text("暂无记录", "No activity yet"))
                                .foregroundStyle(.secondary)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                ForEach((1...min(4, days.count)).reversed(), id: \.self) { columns in
                                    dailyGrid(days, columns: columns)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.leading, contentInsets?.formLeadingMargin, for: .scrollContent)
        .contentMargins(.trailing, contentInsets?.formTrailingMargin, for: .scrollContent)
        .listSectionSpacing(12)
        .task(id: ReadinessInput(times: times, isVisible: isVisible)) {
            guard isVisible, !Task.isCancelled else { return }
            let start = AppTelemetry.performanceStart()
            if bestAverages?.times == times {
                onReady(start)
                return
            }
            var scores: [SolveAverage: String] = [:]
            for kind in availableKinds {
                let extrema = await kind.rollingExtremes(times, includesDNF: false)
                guard !Task.isCancelled else { return }
                scores[kind] = extrema.best.map { start in
                    averageText(kind, window: solves[start..<(start + kind.count)])
                } ?? "DNF"
            }
            guard !Task.isCancelled else { return }
            bestAverages = (times, scores)
            onReady(start)
        }
    }

    private func averageText(_ kind: SolveAverage, window: ArraySlice<Solve>) -> String {
        kind.summarize(window).mean.map(TimerModel.format) ?? "DNF"
    }

    private func metric(_ title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .foregroundStyle(value == "—" ? .secondary : color)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func comparisonRow(_ title: String, current: String, best: String) -> some View {
        GridRow {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(current)
            Text("/")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(best)
                .foregroundStyle(best == "DNF" || best == "…" ? Color.secondary : resultBestColor(for: colorScheme))
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(language.text("当前 \(current)，最佳 \(best)", "Current \(current), best \(best)"))
    }

    private func dailyGrid(_ days: [(date: Date, count: Int)], columns: Int) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: days.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(days[start..<min(start + columns, days.count)], id: \.date) { day in
                        VStack(spacing: 4) {
                            Text(dayLabel(day.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            let count = day.count.formatted(.number.locale(locale))
                            Text(count)
                                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel(language.text("\(count) 次", day.count == 1 ? "\(count) solve" : "\(count) solves"))
                        }
                        .frame(minWidth: columns == 1 ? 0 : dailyColumnWidth, maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func recentDays() -> [(date: Date, count: Int)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let counts = solves.reduce(into: [Date: Int]()) { counts, solve in
            counts[calendar.startOfDay(for: solve.date), default: 0] += 1
        }
        return counts.keys.sorted(by: >).prefix(8).map { ($0, counts[$0, default: 0]) }
    }
}

private struct SolveDetailsView: View {
    @Bindable var model: TimerModel
    let solveID: Solve.ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var confirmsDelete = false
    @State private var svg: String?
    @State private var diagramError: String?
    private var language: AppLanguage { locale.appLanguage }
    private var solve: Solve? { model.solves.first { $0.id == solveID } }

    var body: some View {
        Form {
            if let solve {
                Section {
                    LabeledContent(language.text("成绩", "Time"), value: solve.resultText)
                        .monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(language.text("成绩", "Time"))
                        .accessibilityValue(solve.resultText)
                        .accessibilityIdentifier("solve-detail.time")
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        penaltyButton(language.text("无惩罚", "No penalty"), penalty: nil, solve: solve)
                        penaltyButton("+2", penalty: .plusTwo, solve: solve)
                        penaltyButton("DNF", penalty: .dnf, solve: solve)
                    }
                    .disabled(model.started != nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
                Section {
                    LabeledContent(language.text("项目", "Event"), value: ScrambleCatalog.title(solve.event, in: language))
                    groupPicker(solve)
                    LabeledContent(language.text("日期", "Date"), value: solve.date.formatted(.dateTime.year().month().day().hour().minute().second().locale(locale)))
                }
                Section {
                    Text(solve.scramble)
                        .accessibilityIdentifier("solve-detail.scramble")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    ZStack {
                        if let svg {
                            SVGView(svg: svg, nextSVG: nil, alignment: .center)
                                .accessibilityLabel(language.text("本次成绩的打乱图", "Scramble diagram for this solve"))
                                .accessibilityIdentifier("solve-detail.diagram")
                        } else if let diagramError {
                            Text(diagramError).font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                }
            }
        }
        .appBackground()
        .navigationTitle(language.text("成绩详情", "Solve details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmsDelete = true
                } label: {
                    Image(uiImage: NavigationIcons.solveDetailDelete)
                        .foregroundStyle(.red)
                }
                .disabled(model.started != nil || solve == nil)
                .accessibilityLabel(language.text("删除这条成绩", "Delete this solve"))
            }
        }
        .alert(language.text("确定删除这条成绩吗？", "Delete this solve?"), isPresented: $confirmsDelete) {
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("删除", "Delete"), role: .destructive) {
                if model.deleteSolve(solveID) { dismiss() }
            }
        } message: {
            Text(language.text("删除后，成绩无法恢复。", "Deleted solves cannot be recovered."))
        }
        .task(id: solveID) {
            guard let solve else { return }
            do {
                let diagram = try await Engine.diagram(event: solve.event, algorithm: solve.scramble)
                guard !Task.isCancelled else { return }
                svg = diagram
            } catch {
                guard !Task.isCancelled else { return }
                if !(error is CancellationError) { AppTelemetry.record(.loadDiagram, .engineFailed, impact: .degraded) }
                diagramError = language.text("打乱图加载失败", "Could not load scramble diagram")
            }
        }
    }

    private func penaltyButton(_ title: String, penalty: SolvePenalty?, solve: Solve) -> some View {
        let isSelected = solve.penalty == penalty
        return Button {
            if !isSelected { model.setPenalty(penalty, for: solve.id) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.8))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 36)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .opacity(solve.allowsPenaltyChange || isSelected ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("solve-detail.\(penalty == nil ? "no-penalty" : title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(!solve.allowsPenaltyChange)
    }

    @ViewBuilder private func groupPicker(_ solve: Solve) -> some View {
        let groupID = solve.groupID ?? SolveGroup.initialID(for: solve.event)
        let current = model.groups.first { $0.id == groupID }
        let alternatives = model.groups.filter { $0.event == solve.event && $0.id != groupID }
        if alternatives.isEmpty {
            LabeledContent(language.text("分组", "Group"), value: current?.displayName ?? "Default")
                .accessibilityIdentifier("solve-detail.group")
        } else {
            Menu {
                ForEach(alternatives) { group in
                    Button(group.displayName) { model.moveSolve(solve.id, toGroup: group.id) }
                }
            } label: {
                LabeledContent(language.text("分组", "Group")) {
                    HStack(spacing: 6) {
                        Text(current?.displayName ?? "Default")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .menuIndicator(.hidden)
            .tint(.primary)
            .disabled(model.started != nil)
            .accessibilityLabel(language.text("分组", "Group"))
            .accessibilityValue(current?.displayName ?? "Default")
            .accessibilityIdentifier("solve-detail.group")
        }
    }
}

// Keep the colored circle compact inside the native swipe control hit region.
@MainActor private enum GroupSwipeIcons {
    static let standaloneDelete = icon("trash", color: .systemRed, horizontalOffset: 0)
    static let edit = icon("pencil", color: .systemBlue, horizontalOffset: 0)
    static let pairedEdit = icon("pencil", color: .systemBlue, horizontalOffset: 8)
    static let delete = icon("trash", color: .systemRed, horizontalOffset: -8)

    private static func icon(_ name: String, color: UIColor, horizontalOffset: CGFloat) -> UIImage {
        let side: CGFloat = 32
        let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            if let symbol {
                symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(
                    x: (side - symbol.size.width) / 2,
                    y: (side - symbol.size.height) / 2,
                    width: symbol.size.width, height: symbol.size.height
                ))
            }
        }.withRenderingMode(.alwaysOriginal)
            // Move paired circles inward inside their native action hit regions.
            .withAlignmentRectInsets(UIEdgeInsets(top: 0, left: -horizontalOffset, bottom: 0, right: horizontalOffset))
    }
}

private struct GroupManager: View {
    @Bindable var model: TimerModel
    let usesCenteredPresentation: Bool
    let recordsGroupSwitch: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var groupToDelete: SolveGroup?
    @State private var editingGroupID: String?
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        if usesCenteredPresentation {
            panel.presentationSizing(.form)
        } else {
            panel.presentationDetents([.medium, .large])
        }
    }

    private var panel: some View {
        NavigationStack {
            List {
                ForEach(model.eventGroups) { group in
                    groupRow(group)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Trailing actions display in reverse declaration order.
                            if !group.isDefault {
                                Button(role: .destructive) {
                                    groupToDelete = group
                                } label: {
                                    Image(uiImage: GroupSwipeIcons.delete).renderingMode(.original)
                                }
                                .accessibilityLabel(language.text("删除", "Delete"))
                                .tint(.clear)
                            }
                            Button {
                                editingGroupID = group.id
                            } label: {
                                Image(uiImage: group.isDefault ? GroupSwipeIcons.edit : GroupSwipeIcons.pairedEdit)
                                    .renderingMode(.original)
                            }
                            .accessibilityLabel(language.text("编辑", "Edit"))
                            .tint(.clear)
                        }
                }
                .onMove { source, destination in
                    var ordered = model.eventGroups
                    ordered.move(fromOffsets: source, toOffset: destination)
                    _ = model.reorderGroups(ordered.map(\.id))
                }
            }
            .listStyle(.plain)
            .appBackground()
            .navigationTitle(language.text("分组", "Groups"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $editingGroupID) { id in
                if let group = model.eventGroups.first(where: { $0.id == id }) {
                    GroupEditor(model: model, group: group)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GroupEditor(model: model, group: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(language.text("新建分组", "New group"))
                }
            }
            .alert(language.text("删除分组及其中的成绩？", "Delete group and its results?"), isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil } }
            ), presenting: groupToDelete) { group in
                Button(language.text("取消", "Cancel"), role: .cancel) {}
                Button(language.text("永久删除", "Delete permanently"), role: .destructive) {
                    _ = model.deleteGroup(group.id)
                }
            } message: { group in
                let count = model.solves.filter {
                    $0.event == group.event && ($0.groupID ?? SolveGroup.initialID(for: $0.event)) == group.id
                }.count
                Text(language.text(
                    "「\(group.displayName)」及其中的 \(count) 条成绩将被永久删除。删除后，成绩无法恢复。",
                    "“\(group.displayName)” and its \(count) results will be permanently deleted. These results cannot be recovered."
                ))
            }
            .overlay(alignment: .bottom) {
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding()
                }
            }
        }
    }

    private func groupRow(_ group: SolveGroup) -> some View {
        let isSelected = group.id == model.currentGroup?.id
        let name = Text(group.displayName)
            .font(.body.weight(isSelected ? .medium : .regular))
            .foregroundColor(.primary)
        let starBaselineOffset = (
            AppTypography.preferredFont(for: .body).capHeight
            - UIFont.systemFont(ofSize: 11, weight: .medium).capHeight
        ) / 2
        let star = Text(Image(systemName: "star.fill"))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.yellow)
            .baselineOffset(starBaselineOffset)
        let title = group.isDefault ? Text("\(name) \(star)") : name
        return HStack(spacing: 8) {
            Button {
                let previousGroup = model.currentGroup?.id
                model.selectGroup(group.id)
                if recordsGroupSwitch, model.currentGroup?.id == group.id, previousGroup != group.id {
                    AppTelemetry.record(.featureUsed(.groupSwitched))
                }
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    title
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(group.displayName)
            .accessibilityValue(group.isDefault ? language.text("默认分组", "Default group") : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            ListReorderHandle()
                .frame(width: 32, height: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(language.text("调整分组顺序", "Reorder group"))
                .accessibilityValue(group.displayName)
                .accessibilityAction(named: language.text("上移", "Move up")) { move(group, offset: -1) }
                .accessibilityAction(named: language.text("下移", "Move down")) { move(group, offset: 1) }
        }
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        }
        .accessibilityIdentifier("group.row." + group.id)
    }

    private func move(_ group: SolveGroup, offset: Int) {
        guard let index = model.eventGroups.firstIndex(where: { $0.id == group.id }) else { return }
        let target = index + offset
        guard model.eventGroups.indices.contains(target) else { return }
        _ = model.moveGroup(group.id, to: model.eventGroups[target].id)
    }
}

// Start the list's native interactive movement only from this handle.
struct ListReorderHandle: UIViewRepresentable {
    func makeUIView(context: Context) -> HandleView { HandleView() }
    func updateUIView(_ view: HandleView, context: Context) {}

    final class HandleView: UIView {
        private let icon = UIImageView(image: UIImage(
            systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)
        ))
        private weak var movingCollection: UICollectionView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            icon.contentMode = .center
            icon.tintColor = .tertiaryLabel
            addSubview(icon)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(reorder(_:)))
            press.minimumPressDuration = 0.35
            addGestureRecognizer(press)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            icon.frame = bounds
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Disable dragging the whole row; the handle initiates movement directly.
            collectionContext()?.collection.dragInteractionEnabled = false
        }

        private func collectionContext() -> (collection: UICollectionView, cell: UICollectionViewCell)? {
            var ancestor = superview
            var cell: UICollectionViewCell?
            while let view = ancestor {
                if let listCell = view as? UICollectionViewCell { cell = listCell }
                if let collection = view as? UICollectionView, let cell { return (collection, cell) }
                ancestor = view.superview
            }
            return nil
        }

        @objc private func reorder(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began:
                guard let context = collectionContext(),
                      let index = context.collection.indexPath(for: context.cell) else { return }
                context.collection.dragInteractionEnabled = false
                if context.collection.beginInteractiveMovementForItem(at: index) {
                    movingCollection = context.collection
                }
            case .changed:
                movingCollection?.updateInteractiveMovementTargetPosition(press.location(in: movingCollection))
            case .ended:
                movingCollection?.endInteractiveMovement()
                movingCollection = nil
            case .cancelled, .failed:
                movingCollection?.cancelInteractiveMovement()
                movingCollection = nil
            default:
                break
            }
        }
    }
}

private struct MoveSolvesSheet: View {
    @Bindable var model: TimerModel
    let ids: Set<Solve.ID>
    let usesCenteredPresentation: Bool
    var onMoved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private var destinations: [SolveGroup] {
        model.eventGroups.filter { $0.id != model.currentGroup?.id }
    }

    var body: some View {
        if usesCenteredPresentation {
            panel.presentationSizing(.form)
        } else {
            panel.presentationDetents([.medium, .large])
        }
    }

    private var panel: some View {
        NavigationStack {
            List {
                ForEach(destinations) { group in
                    Button {
                        if model.moveSolves(ids, toGroup: group.id) {
                            dismiss()
                            onMoved()
                        }
                    } label: {
                        HStack {
                            Text(group.displayName)
                                .lineLimit(1).truncationMode(.tail)
                            if group.isDefault {
                                Image(systemName: "star.fill")
                                    .font(.caption2).foregroundStyle(.yellow)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .appBackground()
            .overlay {
                if destinations.isEmpty {
                    Text(language.text("暂无其他分组", "No other groups"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle(language.text("移动到分组", "Move to group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        GroupEditor(model: model, group: nil, selectNewGroup: false)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(language.text("新建分组", "New group"))
                }
            }
        }
    }
}

private struct GroupEditor: View {
    let model: TimerModel
    let group: SolveGroup?
    var selectNewGroup = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var isDefault = false
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    TextField(language.text("分组名称", "Group name"), text: $name)
                        .submitLabel(.done)
                    Text("\(name.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(SolveGroup.maximumNameLength)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(SolveGroup.isValidName(name) || name.isEmpty ? Color.secondary : Color.red)
                        .fixedSize()
                }
            }
            Section {
                Toggle(language.text("默认分组", "Default group"), isOn: $isDefault)
                    .disabled(group?.isDefault == true)
            } footer: {
                Text(language.text("切换到这个项目时，自动使用默认分组。", "Switching to this event selects its default group."))
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .appBackground()
        .navigationTitle(group == nil ? language.text("新建分组", "New group") : language.text("编辑分组", "Edit group"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.text("保存", "Save")) {
                    if model.saveGroup(id: group?.id, name: name, isDefault: isDefault, selectNewGroup: selectNewGroup) { dismiss() }
                }
                .disabled(!SolveGroup.isValidName(name))
            }
        }
        .onAppear {
            name = group?.displayName ?? ""
            isDefault = group?.isDefault ?? false
        }
    }
}

// Leave room inside grouped list rows for the card shadow.
let cardShadowInset: CGFloat = 4

func cardSurface<S: Shape>(_ shape: S) -> some View {
    shape
        .fill(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
}

extension ContainerValues {
    @Entry fileprivate var hasCardRowLayout = false
}

extension View {
    fileprivate func cardRowLayout() -> some View {
        frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 20)
    }
}

@MainActor
func cardRowButton<Label: View>(
    role: ButtonRole? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> Label
) -> some View {
    Button(role: role, action: action) {
        label()
            .cardRowLayout()
            .contentShape(Rectangle())
    }
    .containerValue(\.hasCardRowLayout, true)
}

struct CardSection<Content: View, Header: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    var body: some View {
        Section {
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.containerValues.hasCardRowLayout {
                            row
                        } else {
                            row.cardRowLayout()
                        }
                        if row.id != rows.last?.id {
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .background { cardSurface(RoundedRectangle(cornerRadius: 24)) }
                .padding(cardShadowInset)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            header
        } footer: {
            footer
        }
    }
}

extension CardSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension CardSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension CardSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

@MainActor
private func settingsLinkLabel(_ title: String) -> some View {
    HStack {
        Text(title)
        Spacer()
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

@MainActor
private func trackedSetting<Value: Equatable>(
    _ binding: Binding<Value>, as analyticsValue: @escaping (Value) -> FeatureSettingValue
) -> Binding<Value> {
    Binding(get: { binding.wrappedValue }, set: { newValue in
        let previous = binding.wrappedValue
        guard newValue != previous else { return }
        binding.wrappedValue = newValue
        let from = analyticsValue(previous)
        let to = analyticsValue(binding.wrappedValue)
        guard from != to else { return }
        AppTelemetry.record(.featureUsed(.settingChanged(from: from, to: to)))
    })
}

private struct SettingsView: View {
    static var opensFeedbackForQA: Bool {
#if DEBUG
        Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin.dev"
            && ProcessInfo.processInfo.arguments.contains("-cubegin-show-feedback")
#else
        false
#endif
    }

    static var opensAboutForQA: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-cubegin-show-about")
            || (Bundle.main.bundleIdentifier == "io.github.deweyou.cubegin.dev"
                && arguments.contains("-cubegin-show-device-id"))
#else
        return false
#endif
    }

    private static var deviceIDToastDuration: Duration {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CUBEGIN_UI_TEST_SESSION"] != nil,
           environment["CUBEGIN_UI_TEST_EXTENDED_DEVICE_ID_TOAST"] == "1" {
            return .seconds(12)
        }
#endif
        return .seconds(2)
    }

    let model: TimerModel
    let contentInsets: LandscapeContentInsets?
    let isSelected: Bool
    private enum Page: Hashable { case gestures, imports, clearResults, sync, feedback, privacy, changelog }
    @State private var path: [Page] = opensFeedbackForQA ? [.feedback] : []
    @State private var versionTapCount = 0
    @State private var startDelayBeforeEditing: Int?
    @State private var isCheckingForUpdate = false
    @State private var updateOutcome: AppStoreUpdate.Outcome?
    @Environment(\.openURL) private var openURL
    @State private var copiedDeviceIDAt: ContinuousClock.Instant?
    @AppStorage(AppLanguage.preferenceKey) private var languageOverride = AppLanguage.systemPreference
    @AppStorage(AppTheme.preferenceKey) private var theme = AppTheme.system
    @AppStorage(TimerModel.keepTimerScreenOnKey) private var keepsTimerScreenOn = true
    @AppStorage(TimerModel.inspectionKey) private var usesInspection = false
    @AppStorage(TimerModel.trainingInspectionKey) private var usesTrainingInspection = false
    @AppStorage(TimerModel.inspectionVoiceKey) private var inspectionVoice = InspectionVoice.off
    @AppStorage(TimerModel.startDelayKey) private var startDelayTenths = TimerModel.defaultStartDelayTenths
    @AppStorage(TimerModel.displayKey) private var timerDisplay = TimerDisplay.realtime
    @AppStorage(TimerModel.entryMethodKey) private var entryMethod = SolveEntryMethod.timer
    @AppStorage(TimerModel.hapticsKey) private var usesTimerHaptics = true
    @AppStorage(ResultExtremes.includeDNFPreferenceKey) private var includesDNFInWorst = ResultExtremes.defaultIncludesDNF
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    private var syncedLanguage: Binding<String> {
        trackedSetting(SettingsSync.binding($languageOverride, key: AppLanguage.preferenceKey) { $0 }) {
            .language(AppLanguage(rawValue: $0))
        }
    }

    @ViewBuilder private var timerSettings: some View {
        Toggle(language.text("计时触感", "Timer haptics"), isOn: trackedSetting(
            SettingsSync.binding($usesTimerHaptics, key: TimerModel.hapticsKey) { $0 }, as: FeatureSettingValue.haptics
        ))
            .accessibilityIdentifier("settings.timer.haptics")
        HStack(spacing: 8) {
            let title = language.text("启动延迟", "Start delay")
            let value = (Double(startDelayTenths) / 10).formatted(.number.precision(.fractionLength(1))) + " s"
            Text(title)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { Double(startDelayTenths) },
                set: { syncedStartDelay.wrappedValue = Int($0.rounded()) }
            ), in: 0...20, onEditingChanged: { isEditing in
                if isEditing {
                    startDelayBeforeEditing = startDelayTenths
                } else if let previous = startDelayBeforeEditing {
                    startDelayBeforeEditing = nil
                    recordStartDelayChange(from: previous)
                }
            }) {
                Text(title)
            }
            .labelsHidden()
            .frame(idealWidth: 112, maxWidth: 112)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAdjustableAction { direction in
                let previous = startDelayTenths
                switch direction {
                case .increment: syncedStartDelay.wrappedValue = min(20, startDelayTenths + 1)
                case .decrement: syncedStartDelay.wrappedValue = max(0, startDelayTenths - 1)
                @unknown default: break
                }
                recordStartDelayChange(from: previous)
            }
            .accessibilityIdentifier("settings.startDelay")
        }
        Toggle(language.text("WCA 观察", "WCA inspection"), isOn: trackedSetting(
            SettingsSync.binding($usesInspection, key: TimerModel.inspectionKey) { $0 }, as: FeatureSettingValue.inspection
        ))
            .accessibilityIdentifier("settings.inspection.enabled")
        if usesInspection {
            Toggle(language.text("训练中启用观察", "Inspection in training"), isOn: trackedSetting(
                SettingsSync.binding($usesTrainingInspection, key: TimerModel.trainingInspectionKey) { $0 }, as: FeatureSettingValue.trainingInspection
            ))
            Picker(language.text("观察报时", "Inspection voice"), selection: trackedSetting(
                SettingsSync.binding($inspectionVoice, key: TimerModel.inspectionVoiceKey) { $0.rawValue }, as: FeatureSettingValue.inspectionVoice
            )) {
                ForEach(InspectionVoice.allCases, id: \.self) { voice in
                    Text(voice.title(in: language)).tag(voice)
                }
            }
            .accessibilityIdentifier("settings.inspection.voice")
        }
    }

    private var syncedStartDelay: Binding<Int> {
        SettingsSync.binding($startDelayTenths, key: TimerModel.startDelayKey) { $0 }
    }

    private func recordStartDelayChange(from previous: Int) {
        guard previous != startDelayTenths else { return }
        AppTelemetry.record(.featureUsed(.settingChanged(from: .startDelay(previous), to: .startDelay(startDelayTenths))))
    }

    private func tapVersion() {
        versionTapCount += 1
        guard versionTapCount == 5 else { return }
        versionTapCount = 0
        UIPasteboard.general.string = AppTelemetry.supportIdentifiers
        copiedDeviceIDAt = ContinuousClock.now
        AccessibilityNotification.Announcement(language.text("已复制设备 ID", "Device ID copied")).post()
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                CardSection(language.text("通用", "General")) {
                    Picker(language.text("主题", "Theme"), selection: trackedSetting(
                        SettingsSync.binding($theme, key: AppTheme.preferenceKey) { $0.rawValue }, as: FeatureSettingValue.theme
                    )) {
                        ForEach(AppTheme.allCases) { option in
                            Text(option.title(in: language)).tag(option)
                        }
                    }
                    .accessibilityIdentifier("settings.theme")
                    Picker(language.text("语言", "Language"), selection: Binding(
                        get: { AppLanguage(rawValue: languageOverride)?.rawValue ?? AppLanguage.systemPreference },
                        set: { syncedLanguage.wrappedValue = $0 }
                    )) {
                        Text(language.text("跟随系统", "System")).tag(AppLanguage.systemPreference)
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.name).tag(option.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings.language")
                    if model.supportsCloudSync {
                        cardRowButton {
                            path.append(.sync)
                        } label: {
                            settingsLinkLabel(language.text("同步", "Sync"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.general.sync")
                    }
                }
                CardSection(language.text("计时", "Timer")) {
                    Toggle(language.text("计时页保持常亮", "Keep timer screen on"), isOn: trackedSetting(
                        SettingsSync.binding($keepsTimerScreenOn, key: TimerModel.keepTimerScreenOnKey) { $0 }, as: FeatureSettingValue.keepScreenOn
                    ))
                        .accessibilityIdentifier("settings.timer.keepScreenOn")
                    Picker(language.text("成绩产生方式", "Result entry"), selection: trackedSetting(
                        SettingsSync.binding($entryMethod, key: TimerModel.entryMethodKey) { $0.rawValue }, as: FeatureSettingValue.entryMethod
                    )) {
                        ForEach(SolveEntryMethod.allCases, id: \.self) { method in
                            Text(method.title(in: language)).tag(method)
                        }
                    }
                    .accessibilityIdentifier("settings.timer.entryMethod")
                    if entryMethod == .timer {
                        Picker(language.text("计时器的时间显示", "Timer display"), selection: trackedSetting(
                            SettingsSync.binding($timerDisplay, key: TimerModel.displayKey) { $0.rawValue }, as: FeatureSettingValue.display
                        )) {
                            ForEach(TimerDisplay.allCases, id: \.self) { display in
                                Text(display.title(in: language)).tag(display)
                            }
                        }
                        .accessibilityIdentifier("settings.timer.display")
                        timerSettings
                    }
                    cardRowButton {
                        path.append(.gestures)
                    } label: {
                        settingsLinkLabel(language.text("手势", "Gestures"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.timer.gestures")
                }
                CardSection(language.text("成绩", "Results")) {
                    cardRowButton {
                        path.append(.imports)
                    } label: {
                        settingsLinkLabel(language.text("导入", "Import"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.results.import")
                    cardRowButton {
                        path.append(.clearResults)
                    } label: {
                        settingsLinkLabel(language.text("清空成绩", "Clear results"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.results.clear")
                    Toggle(language.text("最差成绩包含 DNF", "Include DNF as worst"), isOn: trackedSetting(
                        SettingsSync.binding($includesDNFInWorst, key: ResultExtremes.includeDNFPreferenceKey) { $0 }, as: FeatureSettingValue.includeDNF
                    ))
                        .accessibilityIdentifier("settings.results.includeDNFInWorst")
                }
                CardSection(language.text("关于", "About")) {
                    cardRowButton {
                        isCheckingForUpdate = true
                    } label: {
                        HStack {
                            Text(isCheckingForUpdate
                                ? language.text("正在检查更新…", "Checking for updates…")
                                : language.text("检查更新", "Check for Updates"))
                            Spacer()
                            if isCheckingForUpdate {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingForUpdate)
                    .accessibilityIdentifier("settings.about.checkForUpdates")
                    cardRowButton {
                        tapVersion()
                    } label: {
                        LabeledContent(language.text("版本", "Version"), value: AppStoreUpdate.installedVersion ?? language.text("开发版", "Development build"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about.version")
                    cardRowButton {
                        path.append(.changelog)
                    } label: {
                        settingsLinkLabel(language.text("更新记录", "Changelog"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about.changelog")
                    cardRowButton {
                        path.append(.privacy)
                    } label: {
                        settingsLinkLabel(language.text("隐私", "Privacy"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about.privacy")
                    cardRowButton {
                        path.append(.feedback)
                    } label: {
                        settingsLinkLabel(language.text("反馈与评价", "Feedback & Reviews"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about.feedback")
                }
            }
            .defaultScrollAnchor(Self.opensAboutForQA ? .bottom : nil, for: .initialOffset)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .gestures: TimerGestureSettingsView()
                case .imports: ResultsImportView(model: model)
                case .clearResults: ClearResultsView(model: model)
                case .sync: SyncSettingsView(model: model)
                case .feedback: FeedbackSettingsView()
                case .privacy: PrivacySettingsView()
                case .changelog: ChangelogView()
                }
            }
            .pinnedScrollHeader {
                Text(language.text("设置", "Settings"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.title")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, LandscapeContentInsets.contentMargin)
                    .padding(.top, 8 + (contentInsets?.headerTopOffset ?? 0))
            }
            .contentMargins(.leading, contentInsets?.formLeadingMargin, for: .scrollContent)
            .contentMargins(.trailing, contentInsets?.formTrailingMargin, for: .scrollContent)
            .padding(.leading, contentInsets?.containerLeading ?? 0)
            .padding(.trailing, contentInsets?.containerTrailing ?? 0)
            .appBackground()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if copiedDeviceIDAt != nil {
                    Label(language.text("已复制设备 ID", "Device ID copied"), systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.black, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.24)))
                        .padding()
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("settings.deviceID.copied")
                }
            }
        }
        .task(id: copiedDeviceIDAt) {
            guard copiedDeviceIDAt != nil else { return }
            do {
                try await Task.sleep(for: Self.deviceIDToastDuration)
                copiedDeviceIDAt = nil
            } catch {}
        }
        .task(id: isCheckingForUpdate) {
            guard isCheckingForUpdate else { return }
            let outcome = (try? await AppStoreUpdate.check()) ?? .failed
            guard !Task.isCancelled else { return }
            updateOutcome = outcome
            isCheckingForUpdate = false
        }
        .alert(updateTitle, isPresented: Binding(
            get: { updateOutcome != nil },
            set: { if !$0 { updateOutcome = nil } }
        ), presenting: updateOutcome) { outcome in
            if case .available(let release) = outcome {
                Button(language.text("稍后", "Later"), role: .cancel) {}
                Button(language.text("前往 App Store", "Open App Store")) {
                    openURL(release.trackViewUrl)
                }
            } else {
                Button(language.text("好", "OK"), role: .cancel) {}
            }
        } message: { outcome in
            Text(verbatim: updateMessage(outcome))
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                isCheckingForUpdate = false
                updateOutcome = nil
                path.removeAll()
                versionTapCount = 0
                copiedDeviceIDAt = nil
            }
        }
    }

    private var updateTitle: String {
        switch updateOutcome {
        case .available(let release):
            language.text("Cubegin \(release.version) 已发布", "Cubegin \(release.version) Is Available")
        case .upToDate:
            language.text("当前已是最新版", "You’re Up to Date")
        case .requiresNewerOS:
            language.text("新版需要更新系统", "New Version Requires a System Update")
        default:
            language.text("检查更新", "Check for Updates")
        }
    }

    private func updateMessage(_ outcome: AppStoreUpdate.Outcome) -> String {
        let installed = AppStoreUpdate.installedVersion ?? ""
        let version = language.text("当前版本 \(installed)", "Installed version \(installed)")
        switch outcome {
        case .upToDate:
            return version
        case .available(let release):
            let notes = release.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !notes.isEmpty else { return version }
            let summary = notes.count > 240 ? String(notes.prefix(240)) + "…" : notes
            return version + "\n\n" + summary
        case .requiresNewerOS(let release):
            return language.text(
                "Cubegin \(release.version) 需要 iOS 或 iPadOS \(release.minimumOsVersion) 或更高版本。",
                "Cubegin \(release.version) requires iOS or iPadOS \(release.minimumOsVersion) or later."
            )
        case .unavailable:
            return language.text(
                "当前商店地区暂未查到 Cubegin 的正式版本。",
                "Cubegin is not currently listed in this App Store region."
            )
        case .testFlight:
            return language.text("请在 TestFlight 查看测试版更新。", "Check TestFlight for beta updates.")
        case .failed:
            return language.text("暂时无法检查更新，请稍后重试。", "Couldn’t check for updates. Try again later.")
        }
    }
}

private struct ChangelogView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    private var entries: [String] {
        let resource = language == .chinese ? "CHANGELOG_ZH" : "CHANGELOG"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // The first block contains the repository title and language link.
        return markdown.components(separatedBy: "\n## ").dropFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 32) {
                if entries.isEmpty {
                    Text(language.text("暂时无法读取更新记录。", "Couldn’t load the changelog."))
                }
                ForEach(entries, id: \.self) { entry in
                    let lines = entry.split(separator: "\n")
                    if let version = lines.first {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(version)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                                let isBullet = line.hasPrefix("- ")
                                let content = isBullet ? String(line.dropFirst(2)) : String(line)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    if isBullet {
                                        Text("•").accessibilityHidden(true)
                                    }
                                    Text((try? AttributedString(markdown: content)) ?? AttributedString(content))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .appBackground()
        .navigationTitle(language.text("更新记录", "Changelog"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct SyncSettingsView: View {
    let model: TimerModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private let statusLineHeight = ceil(AppTypography.preferredFont(for: .footnote).lineHeight)
    private let refreshTargetSize: CGFloat = 44

    var body: some View {
        Form {
            CardSection {
                iCloudSyncToggle
            } footer: {
                if model.cloudSyncEnabled, model.supportsResultsSync {
                    syncStatus
                }
            }
        }
        .appBackground()
        .navigationTitle(language.text("同步", "Sync"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var iCloudSyncToggle: some View {
        let title = language.text("iCloud 同步", "iCloud Sync")
        let description = model.supportsResultsSync
            ? language.text("跨设备同步成绩和设置。", "Sync results and settings across devices.")
            : language.text("跨设备同步常用设置。", "Sync preferences across devices.")
        return Toggle(isOn: trackedSetting(Binding(
            get: { model.cloudSyncEnabled },
            set: { model.setCloudSyncEnabled($0) }
        ), as: FeatureSettingValue.iCloudSync)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
        }
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityIdentifier("settings.sync.icloudSync")
    }

    private var syncStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            switch model.cloudSyncStatus {
            case .idle, .synced:
                let time = model.lastSuccessfulCloudSync.map {
                    $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
                }
                Text(time.map { language.text("上次同步：\($0)", "Last synced: \($0)") }
                     ?? language.text("等待同步", "Waiting to sync"))
                    .accessibilityIdentifier("settings.sync.lastCloudSync")
                Spacer(minLength: 0)
                syncButton(language.text("刷新", "Refresh"), isRetry: false)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: statusLineHeight, height: statusLineHeight)
                    .accessibilityHidden(true)
                Text(language.text("正在同步…", "Syncing…"))
                    .accessibilityIdentifier("settings.sync.inProgress")
            case .uploading(let completed, let total):
                let count = completed.formatted(.number.locale(locale))
                let changeCount = total.formatted(.number.locale(locale))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(language.text("正在上传到 iCloud…", "Uploading to iCloud…"))
                            .accessibilityIdentifier("settings.sync.uploading")
                        Spacer(minLength: 0)
                        Text("\(count)/\(changeCount)")
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("settings.sync.uploadProgress")
                    }
                    ProgressView(value: Double(completed), total: Double(total))
                        .accessibilityHidden(true)
                }
            case .failed(let failure):
                Text(cloudSyncMessage(failure))
                    .foregroundStyle(failure == .network ? Color.secondary : .red)
                    .accessibilityIdentifier("settings.sync.cloudSyncError")
                Spacer(minLength: 0)
                syncButton(language.text("重试", "Retry"), isRetry: true)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, cardShadowInset)
        // The switch has an additional trailing inset inside its card row.
        .padding(.trailing, cardShadowInset)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, minHeight: refreshTargetSize, alignment: .topLeading)
    }

    private func syncButton(_ title: String, isRetry: Bool) -> some View {
        Color.clear
            .frame(width: refreshTargetSize, height: statusLineHeight)
            .overlay(alignment: .trailing) {
                Button {
                    model.requestCloudSync()
                    SettingsSync.refresh()
                    AppTelemetry.record(.featureUsed(.syncRequested(isRetry: isRetry)))
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.accentColor)
                        .frame(height: statusLineHeight)
                        // Compensate for the symbol's trailing side bearing.
                        .offset(x: 3)
                        .frame(width: refreshTargetSize, height: refreshTargetSize, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.sync.refresh")
            }
    }

    private func cloudSyncMessage(_ failure: CloudSyncFailure) -> String {
        switch failure {
        case .noAccount: language.text("请先在系统设置中登录 iCloud。", "Sign in to iCloud in Settings first.")
        case .restricted: language.text("此设备限制了 iCloud 访问，请检查系统设置。", "iCloud access is restricted on this device. Check Settings.")
        case .accountUnavailable: language.text("暂时无法访问 iCloud 账号，请稍后重试。", "Your iCloud account is temporarily unavailable. Try again later.")
        case .accountChanged: language.text("iCloud 账号已变更，请切回之前同步用的账号。", "Switch back to the iCloud account previously used for sync.")
        case .authentication: language.text("iCloud 验证失败，请检查账号状态。", "iCloud couldn’t verify your account. Check Settings.")
        case .network: language.text("网络连接异常", "Network connection unavailable")
        case .storageFull: language.text("iCloud 储存空间不足，请腾出空间后重试。", "Free up iCloud storage, then try again.")
        case .serviceUnavailable: language.text("iCloud 暂时无法同步，请稍后重试。", "iCloud is temporarily unavailable. Try again later.")
        case .localStorage: language.text("无法读取或保存本机成绩。", "Couldn’t read or save local results.")
        case .unknown: language.text("同步失败，请稍后重试。", "Sync failed. Try again later.")
        }
    }
}

private struct PrivacySettingsView: View {
    @AppStorage(AppTelemetry.sharingChoiceKey, store: AppTelemetry.sharingDefaults)
    private var sharingChoice = AppTelemetry.SharingChoice.undecided
    @State private var showsPrivacyPolicy = false
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    private static let policyURL = URL(string: "cubegin://privacy-policy")

    private func policyText(includeDescription: Bool) -> some View {
        let description = includeDescription ? language.text(
            "开启后会发送崩溃报告、操作失败、性能耗时和功能使用情况，帮助我们修复问题、改进计时体验。",
            "When enabled, Cubegin sends crash reports, failed operations, performance timings, and feature usage to help improve the timer. "
        ) : ""
        var link = AttributedString(language.text("查看隐私政策", "View privacy policy"))
        link.link = Self.policyURL
        return Text(AttributedString(description) + link)
            .tint(Color(uiColor: .link))
            .environment(\.openURL, OpenURLAction { url in
                guard url == Self.policyURL else { return .discarded }
                showsPrivacyPolicy = true
                return .handled
            })
            .accessibilityIdentifier("settings.privacyPolicy")
    }

    var body: some View {
        Form {
            if AppTelemetry.showsSharingPreference {
                CardSection {
                    Toggle(language.text("帮助改进 Cubegin", "Help improve Cubegin"), isOn: Binding(
                        get: { sharingChoice == .allowed },
                        set: { AppTelemetry.chooseSharing($0 ? .allowed : .declined) }
                    ))
                    .accessibilityIdentifier("settings.telemetry.sharing")
                } footer: {
                    policyText(includeDescription: true)
                }
            } else {
                policyText(includeDescription: false).listRowBackground(Color.clear)
            }
        }
        .appBackground()
        .navigationTitle(language.text("隐私", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showsPrivacyPolicy) { PrivacyPolicyView() }
    }
}

private struct TimerGestureSettingsView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        Form {
            CardSection {
                ForEach(TimerSwipeDirection.allCases, id: \.self) { direction in
                    TimerSwipePicker(direction: direction)
                }
            }
        }
        .appBackground()
        .navigationTitle(language.text("手势", "Gestures"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct TimerSwipePicker: View {
    let direction: TimerSwipeDirection
    @AppStorage private var action: TimerSwipeAction
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    init(direction: TimerSwipeDirection) {
        self.direction = direction
        _action = AppStorage(wrappedValue: direction.defaultAction, direction.preferenceKey)
    }

    var body: some View {
        Picker(direction.title(in: language), selection: trackedSetting(SettingsSync.binding($action, key: direction.preferenceKey) { $0.rawValue }) {
            .swipe(direction, $0)
        }) {
            ForEach(TimerSwipeAction.allCases, id: \.self) { option in
                Text(option.title(in: language)).tag(option)
            }
        }
        .accessibilityIdentifier("settings.timer.swipe.\(direction.rawValue)")
    }
}

private struct ClearResultsView: View {
    private struct Request: Identifiable {
        let id = UUID()
        let solveIDs: Set<Solve.ID>
        let title: String
        let scope: ClearResultsScope
    }

    let model: TimerModel
    @Environment(\.locale) private var locale
    @State private var selection: Set<String> = []
    @State private var request: Request?
    @State private var deletedCount: Int?
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        let byGroup = model.solveIDsByGroup
        let groups = model.groups.filter { byGroup[$0.id] != nil }
        let selectedIDs = selection.reduce(into: Set<Solve.ID>()) { ids, groupID in
            if let results = byGroup[groupID] { ids.formUnion(results) }
        }

        Form {
            if model.solves.isEmpty {
                CardSection {
                    Text(language.text("暂无成绩", "No results yet"))
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(language.text("选择分组", "Select groups")) {
                    ForEach(groups) { group in
                        cardRowButton {
                            if !selection.insert(group.id).inserted { selection.remove(group.id) }
                        } label: {
                            HStack {
                                Image(systemName: selection.contains(group.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(group.name.isEmpty ? language.text("默认分组", "Default group") : group.name)
                                    Text(ScrambleCatalog.title(group.event, in: language))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text((byGroup[group.id]?.count ?? 0).formatted())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(group.id) ? .isSelected : [])
                        .accessibilityIdentifier("settings.clear.group.\(group.id)")
                    }
                }
            }
            if !selection.isEmpty {
                CardSection {
                    cardRowButton(role: .destructive) {
                        guard request == nil, !selectedIDs.isEmpty else { return }
                        request = Request(solveIDs: selectedIDs,
                                          title: language.text("清空所选分组？", "Clear selected groups?"),
                                          scope: .selectedGroups)
                    } label: {
                        Text(language.text("清空所选分组（\(selectedIDs.count.formatted()) 条）", "Clear selected groups (\(selectedIDs.count.formatted()))"))
                    }
                    .disabled(selectedIDs.isEmpty || model.started != nil)
                    .accessibilityIdentifier("settings.results.clearSelected")
                }
            } else {
                CardSection {
                    cardRowButton(role: .destructive) {
                        guard request == nil, selection.isEmpty else { return }
                        request = Request(solveIDs: Set(model.solves.map(\.id)),
                                          title: language.text("清空所有成绩？", "Clear all results?"),
                                          scope: .all)
                    } label: {
                        Text(language.text("清空所有成绩", "Clear all results"))
                    }
                    .disabled(model.solves.isEmpty || model.started != nil)
                    .accessibilityIdentifier("settings.results.clearAll")
                }
            }
        }
        .navigationTitle(language.text("清空成绩", "Clear results"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .allowsHitTesting(request == nil)
        .accessibilityHidden(request != nil)
        .overlay {
            if let pending = request {
                ClearResultsConfirmation(
                    title: pending.title,
                    count: pending.solveIDs.count,
                    language: language,
                    onCancel: { request = nil }
                ) {
                    guard model.deleteSolves(pending.solveIDs, operation: .clearResults) else { return false }
                    AppTelemetry.record(.featureUsed(.resultsCleared(pending.scope)))
                    selection.removeAll()
                    deletedCount = pending.solveIDs.count
                    request = nil
                    return true
                }
                .id(pending.id)
            }
        }
        .overlay(alignment: .bottom) {
            if let count = deletedCount, request == nil {
                let message = language.text("已删除 \(count.formatted()) 条成绩。",
                                            count == 1 ? "Deleted 1 result." : "Deleted \(count.formatted()) results.")
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.24)))
                    .padding()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("settings.clear.notice")
                    .onAppear { AccessibilityNotification.Announcement(message).post() }
            }
        }
        .task(id: deletedCount) {
            guard deletedCount != nil else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                deletedCount = nil
            } catch {}
        }
    }
}

private struct ClearResultsConfirmation: View {
    let title: String
    let count: Int
    let language: AppLanguage
    let onCancel: () -> Void
    let onConfirm: () -> Bool
    @State private var seconds = 5
    @State private var failed = false
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Text(language.text("将永久删除 \(count.formatted()) 条成绩。",
                                       count == 1 ? "This will permanently delete 1 result."
                                           : "This will permanently delete \(count.formatted()) results."))
                        .font(.subheadline)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions }
                    VStack(spacing: 8) { actions }
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAction(.escape, onCancel)
            .onAppear { titleFocused = true }
        }
        .alert(language.text("无法清空成绩", "Couldn’t clear results"), isPresented: $failed) {
            Button(language.text("好", "OK"), role: .cancel) {}
        }
        .task {
            do {
                while seconds > 0 {
                    try await Task.sleep(for: .seconds(1))
                    seconds -= 1
                }
            } catch {}
        }
    }

    @ViewBuilder private var actions: some View {
        Button(role: .cancel, action: onCancel) {
            Text(language.text("取消", "Cancel"))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            guard seconds == 0 else { return }
            failed = !onConfirm()
        } label: {
            Text(seconds > 0
                 ? language.text("清空（\(seconds) 秒）", "Clear (\(seconds)s)")
                 : language.text("清空", "Clear"))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(seconds > 0)
        .accessibilityIdentifier("settings.results.confirmClearAll")
    }
}

// Use Gregorian calendar years (yyyy), independently of the UI language and week-year.
enum SolveDateLabel {
    static func text(for date: Date, now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: "%02d:%02d", parts.hour!, parts.minute!)
        }
        if parts.year == calendar.component(.year, from: now) {
            return String(format: "%02d-%02d", parts.month!, parts.day!)
        }
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

// Observe the native List's collection view without replacing its scrolling or reuse.
private struct SolveRangeSelection: UIViewRepresentable {
    var ids: [Solve.ID]
    var selectedIDs: Set<Solve.ID>
    var enabled: Bool
    var onSelection: (Set<Solve.ID>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.onAttach = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.attach(near: view)
        }
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.anchor != nil,
           (!enabled || ids != context.coordinator.gestureIDs) {
            context.coordinator.finish()
        }
        DispatchQueue.main.async { view.onAttach?() }
    }

    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) {
        view.onAttach = nil
        coordinator.detach()
    }

    final class Probe: UIView {
        var onAttach: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { DispatchQueue.main.async { self.onAttach?() } }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SolveRangeSelection
        weak var collection: UICollectionView?
        var press: UILongPressGestureRecognizer?
        var displayLink: CADisplayLink?
        var anchor: Int?
        var gestureIDs: [Solve.ID] = []
        var originalSelection: Set<Solve.ID> = []
        var fingerInWindow = CGPoint.zero
        var lastSelection: Set<Solve.ID> = []
        var lastIndex: Int?

        init(_ parent: SolveRangeSelection) { self.parent = parent }

        func attach(near view: UIView) {
            guard view.window != nil, collection == nil else { return }
            var ancestor = view.superview
            while let container = ancestor {
                if let list = findCollection(in: container) {
                    collection = list
                    let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
                    gesture.minimumPressDuration = 0.4
                    gesture.delegate = self
                    gesture.cancelsTouchesInView = true
                    list.addGestureRecognizer(gesture)
                    press = gesture
                    return
                }
                ancestor = container.superview
            }
        }

        private func findCollection(in view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView { return list }
            for child in view.subviews {
                if let list = findCollection(in: child) { return list }
            }
            return nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.enabled, let collection,
                  let path = collection.indexPathForItem(at: gestureRecognizer.location(in: collection)) else { return false }
            return path.section == 0 && parent.ids.indices.contains(path.item)
        }

        @objc private func handle(_ gesture: UILongPressGestureRecognizer) {
            guard let collection else { return }
            switch gesture.state {
            case .began:
                guard let path = collection.indexPathForItem(at: gesture.location(in: collection)),
                      parent.ids.indices.contains(path.item) else { return }
                gestureIDs = parent.ids
                originalSelection = parent.selectedIDs
                lastSelection = parent.selectedIDs
                anchor = path.item
                fingerInWindow = gesture.location(in: collection.window)
                select(through: path.item)
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            case .changed:
                fingerInWindow = gesture.location(in: collection.window)
                updateRange()
            case .ended:
                fingerInWindow = gesture.location(in: collection.window)
                updateRange()
                finish()
            case .cancelled, .failed:
                finish()
            default:
                break
            }
        }

        private func select(through index: Int) {
            guard let anchor, gestureIDs.indices.contains(index), lastIndex != index else { return }
            lastIndex = index
            let range = min(anchor, index)...max(anchor, index)
            let selection = originalSelection.union(gestureIDs[range])
            guard selection != lastSelection else { return }
            lastSelection = selection
            parent.onSelection(selection)
        }

        private func updateRange() {
            guard let collection, anchor != nil else { return }
            let point = collection.convert(fingerInWindow, from: collection.window)
            if let path = collection.indexPathForItem(at: point), path.section == 0 {
                select(through: path.item)
            } else {
                // At separators or just outside the viewport use the closest visible row.
                let nearest = collection.indexPathsForVisibleItems.filter { $0.section == 0 }.min {
                    let first = collection.layoutAttributesForItem(at: $0)?.frame.midY ?? .infinity
                    let second = collection.layoutAttributesForItem(at: $1)?.frame.midY ?? .infinity
                    return abs(first - point.y) < abs(second - point.y)
                }
                if let nearest { select(through: nearest.item) }
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let collection, anchor != nil else { return }
            let point = collection.convert(fingerInWindow, from: collection.window)
            let top = collection.bounds.minY + collection.adjustedContentInset.top
            let bottom = collection.bounds.maxY - collection.adjustedContentInset.bottom
            let edge: CGFloat = 48
            var velocity: CGFloat = 0
            if point.y < top + edge {
                velocity = -min(1, (top + edge - point.y) / edge) * 360
            } else if point.y > bottom - edge {
                velocity = min(1, (point.y - bottom + edge) / edge) * 360
            }
            if velocity != 0 {
                let minimum = -collection.adjustedContentInset.top
                let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
                let interval = min(0.05, link.targetTimestamp - link.timestamp)
                let y = min(maximum, max(minimum, collection.contentOffset.y + velocity * interval))
                collection.setContentOffset(CGPoint(x: collection.contentOffset.x, y: y), animated: false)
            }
            updateRange()
        }

        func finish() {
            displayLink?.invalidate()
            displayLink = nil
            anchor = nil
            lastIndex = nil
            gestureIDs = []
            originalSelection = []
        }

        func detach() {
            finish()
            if let press { collection?.removeGestureRecognizer(press) }
            press = nil
            collection = nil
        }
    }
}
