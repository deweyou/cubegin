import SwiftUI

struct ManualSolveTime {
    static let digitCount = 7
    static let maximumMilliseconds = 5_999_999

    private(set) var digits: [Character?]

    init(_ input: String = "") {
        digits = Array(repeating: nil, count: Self.digitCount)
        insert(input, at: 0)
    }

    var displayedDigits: String { String(digits.map { $0 ?? "0" }) }

    var milliseconds: Int? {
        guard let value = Int(displayedDigits) else { return nil }
        let seconds = value / 1_000 % 100
        guard seconds < 60 else { return nil }
        return (value / 100_000 * 60 + seconds) * 1_000 + value % 1_000
    }

    @discardableResult
    mutating func insert(_ input: String, at position: Int) -> Int {
        var index = position
        for character in input {
            guard index < digits.count else { break }
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { continue }
            digits[index] = Character(String(value))
            index += 1
        }
        return index
    }

    mutating func clearDigit(at index: Int) {
        digits[index] = nil
    }
}

struct ManualSolveEntryView: View {
    let save: (Int?, SolvePenalty?) -> String?
    let close: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var time = ManualSolveTime()
    @State private var activeIndex = 0
    @State private var focusRequest = 0
    @State private var penalty: SolvePenalty?
    @State private var saveError: String?
    private var language: AppLanguage { locale.appLanguage }
    private var canSave: Bool {
        guard let milliseconds = time.milliseconds else { return false }
        return penalty == .dnf || milliseconds > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    timeInput
                    HStack {
                        penaltyButton("+2", .plusTwo)
                        penaltyButton("DNF", .dnf)
                    }
                    if time.milliseconds == nil {
                        Text(language.text("秒位必须在 00 到 59 之间。", "Seconds must be between 00 and 59."))
                            .foregroundStyle(.red)
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
    }

    private func closeEntry() {
        if let close {
            close()
        } else {
            dismiss()
        }
    }

    private var timeInput: some View {
        HStack(spacing: 4) {
            ForEach(time.digits.indices, id: \.self) { index in
                if index == 2 { Text(":").accessibilityHidden(true) }
                if index == 4 { Text(".").accessibilityHidden(true) }
                let digit = time.digits[index]
                let cell = RoundedRectangle(cornerRadius: 8)
                Button {
                    activeIndex = index
                    focusRequest += 1
                } label: {
                    Text(String(digit ?? "0"))
                        .foregroundStyle(digit == nil ? .secondary : .primary)
                        .frame(maxWidth: 40, minHeight: 44)
                        .background(.quaternary, in: cell)
                        .overlay { cell.strokeBorder(index == activeIndex ? Color.accentColor : .clear, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("第 \(index + 1) 位", "Digit \(index + 1)"))
                .accessibilityValue(String(digit ?? "0"))
                .accessibilityAddTraits(index == activeIndex ? .isSelected : [])
                .accessibilityIdentifier("manual-result.digit.\(index)")
            }
        }
        .font(.title2.monospacedDigit())
        .environment(\.layoutDirection, .leftToRight)
        .background {
            ManualSolveKeyboard(
                label: language.text("用时", "Time"),
                displayedDigits: time.displayedDigits,
                focusRequest: focusRequest,
                insert: { activeIndex = time.insert($0, at: activeIndex) },
                delete: {
                    activeIndex = max(0, activeIndex - 1)
                    time.clearDigit(at: activeIndex)
                }
            )
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

private struct ManualSolveKeyboard: UIViewRepresentable {
    let label: String
    let displayedDigits: String
    let focusRequest: Int
    let insert: (String) -> Void
    let delete: () -> Void

    func makeUIView(context: Context) -> DigitField {
        let field = DigitField()
        field.delegate = field
        field.keyboardType = .numberPad
        field.textColor = .clear
        field.tintColor = .clear
        field.accessibilityIdentifier = "manual-result.time"
        return field
    }

    func updateUIView(_ field: DigitField, context: Context) {
        field.accessibilityLabel = label
        if field.text != displayedDigits { field.text = displayedDigits }
        field.insertDigits = insert
        field.removeDigit = delete
        if field.focusRequest != focusRequest {
            field.focusRequest = focusRequest
            field.requestFocus()
        }
    }

    final class DigitField: UITextField, UITextFieldDelegate {
        var focusRequest = 0
        var insertDigits: ((String) -> Void)?
        var removeDigit: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { requestFocus() }
        }

        func requestFocus() {
            // Focus after UIKit installs the field in the presentation's window.
            DispatchQueue.main.async { [weak self] in
                guard let self, window != nil else { return }
                becomeFirstResponder()
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if string.isEmpty {
                removeDigit?()
            } else {
                insertDigits?(string)
            }
            return false
        }

        override func paste(_ sender: Any?) {
            if let text = UIPasteboard.general.string { insertDigits?(text) }
        }
    }
}
