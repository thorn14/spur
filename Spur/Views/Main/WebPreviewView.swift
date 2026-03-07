import SwiftUI
import WebKit

// TODO: [Phase 4] Implement WebPreviewView — WKWebView loading http://localhost:<port>.
// Disable caching. Add reload-on-demand. See agents.md Prompt 7.

struct WebPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Cache disabled for live preview freshness
        config.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        webView.load(request)
    }
}
