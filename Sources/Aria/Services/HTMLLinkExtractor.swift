import Foundation

/// Extracts links from HTML or plain text using NSDataDetector and
/// a lightweight regex pass for anchor tags.
enum HTMLLinkExtractor {

    static func extract(from text: String) -> [EmailLink] {
        var links: [EmailLink] = []
        var seen = Set<String>()

        // 1. Anchor tags  <a href="...">title</a>
        let anchorPattern = #"<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)<\/a>"#
        if let regex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let urlRange   = Range(match.range(at: 1), in: text),
                      let titleRange = Range(match.range(at: 2), in: text),
                      let url = URL(string: String(text[urlRange]))
                else { continue }
                let key = url.absoluteString
                guard !seen.contains(key), isAllowedScheme(url) else { continue }
                seen.insert(key)
                let title = stripTags(String(text[titleRange]))
                links.append(EmailLink(id: UUID(), title: title, url: url))
            }
        }

        // 2. Bare URLs in plain text via NSDataDetector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, range: range) { result, _, _ in
                guard let result, let url = result.url else { return }
                let key = url.absoluteString
                guard !seen.contains(key), isAllowedScheme(url) else { return }
                seen.insert(key)
                links.append(EmailLink(id: UUID(), title: url.host ?? url.absoluteString, url: url))
            }
        }

        return links
    }

    private static func isAllowedScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private static func stripTags(_ s: String) -> String {
        (try? NSRegularExpression(pattern: "<[^>]+>"))
            .flatMap { regex in
                regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            } ?? s
    }
}
