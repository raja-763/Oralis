import Foundation

/// Wraps the Anthropic Claude API to provide a conversational assistant for
/// email, calendar, and voice-controlled web browsing.
///
/// Authentication priority:
///   1. Direct Anthropic API key (ANTHROPIC_API_KEY in Secrets.xcconfig)
///   2. Cloudflare Worker proxy (ORALIS_PROXY_URL in Secrets.xcconfig or hardcoded fallback)
@MainActor
final class AIAgentService: ObservableObject {

    private static var anthropicAPIKey: String {
        // UserDefaults key (entered via Settings) takes priority over build-time xcconfig value.
        let ud = UserDefaults.standard.string(forKey: "oralis.anthropicAPIKey") ?? ""
        if !ud.isEmpty { return ud }
        return Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
    }
    private static let proxyURLString: String = {
        Bundle.main.infoDictionary?["ORALIS_PROXY_URL"] as? String ?? ""
    }()

    private static var workspaceID: String {
        let ud = UserDefaults.standard.string(forKey: "oralis.anthropicWorkspaceID") ?? ""
        if !ud.isEmpty { return ud }
        return Bundle.main.infoDictionary?["ANTHROPIC_WORKSPACE_ID"] as? String ?? ""
    }

    private let directURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private var proxyURL: URL? {
        let s = AIAgentService.proxyURLString
        return s.isEmpty ? nil : URL(string: s)
    }
    private var usingDirectAPI: Bool {
        !AIAgentService.anthropicAPIKey.isEmpty
    }

    private let model = "claude-haiku-5-5"

