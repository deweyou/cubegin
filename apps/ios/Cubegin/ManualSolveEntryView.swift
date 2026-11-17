import SwiftUI

struct ManualSolveTime {
    static let digitCount = 7
    static let maximumMilliseconds = 5_999_999

    let digits: String

    init(_ input: String) {
        digits = String(input.compactMap { digit -> String? in
            guard let value = digit.wholeNumberValue, (0...9).contains(value) else { return nil }
            return String(value)
        }.prefix(Self.digitCount).joined())
    }

    var displayedDigits: String {
        digits.padding(toLength: Self.digitCount, withPad: "0", startingAt: 0)
    }

    var milliseconds: Int? {
        guard digits.count >= 4, let value = Int(displayedDigits) else { return nil }
        let seconds = value / 1_000 % 100
        guard seconds < 60 else { return nil }
        return (value / 100_000 * 60 + seconds) * 1_000 + value % 1_000
    }
}

struct ManualSolveEntryView: View {
    let save: (Int?, SolvePenalty?) -> String?
    let close: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool
    @State private var digits = ""
    @State private var penalty: SolvePenalty?
    @State private var saveError: String?
    private var language: AppLanguage { locale.appLanguage }
    private var time: ManualSolveTime { ManualSolveTime(digits) }
    private var canSave: Bool {
        (penalty == .dnf && digits.isEmpty) || (time.milliseconds ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    timeInput
                    Text(language.text("从左到右输入分、秒、毫秒",
                                       "Enter minutes, seconds, and milliseconds from left to right."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        penaltyButton("+2", .plusTwo)
                        penaltyButton("DNF", .dnf)
                    }
                    if digits.count >= 4 && time.milliseconds == nil {
                        Text(language.text("秒位必须在 00 到 59 之间。", "Seconds must be between 00 and 59."))
                            .foregroundStyle(.red)
                    } else if penalty == .dnf {
                        Text("DNF")
                            .accessibilityIdentifier("manual-result.preview")
                    } else if penalty == .plusTwo, let milliseconds = time.milliseconds, milliseconds > 0 {
                        let adjusted = TimerModel.format(Double(milliseconds + 2_000) / 1_000)
                        Text(verbatim: adjusted + "+")
                            .accessibilityIdentifier("manual-result.preview")
                    }
                    if let saveError {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(language.text("录入成绩", "Enter result"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("取消", "Cancel"), action: closeEntry)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("保存", "Save")) {
                        saveError = save(time.milliseconds, penalty)
                        if saveError == nil { closeEntry() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task {
            if close != nil {
                // The nonanimated cover needs to be installed before requesting keyboard focus.
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            isFocused = true
        }
    }

    private func closeEntry() {
        if let close {
            close()
        } else {
            dismiss()
        }
    }

    private var timeInput: some View {
        let characters = Array(time.displayedDigits)
        let activeIndex = digits.count
        return HStack(spacing: 4) {
            ForEach(characters.indices, id: \.self) { index in
                if index == 2 { Text(":") }
                if index == 4 { Text(".") }
                let isActive = isFocused && index == activeIndex
                let cell = RoundedRectangle(cornerRadius: 8)
                Text(String(characters[index]))
                    .foregroundStyle(index < digits.count ? .primary : .secondary)
                    .frame(maxWidth: 40, minHeight: 44)
                    .background(.quaternary, in: cell)
                    .overlay { cell.strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2) }
            }
        }
        .font(.title2.monospacedDigit())
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .overlay {
            TextField("", text: Binding(
                get: { digits },
                set: { digits = ManualSolveTime($0).digits }
            ))
            .keyboardType(.numberPad)
            .foregroundStyle(.clear)
            .tint(.clear)
            .focused($isFocused)
            .accessibilityLabel(language.text("用时", "Time"))
            .accessibilityHint(language.text("从左到右输入分、秒、毫秒", "Enter minutes, seconds, and milliseconds from left to right."))
            .accessibilityIdentifier("manual-result.time")
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
    }

    private func penaltyButton(_ title: String, _ value: SolvePenalty) -> some View {
        Button {
            penalty = penalty == value ? nil : value
        } label: {
            Text(verbatim: title)
                .frame(minWidth: 48)
        }
        .buttonStyle(.bordered)
        .tint(penalty == value ? .accentColor : .secondary)
        .background(penalty == value ? Color.accentColor.opacity(0.16) : .clear, in: Capsule())
        .accessibilityAddTraits(penalty == value ? .isSelected : [])
    }
}
