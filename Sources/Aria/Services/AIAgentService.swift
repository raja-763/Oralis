import Foundation

/// Wraps the Anthropic Claude API to provide a conversational email assistant.
/// The agent can read threads, perform actions, and answer questions about email.
@MainActor
final class AIAgentService: ObservableObject {

    // Set your API key in Keychain under key "oralis.anthropic.key"
    private var apiKey: String {
        KeychainService.shared.load(key: "oralis.anthropic.key") ?? ""
    }

    private let model = "claude-opus-4-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // System prompt that tells the agent about its email capabilities
    private let systemPrompt = """
    You are Oralis, an accessible, voice-first email assistant for macOS.
    You help blind and visually-impaired users manage email completely by voice.

    You can perform these actions — respond with a JSON action block when needed:
    - Read an email:        { "action": "readEmail",    "threadID": "..." }
    - Delete emails:        { "action": "delete",       "threadIDs": ["..."] }
    - Archive emails:       { "action": "archive",      "threadIDs": ["..."] }
    - Reply to an email:    { "action": "reply",        "threadID": "...", "body": "..." }
    - Forward an email:     { "action": "forward",      "threadID": "...", "to": "...", "body": "..." }
    - Search emails:        { "action": "search",       "query": "..." }
    - Unsubscribe:          { "action": "unsubscribe",  "threadID": "..." }
    - Delete spam:          { "action": "deleteSpam"  }
    - Accept calendar invite: { "action": "acceptInvite",  "threadID": "..." }
    - Decline calendar invite: { "action": "declineInvite", "threadID": "..." }
    - Open a link:          { "action": "openLink",     "url": "..." }
    - Fill a form:          { "action": "fillForm",     "url": "..." }

    Always be concise. The user will hear your response read aloud.
    Confirm actions before performing destructive ones (delete of more than 10 emails).
    """

    // MARK: - Send a message

    func send(
        userMessage: String,
        history: [AgentMessage],
        context: EmailAgentContext
    ) async throws -> AgentResponse {
        guard !apiKey.isEmpty else { throw OralisError.missingAPIKey }

        let messages = buildMessages(history: history, userMessage: userMessage, context: context)
        let body = try JSONEncoder().encode(ClaudeRequest(
            model: model,
            max_tokens: 1024,
            system: systemPrompt,
            messages: messages
        ))

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OralisError.apiError("Claude API returned an error")
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = result.content.first?.text ?? ""
        return AgentResponse(text: text, action: parseAction(text))
    }

    // MARK: - Build message array

    private func buildMessages(
        history: [AgentMessage],
        userMessage: String,
        context: EmailAgentContext
    ) -> [ClaudeMessage] {
        var messages: [ClaudeMessage] = []

        // Inject current inbox summary as the first user turn
        if !context.inboxSummary.isEmpty {
            messages.append(ClaudeMessage(role: "user", content: context.inboxSummary))
            messages.append(ClaudeMessage(role: "assistant", content: "I have your inbox context. How can I help?"))
        }

        // Add conversation history
        for msg in history.suffix(20) {
            messages.append(ClaudeMessage(role: msg.role == .user ? "user" : "assistant",
                                          content: msg.content))
        }

        messages.append(ClaudeMessage(role: "user", content: userMessage))
        return messages
    }

    // MARK: - Parse action JSON from response text

    private func parseAction(_ text: String) -> AgentAction? {
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else { return nil }

        let jsonStr = String(text[start.lowerBound...end.upperBound])
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionName = dict["action"] as? String
        else { return nil }

        switch actionName {
        case "delete":
            return .delete(ids: (dict["threadIDs"] as? [String]) ?? [])
        case "archive":
            return .archive(ids: (dict["threadIDs"] as? [String]) ?? [])
        case "unsubscribe":
            return .unsubscribe(threadID: dict["threadID"] as? String ?? "")
        case "deleteSpam":
            return .deleteSpam
        case "search":
            return .search(query: dict["query"] as? String ?? "")
        case "acceptInvite":
            return .acceptInvite(threadID: dict["threadID"] as? String ?? "")
        case "declineInvite":
            return .declineInvite(threadID: dict["threadID"] as? String ?? "")
        case "openLink":
            if let u = dict["url"] as? String, let url = URL(string: u) {
                return .openLink(url: url)
            }
        case "fillForm":
            if let u = dict["url"] as? String, let url = URL(string: u) {
                return .fillForm(url: url)
            }
        case "reply":
            return .reply(threadID: dict["threadID"] as? String ?? "",
                          body: dict["body"] as? String ?? "")
        default: break
        }
        return nil
    }
}

// MARK: - Supporting types

struct AgentResponse {
    var text: String
    var action: AgentAction?
}

struct EmailAgentContext {
    var inboxSummary: String    // e.g. "You have 12 unread emails, 3 from..."
    var selectedThread: EmailThread?
}

enum AgentAction {
    case delete(ids: [String])
    case archive(ids: [String])
    case reply(threadID: String, body: String)
    case forward(threadID: String, to: String, body: String)
    case search(query: String)
    case unsubscribe(threadID: String)
    case deleteSpam
    case acceptInvite(threadID: String)
    case declineInvite(threadID: String)
    case openLink(url: URL)
    case fillForm(url: URL)
}

// MARK: - API shapes

private struct ClaudeRequest: Encodable {
    var model: String
    var max_tokens: Int
    var system: String
    var messages: [ClaudeMessage]
}

private struct ClaudeMessage: Codable {
    var role: String
    var content: String
}

private struct ClaudeResponse: Decodable {
    struct Content: Decodable { var text: String }
    var content: [Content]
}
