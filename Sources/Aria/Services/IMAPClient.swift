import Foundation
import Network

/// Minimal IMAP4rev1 client over TLS using NWConnection (Network.framework).
/// Supports: LOGIN, SELECT, FETCH headers + body preview, LOGOUT.
/// Enough to populate the inbox — reply/send goes through SMTP (IMAPService).
actor IMAPClient {

    private var connection: NWConnection?
    private var tagCounter = 0
    private var readBuffer = Data()

    // MARK: - Connect + authenticate

    func connect(host: String, port: Int) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        let params: NWParameters = port == 993 ? .tls : .tcp
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:   cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                case .cancelled:     cont.resume(throwing: IMAPError.connectionCancelled)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // Read and discard the server greeting
        _ = try await readLine()
    }

    func login(username: String, password: String) async throws {
        // Quote strings that contain special chars
        let user = quoted(username)
        let pass = quoted(password)
        let resp = try await send("LOGIN \(user) \(pass)")
        guard resp.contains("OK") else {
            throw IMAPError.loginFailed(resp)
        }
    }

    // MARK: - Inbox fetch

    /// Fetch the most recent `limit` threads from INBOX.
    func fetchInbox(limit: Int = 50) async throws -> [EmailThread] {
        let selectResp = try await send("SELECT INBOX")
        guard selectResp.contains("OK") else { throw IMAPError.commandFailed("SELECT", selectResp) }

        // Parse EXISTS count from "* N EXISTS"
        let existsLine = selectResp.components(separatedBy: "\r\n")
            .first(where: { $0.contains("EXISTS") }) ?? ""
        let count = existsLine.components(separatedBy: " ")
            .compactMap(Int.init).first ?? 0

        guard count > 0 else { return [] }

        let lo  = max(1, count - limit + 1)
        let hi  = count
        let set = "\(lo):\(hi)"

        // Fetch envelope + body preview
        let fetchResp = try await send(
            "FETCH \(set) (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[TEXT]<0.1500>)"
        )

        return parseMessages(from: fetchResp)
    }

    func logout() async {
        _ = try? await send("LOGOUT")
        connection?.cancel()
        connection = nil
    }

    // MARK: - Low-level send / read

    private func send(_ command: String) async throws -> String {
        tagCounter += 1
        let tag = "A\(String(format: "%03d", tagCounter))"
        let line = "\(tag) \(command)\r\n"
        try await write(Data(line.utf8))
        return try await readUntilTagged(tag: tag)
    }

    private func write(_ data: Data) async throws {
        guard let conn = connection else { throw IMAPError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else       { cont.resume() }
            })
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let range = readBuffer.range(of: Data("\r\n".utf8)) {
                let line = String(data: readBuffer[..<range.lowerBound], encoding: .utf8) ?? ""
                readBuffer.removeSubrange(..<range.upperBound)
                return line
            }
            let chunk = try await receive()
            readBuffer.append(chunk)
        }
    }

    private func readUntilTagged(tag: String) async throws -> String {
        var result = ""
        while true {
            let line = try await readLine()
            result += line + "\r\n"
            if line.hasPrefix(tag + " ") { break }
            // Safety: stop after 1 MB to avoid runaway reads
            if result.count > 1_048_576 { break }
        }
        return result
    }

    private func receive() async throws -> Data {
        guard let conn = connection else { throw IMAPError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, err in
                if let err { cont.resume(throwing: err) }
                else if let data { cont.resume(returning: data) }
                else { cont.resume(returning: Data()) }
            }
        }
    }

    // MARK: - Parse FETCH response

    private func parseMessages(from response: String) -> [EmailThread] {
        // Split on FETCH response boundaries: "* N FETCH ("
        let fetchBlocks = splitFetchBlocks(response)
        var threads: [EmailThread] = []

        for block in fetchBlocks {
            guard let thread = parseOneFetch(block) else { continue }
            threads.append(thread)
        }

        return threads.reversed() // most recent first
    }

    private func splitFetchBlocks(_ s: String) -> [String] {
        var blocks: [String] = []
        let lines  = s.components(separatedBy: "\r\n")
        var current = ""
        for line in lines {
            if line.hasPrefix("* ") && line.contains(" FETCH (") {
                if !current.isEmpty { blocks.append(current) }
                current = line + "\r\n"
            } else {
                current += line + "\r\n"
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private func parseOneFetch(_ block: String) -> EmailThread? {
        // UID
        let uid = extractParenValue(block, key: "UID") ?? UUID().uuidString

        // FLAGS
        let isRead = block.contains("\\Seen")

        // INTERNALDATE
        let dateStr = extractParenValue(block, key: "INTERNALDATE")
        let date    = parseIMAPDate(dateStr ?? "") ?? Date()

        // ENVELOPE: (date subject (from) (sender) (reply-to) (to) (cc) (bcc) in-reply-to message-id)
        let subject  = extractEnvelopeField(block, index: 1)?.trimIMAPString() ?? "(No subject)"
        let fromName = extractEnvelopeAddress(block, envelopeIndex: 2)
        let fromAddr = extractEnvelopeAddress(block, envelopeIndex: 2, addressPart: 2)

        // Body preview
        let bodyText = extractBodyText(block)

        let msgID    = UUID()
        let threadID = UUID()
        let from     = EmailAddress(name: fromName ?? "", address: fromAddr ?? "unknown@unknown.com")
        let msg      = EmailMessage(
            id:               msgID,
            remoteID:         uid,
            accountID:        UUID(), // filled in by IMAPService after fetch
            from:             from,
            to:               [],
            cc:               [],
            subject:          subject,
            bodyPlain:        bodyText,
            bodyHTML:         "",
            date:             date,
            isRead:           isRead,
            isStarred:        block.contains("\\Flagged"),
            labels:           [],
            links:            [],
            unsubscribeURL:   nil,
            unsubscribeEmail: nil,
            calendarInvite:   nil
        )
        return EmailThread(
            id:            threadID,
            remoteThreadID: uid,
            accountID:     UUID(), // filled by IMAPService
            subject:       subject,
            participants:  [from],
            messages:      [msg],
            latestDate:    date,
            isRead:        isRead,
            isStarred:     block.contains("\\Flagged"),
            labels:        [],
            snippet:       String(bodyText.prefix(100))
        )
    }

    // MARK: - Parsing helpers

    private func extractParenValue(_ s: String, key: String) -> String? {
        guard let range = s.range(of: key + " ") else { return nil }
        let after = s[range.upperBound...]
        if after.first == "\"" {
            let inner = after.dropFirst()
            guard let end = inner.firstIndex(of: "\"") else { return nil }
            return String(inner[..<end])
        }
        return after.prefix(while: { !$0.isWhitespace && $0 != ")" }).map(String.init(_:)).joined()
    }

    /// Extracts a field from the ENVELOPE list by zero-based index.
    /// ENVELOPE = (date subject (from...) (sender...) (reply-to...) (to...) ...)
    private func extractEnvelopeField(_ s: String, index: Int) -> String? {
        guard let envStart = s.range(of: "ENVELOPE (") else { return nil }
        let envelope = String(s[envStart.upperBound...])
        // Simple tokeniser: split top-level items
        var items: [String] = []
        var depth = 0
        var current = ""
        for ch in envelope {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")":
                depth -= 1
                if depth < 0 { break }
                current.append(ch)
                if depth == 0 { items.append(current); current = "" }
            case " " where depth == 0:
                if !current.isEmpty { items.append(current); current = "" }
            default: current.append(ch)
            }
        }
        guard index < items.count else { return nil }
        return items[index]
    }

    /// Extract name (part 0) or email (part 2) from an address struct like
    /// (("Name" NIL "user" "domain.com"))
    private func extractEnvelopeAddress(_ s: String, envelopeIndex: Int, addressPart: Int = 0) -> String? {
        guard let field = extractEnvelopeField(s, index: envelopeIndex) else { return nil }
        // Strip outer parens to get ((inner))
        let stripped = field.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        // Now split by " "
        var parts: [String] = []
        var inQuote = false
        var curr    = ""
        for ch in stripped {
            if ch == "\"" { inQuote.toggle() }
            else if ch == " " && !inQuote { parts.append(curr); curr = "" }
            else { curr.append(ch) }
        }
        if !curr.isEmpty { parts.append(curr) }
        guard addressPart < parts.count else { return nil }
        let val = parts[addressPart].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return val == "NIL" ? nil : val
    }

    private func extractBodyText(_ s: String) -> String {
        // After BODY[TEXT] literal: {N}\r\n<data>
        guard let litStart = s.range(of: "BODY[TEXT] {") ?? s.range(of: "BODY[TEXT]<0> {") else {
            return ""
        }
        let after = s[litStart.upperBound...]
        guard let braceEnd = after.firstIndex(of: "}") else { return "" }
        let lenStr = String(after[..<braceEnd])
        let n = Int(lenStr) ?? 0
        let textStart = after.index(braceEnd, offsetBy: 3) // skip "}\r\n"
        guard textStart < after.endIndex else { return "" }
        let raw = String(after[textStart...].prefix(n))
        // Strip quoted-printable or base64 lightly — just return readable text
        return raw
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseIMAPDate(_ s: String) -> Date? {
        // "12-Nov-2026 10:30:00 +0000"
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return fmt.date(from: s)
    }

    private func quoted(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Extension for string trimming

private extension String {
    func trimIMAPString() -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .replacingOccurrences(of: "NIL", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum IMAPError: LocalizedError {
    case notConnected
    case connectionCancelled
    case loginFailed(String)
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .notConnected:            return "Not connected to IMAP server."
        case .connectionCancelled:     return "IMAP connection was cancelled."
        case .loginFailed(let r):      return "Login failed: \(r.prefix(120))"
        case .commandFailed(let c, let r): return "\(c) failed: \(r.prefix(120))"
        }
    }
}
