import SwiftUI
import WebKit
import OSLog
import EverPlayCore

@MainActor
final class GameSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var loading = true
    @Published var error: String?
    let webView: WKWebView
    private let server: LocalGameServer
    private let game: GameRecord
    private var started = false
    private var stopped = false
    private(set) var startedAt: Date?

    init(game: GameRecord, root: URL) {
        self.game = game
        server = LocalGameServer(root: root, game: game)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: game.id)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = false
    }

    func start() async {
        trace("start requested; started=\(started), stopped=\(stopped)")
        guard !started, !stopped else { return }
        started = true
        do {
            try await server.start()
            trace("loopback server ready")
            guard !stopped else { server.stop(); return }
            let base = URL(string: "http://127.0.0.1:\(game.port)/")!
            let url = base.appendingPathComponent(game.resourceToken).appendingPathComponent(game.entryPoint)
            startedAt = Date()
            trace("requesting game navigation")
            webView.load(URLRequest(url: url))
        } catch {
            self.error = "The game server could not start: \(error.localizedDescription). Close and reopen the game to retry."
            loading = false
        }
    }

    func stop() {
        trace("stop requested")
        guard !stopped else { return }
        stopped = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        server.stop()
    }

    func sendKey(_ key: String, pressed: Bool) {
        let mapping: [String: (String, Int)] = ["ArrowUp": ("ArrowUp", 38), "ArrowDown": ("ArrowDown", 40),
            "ArrowLeft": ("ArrowLeft", 37), "ArrowRight": ("ArrowRight", 39), "Enter": ("Enter", 13),
            "Escape": ("Escape", 27), "z": ("KeyZ", 90), "x": ("KeyX", 88)]
        guard let (code, number) = mapping[key] else { return }
        // Values come solely from the fixed allowlist, never game text or arbitrary UI input.
        let script = """
        (() => {
          const event = new KeyboardEvent('\(pressed ? "keydown" : "keyup")',
            {key:'\(key)', code:'\(code)', bubbles:true, cancelable:true, keyCode:\(number), which:\(number)});
          Object.defineProperty(event, 'keyCode', {get:()=>\(number)});
          Object.defineProperty(event, 'which', {get:()=>\(number)});
          (document.activeElement || document.body || document).dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.scheme == "http", url.host == "127.0.0.1",
              url.port == Int(game.port), url.path.hasPrefix("/\(game.resourceToken)/") else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { trace("navigation started") }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { trace("navigation finished"); loading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func trace(_ message: String) {
        #if DEBUG
        Logger(subsystem: "app.everplay.player", category: "runtime").notice("\(message, privacy: .public)")
        #endif
    }
    private func fail(_ error: Error) {
        trace("navigation error code \((error as NSError).code)")
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription; loading = false }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "The game process stopped. Exit and reopen the game. Previously saved browser data is retained."
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}

struct GameWebView: UIViewRepresentable {
    let session: GameSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
