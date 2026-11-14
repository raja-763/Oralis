import Foundation
import WebKit

/// The page Oralis opens only when asked to fill in a web form. It is not a web browser:
/// there is no address bar, no history and no general navigation. Oralis opens the page the
/// user names, lists its form fields, fills them in and clicks through the form.
@MainActor
final class BrowserModel: NSObject, ObservableObject {

    let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return WKWebView(frame: .zero, configuration: config)
    }()

    @Published var currentURL: URL?
    @Published var isLoading: Bool = false
    /// The form fields and buttons on the open page, which is all the AI is told about it.
    @Published var formSummary: String = ""

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Opening the form page

    /// Opens a web address so its form can be filled in. Only http and https addresses work.
    @discardableResult
    func openForm(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return false }
        currentURL = url
        formSummary = ""
        isLoading = true
        webView.load(URLRequest(url: url))
        return true
    }

    func waitUntilLoaded(timeout: Double = 25) async {
        let deadline = Date().addingTimeInterval(timeout)
        try? await Task.sleep(nanoseconds: 400_000_000)
        while isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 800_000_000)   // let the form's scripts finish
    }

    // MARK: - Form interaction

    /// Lists the fields and buttons of the form, in words that can be read aloud.
    func refreshFormSummary() async -> String {
        let json = await evaluate("""
        (function(){
          var fields=[];
          document.querySelectorAll('input,textarea,select').forEach(function(el){
            var type=(el.type||el.tagName).toLowerCase();
            if(['hidden','submit','button','image','reset'].indexOf(type)>=0) return;
            var lbl='';
            if(el.id){var l=document.querySelector('label[for="'+el.id+'"]'); if(l) lbl=l.innerText;}
            if(!lbl&&el.closest&&el.closest('label')) lbl=el.closest('label').innerText;
            lbl=(lbl||el.getAttribute('aria-label')||el.placeholder||el.name||el.id||'').trim().replace(/\\s+/g,' ');
            if(!lbl) return;
            fields.push(lbl.slice(0,60)+(el.required?' (required)':''));
          });
          var buttons=[].slice.call(document.querySelectorAll('button,input[type=submit],input[type=button]'))
            .map(function(b){return (b.innerText||b.value||'').trim();})
            .filter(function(t){return t&&t.length<40;}).slice(0,6);
          return JSON.stringify({fields:fields.slice(0,25),buttons:buttons});
        })()
        """)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
              let fields = object["fields"], !fields.isEmpty
        else { formSummary = ""; return "" }
        let buttons = object["buttons"] ?? []
        var summary = "Form fields: " + fields.joined(separator: "; ") + "."
        if !buttons.isEmpty { summary += " Buttons: " + buttons.joined(separator: ", ") + "." }
        formSummary = summary
        return summary
    }

    /// Fills the field whose label, placeholder or name matches the hint. True if one was found.
    func fillField(hint: String, value: String) async -> Bool {
        let h = Self.jsString(hint.lowercased())
        let v = Self.jsString(value)
        let result = await evaluate("""
        (function(){
          var hint=\(h), val=\(v);
          var els=document.querySelectorAll('input,textarea,select');
          for(var i=0;i<els.length;i++){
            var el=els[i];
            var type=(el.type||'').toLowerCase();
            if(['hidden','submit','button','image','reset'].indexOf(type)>=0) continue;
            var lbl=el.id?document.querySelector('label[for="'+el.id+'"]'):null;
            var text=[(lbl?lbl.textContent:''),el.placeholder,el.name,el.id,el.getAttribute('aria-label')].join(' ').toLowerCase();
            if(text.indexOf(hint)<0) continue;
            if(el.tagName==='SELECT'){
              for(var j=0;j<el.options.length;j++){
                if(el.options[j].text.toLowerCase().indexOf(val.toLowerCase())>=0){el.selectedIndex=j;break;}
              }
            } else if(type==='checkbox'||type==='radio'){
              el.checked=!/^(no|false|off|uncheck)/i.test(val);
            } else { el.value=val; }
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
            return 'filled';
          }
          return 'not found';
        })()
        """)
        return result == "filled"
    }

    /// Clicks the button or link whose text matches. True if one was found.
    func click(text: String) async -> Bool {
        let t = Self.jsString(text.lowercased())
        let result = await evaluate("""
        (function(){
          var t=\(t);
          var els=document.querySelectorAll('a,button,input[type=submit],input[type=button],[role=button]');
          for(var i=0;i<els.length;i++){
            var el=els[i];
            var txt=(el.innerText||el.value||el.getAttribute('aria-label')||'').trim().toLowerCase();
            if(txt.indexOf(t)>=0){el.click();return 'clicked';}
          }
          return 'not found';
        })()
        """)
        return result == "clicked"
    }

    // MARK: - Helpers

    private func evaluate(_ js: String) async -> String {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
    }

    /// A JavaScript string literal for the text.
    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
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
            currentURL = wv.url
        }
    }

    nonisolated func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        Task { @MainActor in isLoading = false }
    }

    nonisolated func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        Task { @MainActor in isLoading = false }
    }
}
