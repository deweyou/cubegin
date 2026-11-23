import SwiftUI

struct FeedbackDraft: Equatable {
    let message: String
    let email: String

    init(message: String, email: String) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isMessageValid: Bool { !message.isEmpty && message.utf16.count <= 4000 }

    var isEmailValid: Bool {
        email.isEmpty || (email.utf16.count <= 254
            && email.wholeMatch(of: /[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+/) != nil)
    }
}

struct FeedbackSubmission: Encodable {
    let draft: FeedbackDraft
    let requestId = UUID()

    private enum CodingKeys: String, CodingKey { case message, email, requestId }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(draft.message, forKey: .message)
        if !draft.email.isEmpty {
            try container.encode(draft.email, forKey: .email)
        }
        try container.encode(requestId, forKey: .requestId)
    }

    func request(to endpoint: URL) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(self)
        return request
    }

    func send(to endpoint: URL) async throws {
        struct Receipt: Decodable { let sent: Bool }
        let (data, response) = try await URLSession.shared.data(for: request(to: endpoint))
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              try JSONDecoder().decode(Receipt.self, from: data).sent else {
            throw URLError(.badServerResponse)
        }
    }
}

struct FeedbackSettingsView: View {
    @Environment(\.locale) private var locale
    @FocusState private var focusedField: Field?
    @State private var message = ""
    @State private var email = ""
    @State private var lastSubmission: FeedbackSubmission?
    @State private var status = SubmissionStatus.idle

    private enum Field { case message, email }
    private enum SubmissionStatus { case idle, sending, sent, failed }

    private var language: AppLanguage { locale.appLanguage }
    private var draft: FeedbackDraft { FeedbackDraft(message: message, email: email) }

    private static let feedbackEndpoint: URL? = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CubeginFeedbackBaseURL") as? String,
           let url = URL(string: value), url.scheme == "https", url.host != nil {
            return url.appending(path: "api/feedback")
        }
#if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://localhost:4489/api/feedback")
#else
        return nil
#endif
    }()

    private static let reviewURL: URL? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CubeginAppStoreID") as? String,
              id.wholeMatch(of: /[0-9]+/) != nil else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }()

    var body: some View {
        Form {
            CardSection {
                TextField(language.text("请描述你的问题或建议", "Describe your issue or suggestion"), text: $message, axis: .vertical)
                    .lineLimit(5...10)
                    .padding(.vertical, 12)
                    .focused($focusedField, equals: .message)
                    .accessibilityIdentifier("settings.feedback.message")
                    .disabled(status == .sending)
            } header: {
                Text(language.text("反馈内容（必填）", "Feedback (required)"))
            } footer: {
                if draft.message.utf16.count > 4000 {
                    Text(language.text("反馈内容不能超过 4,000 字符。", "Feedback must be 4,000 characters or fewer."))
                        .foregroundStyle(.red)
                }
            }

            CardSection {
                TextField(language.text("邮箱地址", "Email address"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .focused($focusedField, equals: .email)
                    .accessibilityIdentifier("settings.feedback.email")
                    .disabled(status == .sending)
            } header: {
                Text(language.text("邮箱（选填）", "Email (optional)"))
            } footer: {
                if !draft.isEmailValid && focusedField != .email {
                    Text(language.text("请输入有效的邮箱地址。", "Enter a valid email address."))
                        .foregroundStyle(.red)
                } else {
                    Text(language.text("如果希望收到回复，请留下邮箱。", "Leave your email if you’d like a reply."))
                }
            }

            CardSection {
                cardRowButton(action: sendFeedback) {
                    HStack {
                        Text(language.text("发送反馈", "Send Feedback"))
                        if status == .sending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .accessibilityIdentifier("settings.feedback.send")
                .disabled(Self.feedbackEndpoint == nil || !draft.isMessageValid || !draft.isEmailValid || status == .sending)
            } footer: {
                if Self.feedbackEndpoint == nil {
                    Text(language.text("当前版本暂时无法发送反馈。", "Feedback is unavailable in this build."))
                } else if status == .sent {
                    Text(language.text("反馈已发送，谢谢！", "Feedback sent. Thank you!"))
                        .accessibilityIdentifier("settings.feedback.sent")
                } else if status == .failed {
                    Text(language.text("反馈发送失败，请重试。", "Couldn’t send feedback. Please try again."))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.feedback.failed")
                }
            }

            if let reviewURL = Self.reviewURL {
                CardSection {
                    Link(destination: reviewURL) {
                        HStack {
                            Text(language.text("在 App Store 评价", "Review on the App Store"))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("settings.feedback.review")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle(language.text("反馈与评价", "Feedback & Reviews"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func sendFeedback() {
        let draft = draft
        guard let endpoint = Self.feedbackEndpoint, draft.isMessageValid, draft.isEmailValid,
              status != .sending else { return }

        let submission = lastSubmission.flatMap { $0.draft == draft ? $0 : nil } ?? FeedbackSubmission(draft: draft)
        lastSubmission = submission
        focusedField = nil
        status = .sending
        Task {
            do {
                try await submission.send(to: endpoint)
                message = ""
                email = ""
                lastSubmission = nil
                status = .sent
            } catch {
                status = .failed
            }
        }
    }
}
