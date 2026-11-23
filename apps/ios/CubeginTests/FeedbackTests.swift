import Foundation
import Testing
@testable import CubeginApp

struct FeedbackTests {
    @Test
    func requiresTextAndAcceptsAnEmptyEmail() {
        #expect(!FeedbackDraft(message: " \n", email: "").isMessageValid)
        #expect(FeedbackDraft(message: "建议", email: "  ").isEmailValid)
        #expect(!FeedbackDraft(message: "建议", email: "person@").isEmailValid)
        #expect(!FeedbackDraft(message: String(repeating: "😀", count: 2001), email: "").isMessageValid)
    }

    @Test(arguments: ["", "user+feedback@example.com"])
    func encodesTheExistingFeedbackAPI(email: String) throws {
        let endpoint = try #require(URL(string: "https://example.com/api/feedback"))
        let submission = FeedbackSubmission(draft: FeedbackDraft(message: "  建议\n", email: email))
        let request = try submission.request(to: endpoint)
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

        #expect(request.url == endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(payload["message"] == "建议")
        #expect(payload["email"] == (email.isEmpty ? nil : email))
        #expect(payload["requestId"] == submission.requestId.uuidString)
        #expect(FeedbackSubmission(draft: submission.draft).requestId != submission.requestId)
    }
}