    private var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "oralis.deviceID") { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "oralis.deviceID")
        return id
    }

    // MARK: - System prompt

    private let systemPrompt = """
    You are Oralis, a voice-first accessible AI assistant for macOS.
    You help blind and visually-impaired users control email, browse the web, and manage their calendar — all by voice.

    IMPORTANT: Always respond in the same language the user used to ask the question.

    You can perform actions by responding with a JSON block in your reply.
    Put actions after your spoken reply, each as its own JSON block. When the user asks for several things at once ("delete the first two and star the one from my bank"), include one block per step, in the order they should happen, up to five. The app carries them out one after another.

    EMAIL ACTIONS:
    Read email:          { "action": "readEmail",    "threadID": "..." }
    Summarize email:     { "action": "summarize",    "threadID": "..." }
    Triage inbox:        { "action": "triage" }
    Delete emails:       { "action": "delete",       "threadIDs": ["..."] }
    Archive emails:      { "action": "archive",      "threadIDs": ["..."] }
    Reply to email:      { "action": "reply",        "threadID": "...", "body": "..." }
    Forward email:       { "action": "forward",      "threadID": "...", "to": "...", "body": "..." }
    Send a new email:    { "action": "draft",        "to": "email address or contact name", "subject": "...", "body": "..." }
    Mark read or unread: { "action": "markRead",     "threadIDs": ["..."], "read": true }
    Star or unstar:      { "action": "star",         "threadIDs": ["..."], "starred": true }
    Search emails:       { "action": "search",       "query": "..." }
    Unsubscribe:         { "action": "unsubscribe",  "threadID": "..." }
    List spam folder:    { "action": "listSpam" }
    Mark as spam:        { "action": "markSpam",     "threadIDs": ["..."] }
    Empty spam folder:   { "action": "deleteSpam" }
    Move back to inbox:  { "action": "moveToInbox",  "threadIDs": ["..."] }

    CALENDAR ACTIONS:
    List events:         { "action": "listCalendar",  "days": 7 }
    Create event:        { "action": "createEvent",   "title": "...", "date": "2026-11-15T14:00:00", "duration": 60 }
    Accept invite:       { "action": "acceptInvite",  "threadID": "..." }
    Decline invite:      { "action": "declineInvite", "threadID": "..." }

    WEB BROWSER ACTIONS:
    Navigate to URL:     { "action": "navigateTo",    "url": "https://..." }
    Read web page:       { "action": "readWebPage" }
    Fill form field:     { "action": "fillForm",      "field": "email", "value": "user@example.com" }
    Click element:       { "action": "clickElement",  "text": "Submit" }
    Scroll down:         { "action": "scrollDown" }
    Go back:             { "action": "goBack" }
    Open link:           { "action": "openLink",      "url": "https://..." }

    Understanding the user:
    - The user speaks or types in everyday language, often loosely, and speech recognition may mishear words. Work out what they most likely mean from the conversation so far; never ask them to rephrase or to use particular words.
    - Resolve references yourself: "the second one", "that one", "the last one you read", "the one from my bank", "all of those", "it" refer to emails you listed or discussed. Match senders and subjects loosely (partial names, nicknames, misheard spellings).
    - If a request could mean two different emails or actions, ask one short question. Otherwise just do it.
    - The reply, forward and draft actions SEND the email immediately. Before sending, say who it is going to and read the wording back, and ask "Shall I send it?". Only include the action after the user agrees. If they ask for changes, revise and read it back again.
    - You handle email, calendar and web pages only. You cannot send text messages or iMessages.
    - If the user asks for something you have no action for, say so plainly in one sentence and offer the closest thing you can do.

    Rules:
    - Be concise — the user hears everything you say read aloud. This is a spoken back-and-forth conversation: answer in one to three short sentences unless asked for more, use plain speech with no lists, symbols or markdown, and remember what was said earlier in the conversation.
    - The INBOX context lists the newest emails with their threadID, sender, time, subject and a preview. When the user asks what is in their inbox or asks for their latest emails, answer immediately from that list: say who each one is from and what it is about, newest first, three at a time unless asked for more. Never tell the user to wait and never say you are "about to" read something.
    - When the user asks to hear one specific email in full, say only a few words such as "Here it is." and include the readEmail action with that email's exact threadID from the list. The app then reads the full email aloud. Never invent a threadID.
    - Spam: to tell the user what is in spam, use listSpam; the app reads the list aloud. Once the SPAM FOLDER context is present you can delete chosen spam emails with the delete action and their threadIDs. Before deleteSpam (which empties the whole spam folder) ask the user to confirm, and only include the action after they say yes. Deleting moves emails to Trash.
    - Moving mail back to the inbox (from spam, trash or the archive) uses moveToInbox with threadIDs. If the email is in the SPAM FOLDER or SEARCH RESULTS context, use its threadID straight away. If it is not listed yet, first find it with a search action using Gmail search words, for example "in:spam from:amazon", "in:trash invoice" or "-in:inbox newsletter"; the app reads the matches aloud, and on the user's next message you can move the one they mean.
    - Confirm before deleting more than 10 emails.
    - Never write action names, brackets such as "[Action: ...]" or any description of the JSON in your spoken text; only the JSON block itself carries an action.
    - For drafts, write in the user's language and tone.
    - For web browsing, describe what action you are taking before the JSON.
    - For form fields, use the visible label or placeholder name as the "field" value.
    """

    // MARK: - Send a message

    func send(
        userMessage: String,
        history: ArraySlice<AgentMessage>,
        context: EmailAgentContext
    ) async throws -> AgentResponse {
        let messages = buildMessages(history: history, userMessage: userMessage, context: context)
        let body = try JSONEncoder().encode(ClaudeRequest(
            model: model,
            max_tokens: 1024,
            system: systemPrompt,
            messages: messages
        ))

        let endpoint: URL
        if usingDirectAPI {
            endpoint = directURL
        } else if let proxy = proxyURL {
            endpoint = proxy
        } else {
            throw OralisError.apiError("No API key or proxy configured. Add ANTHROPIC_API_KEY to Secrets.xcconfig.")
        }

        // Builds the request; the proxy build identifies the user with their Google token.
        func makeRequest(proxyToken: String?) -> URLRequest {
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if usingDirectAPI {
                req.setValue(AIAgentService.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                let ws = AIAgentService.workspaceID
                if !ws.isEmpty {
                    req.setValue(ws, forHTTPHeaderField: "anthropic-workspace-id")
                }
            } else {
                req.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
                if let proxyToken { req.setValue("Bearer \(proxyToken)", forHTTPHeaderField: "Authorization") }
            }
            req.httpBody = body
            return req
        }

        var proxyToken: String?
        if !usingDirectAPI {
            proxyToken = await ProxyAuth.token()
            guard proxyToken != nil else { throw OralisError.apiError(ProxyAuth.signInMessage) }
        }

        var (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: makeRequest(proxyToken: proxyToken))
        } catch let error as URLError where error.code == .networkConnectionLost || error.code == .timedOut {
            // A dropped connection is usually momentary; try once more before reporting it.
            (data, response) = try await URLSession.shared.data(for: makeRequest(proxyToken: proxyToken))
        }
        // An expired Google token is refreshed once and the request repeated.
        if !usingDirectAPI, (response as? HTTPURLResponse)?.statusCode == 401,
           let fresh = await ProxyAuth.token(refresh: true) {
            (data, response) = try await URLSession.shared.data(for: makeRequest(proxyToken: fresh))
        }
        let rawBody = String(data: data, encoding: .utf8) ?? ""

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OralisError.apiError("HTTP \(http.statusCode): \(rawBody.prefix(300))")
        }

        // Catch decode failures and surface the raw response so errors are visible
        do {
            let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            let text = result.content.first(where: { $0.type == "text" })?.text ?? ""
            let actions = AIAgentService.jsonBlocks(in: text).compactMap { parseAction(String(text[$0])) }
            return AgentResponse(text: text, actions: Array(actions.prefix(5)))
        } catch {
            throw OralisError.apiError(rawBody.isEmpty ? error.localizedDescription : String(rawBody.prefix(300)))
        }
    }

    // MARK: - Build message array

    private func buildMessages(
        history: ArraySlice<AgentMessage>,
        userMessage: String,
        context: EmailAgentContext
    ) -> [ClaudeMessage] {
        var messages: [ClaudeMessage] = []

        // Inject combined context as the first synthetic exchange
        var contextParts: [String] = []
        if !context.inboxSummary.isEmpty {
            contextParts.append("INBOX:\n\(context.inboxSummary)")
        }
        if let cal = context.calendarSummary, !cal.isEmpty {
            contextParts.append("CALENDAR:\n\(cal)")
        }
        if let pageText = context.webPageContent, !pageText.isEmpty {
            let preview = String(pageText.prefix(1500))
            let urlStr = context.webPageURL?.absoluteString ?? ""
            contextParts.append("CURRENT WEB PAGE: \(urlStr)\n\(preview)")
        }
        if let thread = context.selectedThread {
            let body = thread.messages.first.map { String($0.bodyPlain.prefix(500)) } ?? ""
            contextParts.append("SELECTED EMAIL:\nSubject: \(thread.subject)\nFrom: \(thread.participants.first?.display ?? "unknown")\n\(body)")
        }

        if !contextParts.isEmpty {
            messages.append(ClaudeMessage(role: "user", content: contextParts.joined(separator: "\n\n")))
            messages.append(ClaudeMessage(role: "assistant", content: "I have your context. How can I help?"))
        }

        for msg in history.suffix(20) {
            messages.append(ClaudeMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            ))
        }

        messages.append(ClaudeMessage(role: "user", content: userMessage))
        return messages
    }

    // MARK: - Parse action JSON from response text

    /// Ranges of each top-level { ... } block in the text, ignoring braces inside strings.
    static func jsonBlocks(in text: String) -> [Range<String.Index>] {
        var blocks: [Range<String.Index>] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" && depth > 0 {
                inString = true
            } else if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}" && depth > 0 {
                depth -= 1
                if depth == 0, let s = start {
                    blocks.append(s..<text.index(after: index))
                    start = nil
                }
            }
            index = text.index(after: index)
        }
        return blocks
    }

    private func parseAction(_ text: String) -> AgentAction? {
        guard let start = text.range(of: "{"),
              let end   = text.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else { return nil }

        // Half-open range: upperBound is already one past the brace, and equals
        // endIndex when the reply ends with the action block.
        let jsonStr = String(text[start.lowerBound..<end.upperBound])
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["action"] as? String
        else { return nil }

        switch name {
        case "readEmail":
            return .readEmail(threadID: dict["threadID"] as? String ?? "")
        case "summarize":
            return .summarize(threadID: dict["threadID"] as? String ?? "")
        case "triage":
            return .triage
        case "delete":
            return .delete(ids: (dict["threadIDs"] as? [String]) ?? [])
        case "archive":
            return .archive(ids: (dict["threadIDs"] as? [String]) ?? [])
        case "reply":
            return .reply(threadID: dict["threadID"] as? String ?? "",
                          body: dict["body"] as? String ?? "")
        case "forward":
            return .forward(threadID: dict["threadID"] as? String ?? "",
                            to: dict["to"] as? String ?? "",
                            body: dict["body"] as? String ?? "")
        case "draft":
            return .draft(to: dict["to"] as? String ?? "",
                          subject: dict["subject"] as? String ?? "",
                          body: dict["body"] as? String ?? "")
        case "markRead":
            return .markRead(ids: dict["threadIDs"] as? [String] ?? [], read: dict["read"] as? Bool ?? true)
        case "star":
            return .star(ids: dict["threadIDs"] as? [String] ?? [], starred: dict["starred"] as? Bool ?? true)
        case "search":
            return .search(query: dict["query"] as? String ?? "")
        case "unsubscribe":
            return .unsubscribe(threadID: dict["threadID"] as? String ?? "")
        case "listSpam":
            return .listSpam
        case "markSpam":
            return .markSpam(ids: dict["threadIDs"] as? [String] ?? [])
        case "moveToInbox":
            return .moveToInbox(ids: dict["threadIDs"] as? [String] ?? [])
        case "deleteSpam":
            return .deleteSpam
        case "listCalendar":
            return .listCalendar(days: dict["days"] as? Int ?? 7)
        case "createEvent":
            return .createEvent(title: dict["title"] as? String ?? "",
                                date: dict["date"] as? String ?? "",
                                duration: dict["duration"] as? Int ?? 60)
        case "acceptInvite":
            return .acceptInvite(threadID: dict["threadID"] as? String ?? "")
        case "declineInvite":
            return .declineInvite(threadID: dict["threadID"] as? String ?? "")
        case "navigateTo":
            if let u = dict["url"] as? String, let url = URL(string: u) { return .navigateTo(url: url) }
        case "readWebPage":
            return .readWebPage
        case "fillForm":
            return .fillWebForm(field: dict["field"] as? String ?? "",
                                value: dict["value"] as? String ?? "")
        case "clickElement":
            return .clickElement(text: dict["text"] as? String ?? "")
        case "scrollDown":
            return .scrollDown
        case "goBack":
            return .goBack
        case "openLink":
            if let u = dict["url"] as? String, let url = URL(string: u) { return .openLink(url: url) }
        default: break
        }
        return nil
    }
}

