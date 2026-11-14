import AppKit
import WebKit

/// Follows an unsubscribe link and clicks through it entirely in the background, in a hidden
/// page that is never shown. It confirms (or opts out of everything) when the page asks, then
/// reads the result so Oralis can say honestly whether it worked.
@MainActor
final class UnsubscribeBrowser: NSObject, WKNavigationDelegate {

    enum Outcome {
        case confirmed                  // the page said the person is unsubscribed
        case clicked(String)            // clicked through, but the page did not clearly confirm
        case noAction(String)           // nothing to click and no confirmation
    }

    private let webView: WKWebView
    private let window: NSWindow
    private var loading = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()      // no cookies or history are kept
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: config)
        // A real (but never visible) window keeps the page's scripts running normally.
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1100, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func run(_ url: URL) async -> Outcome {
        window.orderBack(nil)
        defer { window.close(); webView.stopLoading() }

        loading = true
        webView.load(URLRequest(url: url, timeoutInterval: 25))
        await waitUntilLoaded(timeout: 25)

        var clicked = false
        var lastClick = ""
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)       // let the page's scripts render
            if Self.looksUnsubscribed(await pageText()) { return .confirmed }
            let result = await evaluate(Self.clickScript)
            guard result.hasPrefix("clicked:") else { break }
            clicked = true
            lastClick = String(result.dropFirst(8))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await waitUntilLoaded(timeout: 12)
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let finalText = await pageText()
        if Self.looksUnsubscribed(finalText) { return .confirmed }
        let summary = Self.summary(of: finalText)
        oralisLog("unsubscribe: page did not clearly confirm (clicked \(clicked ? "'" + lastClick + "'" : "nothing"))")
        return clicked ? .clicked(summary) : .noAction(summary)
    }

    // MARK: - Page helpers

    private func pageText() async -> String {
        await evaluate("document.body ? document.body.innerText : ''")
    }

    private func evaluate(_ js: String) async -> String {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
    }

    private func waitUntilLoaded(timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        try? await Task.sleep(nanoseconds: 300_000_000)
        while loading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        Task { @MainActor in self.loading = true }
    }
    nonisolated func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in self.loading = false }
    }
    nonisolated func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        Task { @MainActor in self.loading = false }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        Task { @MainActor in self.loading = false }
    }

    // MARK: - Reading the result

    nonisolated private static let successPhrases = [
        "you have been unsubscribed", "you've been unsubscribed", "you are unsubscribed",
        "you are now unsubscribed", "successfully unsubscribed", "unsubscribed successfully",
        "you have successfully unsubscribed", "you've unsubscribed", "you have unsubscribed",
        "been removed from", "no longer receive", "will not receive", "won't receive",
        "will no longer", "preferences have been updated", "preferences updated",
        "preferences saved", "we've removed", "we have removed", "opted out",
        "unsubscribe request", "subscription has been", "subscription was", "you're unsubscribed",
        "has been unsubscribed", "unsubscribed from",
    ]

    nonisolated static func looksUnsubscribed(_ text: String) -> Bool {
        let t = text.lowercased()
        return successPhrases.contains { t.contains($0) }
    }

    private static func summary(of text: String) -> String {
        let flat = text.split(whereSeparator: { $0.isNewline || $0.isWhitespace }).joined(separator: " ")
        return String(flat.prefix(140))
    }

    /// Chooses "unsubscribe from all" style options, then clicks the best unsubscribe or
    /// confirm control. Returns "clicked:<label>" or "none".
    private static let clickScript = """
    (function(){
      document.querySelectorAll('input[type=radio],input[type=checkbox]').forEach(function(i){
        var l=((i.labels&&i.labels[0]?i.labels[0].textContent:'')+' '+(i.value||'')+' '+(i.getAttribute('aria-label')||'')).toLowerCase();
        if(/unsubscribe( me)? from (all|every)|all (marketing |promotional )?(emails|email)|opt.?out of all|do not (send|email)|stop (all )?emails/.test(l)&&!i.checked){ try{i.click();}catch(e){} }
      });
      var rules=[
        [/confirm.*unsubscribe|unsubscribe.*confirm|yes.*unsubscribe|unsubscribe.*yes/,100],
        [/unsubscribe (me )?from (all|every)|unsubscribe (me|all)\\b/,95],
        [/^unsubscribe$/,90],
        [/unsubscribe/,80],
        [/opt.?out|stop (sending|emails)|remove me/,75],
        [/^confirm|confirm$/,60],
        [/update (my )?preferences|save (my )?(preferences|changes)|^submit$|^continue$|^yes$/,45]
      ];
      var bad=/cancel|resubscribe|re-subscribe|stay subscribed|keep (me|sending)|no,? thanks|not now|go back|sign in|log ?in|privacy|terms/;
      var best=null,score=0,label='';
      document.querySelectorAll('a,button,input[type=submit],input[type=button],[role=button]').forEach(function(el){
        var t=(el.innerText||el.value||el.getAttribute('aria-label')||'').trim().toLowerCase();
        if(!t||t.length>90||bad.test(t)) return;
        for(var k=0;k<rules.length;k++){
          if(rules[k][0].test(t)){ if(rules[k][1]>score){score=rules[k][1];best=el;label=t;} break; }
        }
      });
      if(best&&score>=45){ best.click(); return 'clicked:'+label; }
      return 'none';
    })()
    """
}
