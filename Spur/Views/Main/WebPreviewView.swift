import SwiftUI
import WebKit

// MARK: - WebViewStore

/// Observable wrapper giving SwiftUI views access to the underlying WKWebView
/// for programmatic reload without triggering a full view reconstruction.
final class WebViewStore: ObservableObject {
    weak var webView: WKWebView?

    func reload() {
        if let webView, webView.url != nil {
            webView.reload()
        }
    }
}

// MARK: - WebPreviewView

struct WebPreviewView: NSViewRepresentable {
    let url: URL
    /// Shared store so the parent view can trigger reloads.
    @ObservedObject var store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Hand the live reference to the store so callers can reload
        store.webView = webView

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        webView.load(request)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only navigate when the URL actually changes (e.g., option switch)
        guard webView.url?.absoluteString != url.absoluteString else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        webView.load(request)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let store: WebViewStore

        init(store: WebViewStore) {
            self.store = store
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if store.webView == nil { store.webView = webView }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            // Silently ignore connection-refused errors while the server is starting up
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain &&
                (nsErr.code == NSURLErrorCannotConnectToHost ||
                 nsErr.code == NSURLErrorNetworkConnectionLost) {
                return
            }
        }
    }
}
