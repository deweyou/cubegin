import SwiftUI

struct AssistScramble: Identifiable {
    let event: String
    let groupID: String
    let algorithm: String
    let usesDuoModal: Bool

    var id: String { algorithm }
}

struct AssistPreferences {
    let event: String
    let groupID: String
    var defaults: UserDefaults = .standard

    private var prefix: String { "assist.\(event)/\(groupID)" }

    static func isPreferenceKey(_ key: String) -> Bool {
        key.hasPrefix("assist.") && (key.hasSuffix(".method") || isOrderKey(key))
    }

    static func isOrderKey(_ key: String) -> Bool { key.contains(".order.") }

    func selectedMethod(from methods: [AssistMethod]) -> AssistMethod? {
        let saved = defaults.string(forKey: prefix + ".method")
        return methods.first { $0.rawValue == saved } ?? methods.first
    }

    @discardableResult
    func saveMethod(_ method: AssistMethod) -> String {
        let key = prefix + ".method"
        defaults.set(method.rawValue, forKey: key)
        return key
    }

    func ordered(_ solutions: [AssistSolution], for method: AssistMethod) -> [AssistSolution] {
        guard !method.isStaged else { return solutions }
        let targets = defaults.stringArray(forKey: orderKey(for: method)) ?? []
        let ordered = targets.compactMap { target in solutions.first { $0.id == target } }
        let restored = Set(ordered.map(\.id))
        return ordered + solutions.filter { !restored.contains($0.id) }
    }

    @discardableResult
    func saveOrder(_ solutions: [AssistSolution], for method: AssistMethod) -> String {
        let key = orderKey(for: method)
        defaults.set(solutions.map(\.id), forKey: key)
        return key
    }

    private func orderKey(for method: AssistMethod) -> String {
        prefix + ".order." + method.rawValue
    }
}

struct AssistFormulaModal: View {
    let scramble: AssistScramble
    let onPreferencesChanged: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = 20
            let width = max(0, min(560, geometry.size.width - 2 * margin))
            let height = max(0, min(640, geometry.size.height - 2 * margin))
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                AssistFormulaView(scramble: scramble, onPreferencesChanged: onPreferencesChanged)
                    .frame(width: width, height: height)
                    .clipShape(.rect(cornerRadius: 28))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AssistFormulaView: View {
    let scramble: AssistScramble
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var metricFontSize = 10.0
    let methods: [AssistMethod]
    private let preferences: AssistPreferences
    private let onPreferencesChanged: (String) -> Void
    @State private var method: AssistMethod
    @State private var search: Search = .loading
    @State private var retryCount = 0
    @State private var viewedMethods: Set<AssistMethod> = []

    private enum Search {
        case loading
        case solutions([AssistSolution])
        case failed
    }

    init(scramble: AssistScramble, onPreferencesChanged: @escaping (String) -> Void) {
        self.scramble = scramble
        self.onPreferencesChanged = onPreferencesChanged
        let methods = AssistMethod.available(for: scramble.event)
        self.methods = methods
        let preferences = AssistPreferences(event: scramble.event, groupID: scramble.groupID)
        self.preferences = preferences
        _method = State(initialValue: preferences.selectedMethod(from: methods) ?? .cross)
    }

    private var language: AppLanguage { locale.appLanguage }

    private var canReorder: Bool {
        guard !method.isStaged, case .solutions(let solutions) = search else { return false }
        return solutions.count > 1
    }

    var body: some View {
        NavigationStack {
            List {
                methodSection
                solutionsSection
            }
            .navigationTitle(language.text("辅助公式", "Formula hints"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("完成", "Done")) { dismiss() }
                }
            }
        }
        .task(id: SearchRequest(method: method, retryCount: retryCount)) { [method] in
            await loadSolutions(method: method)
        }
    }

