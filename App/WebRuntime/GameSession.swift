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
        if game.engine == .rpgMakerMV || game.engine == .rpgMakerMZ {
            // Shims first, before the game's plugins run; cheats once the page is loaded.
            var scripts = [("RPGMakerShims", WKUserScriptInjectionTime.atDocumentStart), ("RPGMakerCheats", .atDocumentEnd)]
            // Machine translation, when switched on for this game (game page › Translate).
            let translation = TranslationPreferences.settings
            if translation.provider != .off, TranslationPreferences.isEnabled(for: Self.translationKey(game)) {
                TranslationEngine.shared.start(game: Self.translationKey(game), settings: translation)
                configuration.userContentController.addScriptMessageHandler(TranslationBridge(), contentWorld: .page,
                                                                            name: "everplayTranslate")
                scripts.append(("RPGMakerTranslate", .atDocumentEnd))
            }
            for (name, time) in scripts {
                guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                      let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: time, forMainFrameOnly: true))
            }
        }
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
        TranslationEngine.shared.flush()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        server.stop()
    }

    func sendKey(_ key: String, pressed: Bool) {
        // Only keys from the fixed catalog, passed as JSON; never game text or free UI input.
        guard let entry = ControlKey.named(key),
              let names = try? JSONSerialization.data(withJSONObject: [entry.key, entry.code]) else { return }
        let number = entry.keyCode
        let script = """
        (() => {
          const [key, code] = \(String(decoding: names, as: UTF8.self));
          const event = new KeyboardEvent('\(pressed ? "keydown" : "keyup")',
            {key, code, bubbles:true, cancelable:true, keyCode:\(number), which:\(number)});
          Object.defineProperty(event, 'keyCode', {get:()=>\(number)});
          Object.defineProperty(event, 'which', {get:()=>\(number)});
          (document.activeElement || document.body || document).dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// The key a web game's translation setting and memory are stored under.
    static func translationKey(_ game: GameRecord) -> String { "web-\(game.id.uuidString)" }

    /// Shows the game's original text (true) or the translation again.
    func showOriginalText(_ on: Bool) {
        webView.evaluateJavaScript("window.__everplayTranslation && window.__everplayTranslation.setOriginal(\(on))",
                                   completionHandler: nil)
    }

    /// Methods of window.__everplayCheats (App/Resources/RPGMakerCheats.js) the cheat screen may call.
    static let cheatMethods: Set<String> = ["status", "addGold", "setGold", "heal", "levelUp", "setSpeed", "setThrough",
                                            "setNoEncounters", "variables", "setVariable", "switches", "setSwitch",
                                            "items", "gainItem"]

    /// Calls the RPG Maker cheat script with JSON-encoded arguments and decodes its JSON reply.
    func cheat<Result: Decodable>(_ method: String, _ arguments: [Any] = [], as type: Result.Type) async throws -> Result {
        guard Self.cheatMethods.contains(method) else { throw EverPlayError.invalidRequest }
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        let script = "JSON.stringify(window.__everplayCheats ? window.__everplayCheats.\(method).apply(null, \(encoded)) : null)"
        guard let reply = try await webView.evaluateJavaScript(script) as? String else { throw EverPlayError.invalidRequest }
        return try JSONDecoder().decode(Result.self, from: Data(reply.utf8))
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

/// Answers RPGMakerTranslate.js: a list of lines in, their translations out (the line itself when
/// none arrives in time). Waits off the main thread, where the requests finish too.
final class TranslationBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let lines = message.body as? [String], lines.count <= 100 else {
            replyHandler(nil, "Expected up to 100 lines of text")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let engine = TranslationEngine.shared
            engine.prefetch(lines)
            let results = lines.map { engine.translate($0, timeout: 6) ?? $0 }
            DispatchQueue.main.async { replyHandler(results, nil) }
        }
    }
}
