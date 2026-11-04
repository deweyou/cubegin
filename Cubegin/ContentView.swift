import SwiftUI
import WebKit

struct ContentView: View {
    @Bindable var model: TimerModel
    @State private var showsProjectList = false
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private let controlIconSize: CGFloat = 20
    private let controlRowHeight: CGFloat = 44
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // The native iPad TabView uses the top bar in regular-width layouts.
    private var usesTopNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationStack {
                    page(width: geometry.size.width)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
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
                page(width: geometry.size.width)
            }
        }
#if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--measure-picker") {
                measurePickerWidths()
            }
        }
#endif
    }
    private func page(width: CGFloat) -> some View {
            ScrollView {
                VStack(spacing: 28) {
                    if usesTopNavigation {
                        projectMenu
                            .frame(maxWidth: .infinity)
                            .disabled(model.busy || model.started != nil)
                    } else if UIDevice.current.userInterfaceIdiom != .pad {
                        HStack(spacing: 0) {
                            projectMenu
                            Spacer(minLength: 12)
                            trailingControls
                        }
                        .disabled(model.busy || model.started != nil)
                    }
                    VStack(spacing: 18) {
                        HStack {
                            Label(language.text("随机打乱", "Scramble"), systemImage: "shuffle").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(model.busy || model.started != nil).accessibilityLabel(language.text("重新生成打乱", "Generate a new scramble"))
                        }
                        if model.busy { ProgressView(language.text("计算中…", "Generating…")) }
                        Text(model.scramble?.algorithm ?? language.text("准备你的下一次挑战", "Ready for your next solve"))
                            .font(.system(.title3, design: .monospaced)).lineSpacing(7).frame(maxWidth: .infinity)
                            .textSelection(.enabled)
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    Button { model.toggle() } label: {
                        VStack(spacing: 14) {
                            TimelineView(.animation(minimumInterval: 0.03, paused: model.started == nil)) { _ in
                                let duration = model.started.map { $0.duration(to: .now) }
                                let seconds = duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? model.elapsed
                                Text(TimerModel.format(seconds)).font(.system(size: width > 600 ? 110 : 76, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            }
                            Text(model.started == nil ? language.text("轻触开始计时", "Tap to start") : language.text("轻触停止", "Tap to stop")).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.scramble == nil && model.started == nil)
                        .accessibilityLabel(model.started == nil ? language.text("开始计时", "Start timer") : language.text("停止计时", "Stop timer"))
                    HStack(spacing: 16) {
                        statistic(language.text("完成", "Solves"), "\(model.session.count)")
                        statistic(language.text("最佳", "Best"), model.session.map(\.seconds).min().map(TimerModel.format) ?? "—")
                        statistic(language.text("平均", "Average"), model.session.isEmpty ? "—" : TimerModel.format(model.session.map(\.seconds).reduce(0, +) / Double(model.session.count)))
                    }
                    if let svg = model.scramble?.svg {
                        SVGView(svg: svg).frame(height: 180).accessibilityLabel(language.text("当前打乱状态图", "Current scramble diagram"))
                    }
                    if let assistance = model.assistance { Text(assistance).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    if !model.session.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(language.text("最近成绩", "Recent solves")).font(.headline)
                            ForEach(model.session.prefix(20)) { solve in
                                HStack {
                                    Text(solve.date, style: .time).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(TimerModel.format(solve.seconds)).monospacedDigit().fontWeight(.medium)
                                }
                            }
                        }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 880).frame(maxWidth: .infinity)
            }
        .background {
            LinearGradient(colors: [Color.cyan.opacity(0.14), Color(.systemBackground), Color.indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
    }
    private var projectMenu: some View {
        projectButton(event: model.event, language: language, large: usesTopNavigation) {
            showsProjectList = true
        }
        .popover(isPresented: $showsProjectList, arrowEdge: .top) {
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
            .frame(width: 300, height: 400)
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

    private func projectButton(event: String, language: AppLanguage, large: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            projectMenuLabel(event: event, language: language, large: large)
        }
        .buttonStyle(.plain)
        .controlSize(large ? .regular : .small)
        .accessibilityLabel(language.text("打乱项目", "Event"))
        .accessibilityValue(ScrambleCatalog.title(event, in: language))
    }

    private func projectMenuLabel(event: String, language: AppLanguage, large: Bool) -> some View {
        let iconID = String(event.prefix { $0 != "." })
        return HStack(spacing: 6) {
            Image("Event-\(iconID)")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
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
        .frame(minWidth: 44, minHeight: controlRowHeight, alignment: .leading)
        .contentShape(Rectangle())
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
                 "compactPicker": width(projectButton(event: choice.id, language: language, large: false, action: {}), language: language),
                 "regularPicker": width(projectButton(event: choice.id, language: language, large: true, action: {}), language: language)] as [String: Any]
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

    private var trainingButton: some View {
        Button {
            model.mode = model.mode == .training ? .standard : .training
        } label: {
            Image(systemName: "dumbbell")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .foregroundStyle(model.mode == .training ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("训练模式", "Training"))
        .accessibilityValue(model.mode == .training ? language.text("已开启", "On") : language.text("已关闭", "Off"))
        .accessibilityAddTraits(model.mode == .training ? .isSelected : [])
        .accessibilityHint(language.text("切换标准打乱与训练打乱", "Switch between standard and training scrambles"))
        .frame(minHeight: controlRowHeight)
    }
    private func statistic(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit()) }
            .frame(maxWidth: .infinity).padding(.vertical, 18).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SVGView: UIViewRepresentable {
    let svg: String
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{margin:0;display:grid;place-items:center;height:100vh;background:transparent}svg{max-width:100%;max-height:100vh}</style>" + svg, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var svg = "" }
}
