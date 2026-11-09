import SwiftUI
import WebKit

/// Opens an external link in an embedded WebView with voice navigation support.
/// Users can navigate links, fill forms, and interact entirely by voice.
struct LinkReaderView: View {
    let url: URL
    @EnvironmentObject var appState: AppState
    @State private var pageTitle = ""
    @State private var isLoading = true
    @State private var webViewRef: WKWebView?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark")
                }
                .accessibilityLabel("Close link reader")

                Spacer()

                Text(pageTitle.isEmpty ? url.host ?? "" : pageTitle)
                    .lineLimit(1)
                    .accessibilityLabel("Page: \(pageTitle.isEmpty ? url.host ?? "" : pageTitle)")

                Spacer()

                Button {
                    readPageAloud()
                } label: {
                    Label("Read page", systemImage: "speaker.wave.2.fill")
                }
                .accessibilityLabel("Read this page aloud")
                .keyboardShortcut("R", modifiers: [.command, .option])

                Button {
                    webViewRef?.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityLabel("Go back")
                .keyboardShortcut("[", modifiers: .command)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))

            Divider()

            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading page")
            }

            AccessibleWebView(url: url, onLoad: { title, webView in
                pageTitle = title
                webViewRef = webView
                isLoading = false
            })
            .opacity(isLoading ? 0 : 1)
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("Link Reader")
    }

    private func readPageAloud() {
        guard let wv = webViewRef else { return }
        wv.evaluateJavaScript("document.body.innerText") { result, _ in
            guard let text = result as? String else { return }
            Task { @MainActor in
                appState.speech.speak(text)
            }
        }
    }
}

// MARK: - WKWebView wrapper with accessibility hooks

struct AccessibleWebView: NSViewRepresentable {
    let url: URL
    var onLoad: (String, WKWebView) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoad: (String, WKWebView) -> Void
        init(onLoad: @escaping (String, WKWebView) -> Void) { self.onLoad = onLoad }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoad(webView.title ?? "", webView)
        }
    }
}