    private var methodSection: some View {
        Section {
            Picker(language.text("求解", "Solve"), selection: $method) {
                ForEach(methods) { method in
                    Text(method.title(in: language)).tag(method)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("assist.method")
            .onChange(of: method) { _, selection in
                onPreferencesChanged(preferences.saveMethod(selection))
                search = .loading
                AppTelemetry.record(.featureUsed(.assistMethodSelected(selection)))
            }
        }
    }

    private var solutionsSection: some View {
        Section(method.isStaged
                ? language.text("按顺序执行", "Follow in order")
                : "") {
            switch search {
            case .loading:
                ProgressView(language.text("正在求解…", "Finding solutions…"))
            case .solutions(let solutions):
                if solutions.isEmpty {
                    Text(language.text("没有找到解法。", "No solutions found."))
                        .foregroundStyle(.secondary)
                }
                ForEach(solutions) { solution in
                    solutionRow(solution)
                        .moveDisabled(!canReorder)
                }
                .onMove(perform: moveSolutions)
            case .failed:
                Text(language.text("无法生成提示，请重试或切换方法。", "Couldn’t find hints. Try again or switch methods."))
                    .foregroundStyle(.secondary)
                Button(language.text("重试", "Try again")) {
                    search = .loading
                    retryCount += 1
                }
            }
        }
    }

    private struct SearchRequest: Equatable {
        let method: AssistMethod
        let retryCount: Int
    }

    private func moveSolutions(from source: IndexSet, to destination: Int) {
        guard canReorder, case .solutions(var solutions) = search else { return }
        let previousOrder = solutions.map(\.id)
        solutions.move(fromOffsets: source, toOffset: destination)
        guard solutions.map(\.id) != previousOrder else { return }
        onPreferencesChanged(preferences.saveOrder(solutions, for: method))
        search = .solutions(solutions)
        AppTelemetry.record(.featureUsed(.assistReordered))
    }

    private func moveSolution(_ target: String, offset: Int) {
        guard case .solutions(let solutions) = search,
              let source = solutions.firstIndex(where: { $0.id == target }),
              solutions.indices.contains(source + offset) else { return }
        let destination = offset > 0 ? source + offset + 1 : source + offset
        moveSolutions(from: IndexSet(integer: source), to: destination)
    }

    private func loadSolutions(method: AssistMethod) async {
        do {
            let solutions = try await Engine.assistSolutions(
                event: scramble.event, method: method, algorithm: scramble.algorithm
            )
            try Task.checkCancellation()
            guard self.method == method else { return }
            search = .solutions(preferences.ordered(solutions, for: method))
            if !solutions.isEmpty, viewedMethods.insert(method).inserted {
                AppTelemetry.record(.featureUsed(.assistMethodViewed(method)))
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.method == method else { return }
            AppTelemetry.record(.loadAssist, error is DecodingError ? .decodeFailed : .engineFailed, impact: .degraded)
            search = .failed
        }
    }

    private func solutionRow(_ solution: AssistSolution) -> some View {
        let formula = [solution.setupRotation, solution.solution].filter { !$0.isEmpty }.joined(separator: " ")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(solution.targetLabel.isEmpty ? method.title(in: language) : solution.targetLabel)
                        .font(.subheadline.weight(.semibold))
                    if let metric = solution.metric, method != .shapeFTM, method != .shapeTwist {
                        Text("\(metric.ftm) FTM")
                            .font(.system(size: metricFontSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(colorScheme == .dark ? Color.indigo.mix(with: .white, by: 0.35) : Color.indigo)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }
                }
                Text(formula.isEmpty ? language.text("无需转动", "No moves needed") : formula)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canReorder {
                ListReorderHandle()
                    .frame(width: 32, height: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(language.text("调整解法顺序", "Reorder solution"))
                    .accessibilityValue(solution.targetLabel)
                    .accessibilityIdentifier("assist.reorder." + solution.id)
                    .accessibilityAction(named: language.text("上移", "Move up")) { moveSolution(solution.id, offset: -1) }
                    .accessibilityAction(named: language.text("下移", "Move down")) { moveSolution(solution.id, offset: 1) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assist.solution.\(solution.target)")
    }
}
