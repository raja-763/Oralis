import Foundation
import WebKit

/// Manages the shared WKWebView for the voice-controlled browser tab.
/// Stored on AppState so agent actions can drive navigation without
/// needing a direct reference to the view.
@MainActor
final class BrowserModel: NSObject, ObservableObject {

    let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return WKWebView(frame: .zero, configuration: config)
    }()

    @Published var title: String = ""
    @Published var currentURL: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var pageText: String = ""

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Navigation

    func navigate(to raw: String) {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { return }
        if !str.contains("://") {
            str = str.contains(".") ? "https://" + str : searchURL(for: str)
        }
        guard let url = URL(string: str) else { return }
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    func goBack()    { webView.goBack() }
    func goForward() { webView.goForward() }

    func scrollDown() {
        webView.evaluateJavaScript("window.scrollBy(0,400)", completionHandler: nil)
    }

    // MARK: - Page reading / form interaction

    func readPageText(completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("document.body.innerText ?? ''") { result, _ in
            completion(result as? String ?? "")
        }
    }

    func fillForm(fieldHint: String, value: String) {
        let hint = fieldHint.lowercased()
            .replacingOccurrences(of: "'", with: "\\'")
        let val  = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function(){
          var hint='\(hint)';
          var val='\(val)';
          var els=document.querySelectorAll('input,textarea,select');
          for(var el of els){
            var lbl=el.id?document.querySelector('label[for="'+el.id+'"]'):null;
            if((lbl&&lbl.textContent.toLowerCase().includes(hint))||
               (el.placeholder&&el.placeholder.toLowerCase().includes(hint))||
               (el.name&&el.name.toLowerCase().includes(hint))||
               (el.id&&el.id.toLowerCase().includes(hint))){
              el.value=val;
              el.dispatchEvent(new Event('input',{bubbles:true}));
              el.dispatchEvent(new Event('change',{bubbles:true}));
              return 'filled';
            }
          }
          return 'not found';
        })()
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func clickElement(text: String) {
        let t = text.lowercased()
            .replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function(){
          var t='\(t)';
          var els=document.querySelectorAll('a,button,input[type=submit],input[type=button],[role=button]');
          for(var el of els){
            var txt=(el.textContent||el.value||el.getAttribute('aria-label')||'').trim().toLowerCase();
            if(txt.includes(t)){el.click();return 'clicked';}
          }
          return 'not found';
        })()
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Private helpers

    private func searchURL(for query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "https://www.google.com/search?q=\(encoded)"
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {

    nonisolated func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        Task { @MainActor in isLoading = true }
    }

    nonisolated func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in
            isLoading = false
            title = wv.title ?? ""
            currentURL = wv.url
            canGoBack = wv.canGoBack
            canGoForward = wv.canGoForward

            wv.evaluateJavaScript("document.body.innerText ?? ''") { [weak self] result, _ in
                Task { @MainActor in
                    self?.pageText = result as? String ?? ""
                }
            }
        }
    }

    nonisolated func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        Task { @MainActor in isLoading = false }
    }

    nonisolated func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        Task { @MainActor in isLoading = false }
    }
}
