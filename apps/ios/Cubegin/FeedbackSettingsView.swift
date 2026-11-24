import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum FeedbackScreenshot {
    static let maximumCount = 3
    static let maximumBytes = 1_000_000

    nonisolated static func compress(_ data: Data) throws -> Data {
        guard data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FeedbackError.invalidImage
        }
        var dimension = 2048
        for _ in 0..<6 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw FeedbackError.invalidImage
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw FeedbackError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.87
            ] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= maximumBytes {
                return output as Data
            }
            dimension = Int(Double(dimension) * 0.78)
        }
        throw FeedbackError.invalidImage
    }
}

private enum FeedbackError: Error { case invalidImage, rateLimited }

struct FeedbackDraft: Equatable {
    static let maximumMessageLength = 200

    let message: String
    let email: String
    let screenshots: [Data]

    init(message: String, email: String, screenshots: [Data] = []) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.screenshots = screenshots
    }

    var messageLength: Int { message.utf16.count }
    var isMessageValid: Bool { (1...Self.maximumMessageLength).contains(messageLength) }

    var isEmailValid: Bool {
        email.isEmpty || (email.utf16.count <= 254
            && email.wholeMatch(of: /[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+/) != nil)
    }
}

struct FeedbackSubmission {
    let draft: FeedbackDraft
    let requestId = UUID()

    private let fields: [String: String]

    @MainActor
    init(draft: FeedbackDraft) {
        self.draft = draft
        let device = UIDevice.current
        var hardware = utsname()
        uname(&hardware)
        let hardwareModel = withUnsafeBytes(of: hardware.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
#if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareModel
#else
        let model = hardwareModel
#endif
        var fields = ["message": draft.message, "requestId": requestId.uuidString,
                      "source": "ios", "deviceModel": model,
                      "systemVersion": "\(device.systemName) \(device.systemVersion)",
                      "deviceId": AppTelemetry.deviceID]
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            fields["appVersion"] = "\(version) (\(build))"
        }
        fields["userId"] = AppTelemetry.supportUserID?.uuidString.lowercased()
        if !draft.email.isEmpty { fields["email"] = draft.email }
        self.fields = fields
    }

