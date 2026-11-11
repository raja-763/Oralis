import SwiftUI
import WebKit

/// Voice-controlled in-app web browser.
/// The agent can navigate, read pages, fill forms, and click elements by voice.
struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlText: String = ""

    private var browser: BrowserModel { appState.browser }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            if browser.currentURL != nil {
                BrowserWebView(webView: browser.webView)
                    .overlay(loadingOverlay, alignment: .top)
            } else {
                browserWelcome
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: browser.currentURL) { _, url in
            urlText = url?.absoluteString ?? ""
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Go back")
            }
            .disabled(!browser.canGoBack)
            .buttonStyle(.borderless)

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Go forward")
            }
            .disabled(!browser.canGoForward)
            .buttonStyle(.borderless)

            TextField("Say or type a web address…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Address bar — type a URL or search term")
                .onSubmit {
                    browser.navigate(to: urlText)
                }

            Button {
                browser.navigate(to: urlText)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .accessibilityLabel("Go")
            }
            .buttonStyle(.borderless)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Loading overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if browser.isLoading {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(height: 2)
        }
    }

    // MARK: - Welcome / empty state

    private var browserWelcome: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Voice Web Browser")
                        .font(.title3.weight(.semibold))
                    Text("Navigate, read pages, and fill forms entirely by voice.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try saying:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    SuggestionChip("Go to google.com")
                    SuggestionChip("Read this page")
                    SuggestionChip("Fill in my name")
                    SuggestionChip("Click the submit button")
                    SuggestionChip("Scroll down")
                    SuggestionChip("Go back")
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - WKWebView wrapper

struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