// MARK: - Supporting types

struct AgentResponse {
    var text: String
    var actions: [AgentAction]
    var action: AgentAction? { actions.first }
}

struct EmailAgentContext {
    var inboxSummary: String
    var selectedThread: EmailThread?
    var webPageURL: URL?
    var webPageContent: String?
    var calendarSummary: String?
}

enum AgentAction {
    // Email
    case readEmail(threadID: String)
    case summarize(threadID: String)
    case triage
    case delete(ids: [String])
    case archive(ids: [String])
    case reply(threadID: String, body: String)
    case forward(threadID: String, to: String, body: String)
    case draft(to: String, subject: String, body: String)
    case search(query: String)
    case unsubscribe(threadID: String)
    case deleteSpam
    case listSpam
    case markSpam(ids: [String])
    case moveToInbox(ids: [String])
    case markRead(ids: [String], read: Bool)
    case star(ids: [String], starred: Bool)
    // Calendar
    case listCalendar(days: Int)
    case createEvent(title: String, date: String, duration: Int)
    case acceptInvite(threadID: String)
    case declineInvite(threadID: String)
    // Browser
    case navigateTo(url: URL)
    case readWebPage
    case fillWebForm(field: String, value: String)
    case clickElement(text: String)
    case scrollDown
    case goBack
    case openLink(url: URL)
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
    struct Content: Decodable {
        var type: String
        var text: String?
    }
    var content: [Content]
}