    func request(to endpoint: URL) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        if draft.screenshots.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
        } else {
            guard draft.screenshots.count <= FeedbackScreenshot.maximumCount,
                  draft.screenshots.allSatisfy({ !$0.isEmpty && $0.count <= FeedbackScreenshot.maximumBytes }) else {
                throw FeedbackError.invalidImage
            }
            let boundary = "Cubegin-\(UUID().uuidString)"
            var body = Data()
            for (name, value) in fields {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            for (index, screenshot) in draft.screenshots.enumerated() {
                let filename = "screenshot-\(index + 1).jpg"
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"images\"; filename=\"\(filename)\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
                body.append(screenshot)
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    func send(to endpoint: URL) async throws {
        struct Receipt: Decodable { let sent: Bool }
        let (data, response) = try await URLSession.shared.data(for: request(to: endpoint))
        if (response as? HTTPURLResponse)?.statusCode == 429 { throw FeedbackError.rateLimited }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              try JSONDecoder().decode(Receipt.self, from: data).sent else {
            throw URLError(.badServerResponse)
        }
    }
}

struct FeedbackSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage("feedback.replyEmail") private var savedReplyEmail = ""
    @FocusState private var focusedField: Field?
    @State private var message = ""
    @State private var email = ""
    @State private var didLoadReplyEmail = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var screenshots: [Data] = []
    @State private var isPreparing = false
    @State private var screenshotFailed = false
    @State private var lastSubmission: FeedbackSubmission?
    @State private var status = SubmissionStatus.idle
    @State private var validationNotice: (message: String, shownAt: ContinuousClock.Instant)?

    private enum Field { case message, email }
    private enum SubmissionStatus { case idle, sending, sent, failed, limited }

    private var language: AppLanguage { locale.appLanguage }
    private var draft: FeedbackDraft { FeedbackDraft(message: message, email: email, screenshots: screenshots) }

    private var validationMessage: String? {
        if Self.feedbackEndpoint == nil {
            return language.text("当前版本暂时无法发送反馈。", "Feedback is unavailable in this build.")
        }
        if isPreparing {
            return language.text("正在处理截图，请稍等。", "Please wait while screenshots are prepared.")
        }
        let draft = draft
        if draft.message.isEmpty {
            return language.text("请先填写反馈内容。", "Enter your feedback first.")
        }
        if !draft.isMessageValid {
            let limit = FeedbackDraft.maximumMessageLength.formatted(.number.locale(locale))
            return language.text("反馈内容不能超过 \(limit) 字符。", "Feedback must be \(limit) characters or fewer.")
        }
        if !draft.isEmailValid {
            return language.text("请输入有效的邮箱地址。", "Enter a valid email address.")
        }
        return nil
    }

    private static let feedbackEndpoint: URL? = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CubeginFeedbackBaseURL") as? String,
           let url = URL(string: value), url.scheme == "https", url.host != nil {
            return url.appending(path: "api/feedback")
        }
#if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://localhost:4490/api/feedback")
#else
        return URL(string: "https://cubegin.deweyou.me/api/feedback")
#endif
    }()

    private static let reviewURL: URL? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CubeginAppStoreID") as? String,
              id.wholeMatch(of: /[0-9]+/) != nil else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }()

    var body: some View {
        let validationMessage = validationMessage
        Form {
            CardSection {
                messageEditor
                replyEmailField
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("留下邮箱可收到回复。提交时会附上设备型号、系统和 App 版本，以及可用的诊断 ID。", "Leave your email for a reply. Your device model, system and app versions, and available diagnostic IDs are included when you send."))
                        .foregroundStyle(.secondary)
                    if screenshotFailed {
                        Text(language.text("部分截图无法添加，请重新选择。", "Some screenshots couldn’t be added. Choose them again."))
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Button(action: sendFeedback) {
                    HStack(spacing: 8) {
                        if status == .sending {
                            ProgressView()
                            Text(language.text("正在发送…", "Sending…"))
                        } else {
                            Label(language.text("发送反馈", "Send Feedback"), systemImage: "paperplane.fill")
                                .foregroundStyle(validationMessage == nil ? Color.white : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(validationMessage == nil ? Color.accentColor : Color(uiColor: .systemGray4))
                .accessibilityHint(validationMessage ?? "")
                .accessibilityIdentifier("settings.feedback.send")
                .disabled(status == .sending)
                .listRowInsets(EdgeInsets(top: 0, leading: cardShadowInset, bottom: 0, trailing: cardShadowInset))
                .listRowBackground(Color.clear)
            } footer: {
                if status == .sent {
                    Text(language.text("反馈已发送，谢谢！", "Feedback sent. Thank you!"))
                        .accessibilityIdentifier("settings.feedback.sent")
                } else if status == .failed {
                    Text(language.text("反馈发送失败，请重试。", "Couldn’t send feedback. Please try again."))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.feedback.failed")
                } else if status == .limited {
                    Text(language.text("反馈提交过于频繁，请稍后重试。", "Feedback is receiving too many requests. Please try again later."))
                        .foregroundStyle(.red)
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
        .onAppear {
            guard !didLoadReplyEmail else { return }
            email = savedReplyEmail
            didLoadReplyEmail = true
        }
        .overlay(alignment: .bottom) {
            if let validationNotice {
                Label(validationNotice.message, systemImage: "info.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.24)))
                    .padding()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("settings.feedback.validation")
            }
        }
        .task(id: validationNotice?.shownAt) {
            guard validationNotice != nil else { return }
#if DEBUG
            if ProcessInfo.processInfo.environment["CUBEGIN_UI_TEST_KEEP_FEEDBACK_NOTICE"] == "1" { return }
#endif
            do {
                try await Task.sleep(for: .seconds(3))
                validationNotice = nil
            } catch {}
        }
        .onChange(of: validationMessage) { _, _ in validationNotice = nil }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            selectedPhotos = []
            addScreenshots(items)
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(language.text("请描述你的问题或建议", "Describe your issue or suggestion"), text: $message, axis: .vertical)
                .lineLimit(5...10)
                .padding(.top, 12)
                .focused($focusedField, equals: .message)
                .accessibilityLabel(language.text("反馈内容", "Feedback"))
                .accessibilityIdentifier("settings.feedback.message")

            ViewThatFits(in: .horizontal) {
                editorFooter(tileSize: 68)
                editorFooter(tileSize: 56)
                editorFooter(tileSize: 48)
            }
            .padding(.vertical, 12)
        }
        .disabled(status == .sending)
    }

    private func editorFooter(tileSize: CGFloat) -> some View {
        let count = draft.messageLength
        let limit = FeedbackDraft.maximumMessageLength
        return HStack(alignment: .bottom, spacing: 8) {
            attachmentControls(tileSize: tileSize)
            Spacer(minLength: 0)
            Text("\(count.formatted(.number.grouping(.never))) / \(limit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count > limit ? Color.red : Color.secondary)
                .accessibilityLabel(language.text("\(count) / \(limit) 字符", "\(count) of \(limit) characters"))
                .accessibilityIdentifier("settings.feedback.characterCount")
                .fixedSize()
        }
    }

    private var replyEmailField: some View {
        HStack(spacing: 0) {
            TextField(language.text("邮箱（选填）", "Email (optional)"), text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .focused($focusedField, equals: .email)
                .accessibilityIdentifier("settings.feedback.email")

            if !email.isEmpty {
                Button {
                    email = ""
                    savedReplyEmail = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("清空邮箱", "Clear email"))
                .accessibilityIdentifier("settings.feedback.clearEmail")
            }
        }
        .disabled(status == .sending)
    }

    private let attachmentShape = RoundedRectangle(cornerRadius: 10)

    private func attachmentControls(tileSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(screenshots.indices, id: \.self) { index in
                screenshotTile(at: index, size: tileSize)
            }
            if screenshots.count < FeedbackScreenshot.maximumCount {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: FeedbackScreenshot.maximumCount - screenshots.count,
                    matching: .images
                ) {
                    ZStack {
                        attachmentShape.fill(Color.accentColor.opacity(0.05))
                        attachmentShape.strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        if isPreparing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(width: tileSize, height: tileSize)
                    .contentShape(attachmentShape)
                }
                .accessibilityLabel(isPreparing
                    ? language.text("正在处理截图", "Preparing screenshots")
                    : language.text("添加截图", "Add Screenshots"))
                .accessibilityIdentifier("settings.feedback.screenshots")
                .disabled(isPreparing || status == .sending)
            }
        }
    }

    private func screenshotTile(at index: Int, size: CGFloat) -> some View {
        attachmentShape.fill(.quaternary)
            .overlay {
                if let image = UIImage(data: screenshots[index]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(attachmentShape)
                        .accessibilityLabel(language.text("截图 \(index + 1)", "Screenshot \(index + 1)"))
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                Button {
                    screenshots.remove(at: index)
                    screenshotFailed = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(.black.opacity(0.72), in: Circle())
                        .padding(4)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(language.text("移除第 \(index + 1) 张截图", "Remove screenshot \(index + 1)"))
                .disabled(isPreparing || status == .sending)
            }
    }

    private func addScreenshots(_ items: [PhotosPickerItem]) {
        guard !isPreparing, status != .sending else { return }
        isPreparing = true
        screenshotFailed = false
        Task {
            defer { isPreparing = false }
            for item in items.prefix(FeedbackScreenshot.maximumCount - screenshots.count) {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw FeedbackError.invalidImage
                    }
                    let screenshot = try await Task.detached(priority: .userInitiated) {
                        try FeedbackScreenshot.compress(data)
                    }.value
                    screenshots.append(screenshot)
                } catch {
                    screenshotFailed = true
                }
            }
        }
    }

    private func sendFeedback() {
        guard status != .sending else { return }
        if let validationMessage {
            validationNotice = (validationMessage, .now)
            AccessibilityNotification.Announcement(validationMessage).post()
            return
        }
        guard let endpoint = Self.feedbackEndpoint else { return }
        let draft = draft

        let submission = lastSubmission.flatMap { $0.draft == draft ? $0 : nil } ?? FeedbackSubmission(draft: draft)
        lastSubmission = submission
        focusedField = nil
        status = .sending
        Task {
            do {
                try await submission.send(to: endpoint)
                message = ""
                savedReplyEmail = draft.email
                email = draft.email
                screenshots = []
                screenshotFailed = false
                lastSubmission = nil
                status = .sent
            } catch FeedbackError.rateLimited {
                status = .limited
            } catch {
                status = .failed
            }
        }
    }
}
