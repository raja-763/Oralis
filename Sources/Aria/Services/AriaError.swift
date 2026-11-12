import Foundation

enum OralisError: LocalizedError {
    case notAuthenticated
    case notImplemented(String)
    case apiError(String)
    case missingAPIKey
    case unsubscribeFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in to your email account."
        case .notImplemented(let feature):
            return "\(feature) is not yet implemented."
        case .apiError(let msg):
            return "API error: \(msg)"
        case .missingAPIKey:
            return "Anthropic API key not set. Add it in Settings."
        case .unsubscribeFailed(let reason):
            return "Could not unsubscribe: \(reason)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}


/// Appends a diagnostic line to ~/Library/Logs/Oralis.log. Never log tokens or message content.
func oralisLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Oralis.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
