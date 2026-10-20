import XCTest
import EverPlayCore
@testable import EverPlay

final class GameSessionTests: XCTestCase {
    @MainActor
    func testGameStorageIsolationAndSessionReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LibraryStore(root: root)
        let demo = try XCTUnwrap(Bundle.main.url(forResource: "EverPlayDemo", withExtension: "zip"))
        let first = try await library.importZIP(at: demo)
        // Reuse original fixture bytes under a second persisted game identity. No copyrighted engine is needed.
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        fields["id"] = UUID().uuidString
        fields["resourceToken"] = UUID().uuidString
        fields["port"] = Int(first.port) + 1
        let second = try JSONDecoder().decode(GameRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        var sessions: [GameSession] = []
        defer {
            sessions.forEach { $0.stop() }
            try? FileManager.default.removeItem(at: root)
        }
        let gameRoot = library.directory(for: first)
        let a = GameSession(game: first, root: gameRoot)
        sessions.append(a)
        try await load(a)
        let before = try await a.webView.evaluateJavaScript("Number(document.querySelector('#gold').value)")
        a.sendKey("z", pressed: true)
        a.sendKey("z", pressed: false)
        let after = try await a.webView.evaluateJavaScript("Number(document.querySelector('#gold').value)")
        XCTAssertEqual((after as? NSNumber)?.intValue, ((before as? NSNumber)?.intValue ?? -100) + 10,
                       "Production virtual-key injection must reach the actual game input handler")
        _ = try await a.webView.evaluateJavaScript("localStorage.setItem('everplay-isolation-check', 'game-a')")
        a.stop()

        let b = GameSession(game: second, root: gameRoot)
        sessions.append(b)
        try await load(b)
        let initiallyEmpty = try await b.webView.evaluateJavaScript("localStorage.getItem('everplay-isolation-check') === null")
        XCTAssertEqual(initiallyEmpty as? Bool, true, "A different game must not inherit another game's saves")
        _ = try await b.webView.evaluateJavaScript("localStorage.setItem('everplay-isolation-check', 'game-b')")
        b.stop()

        let reopened = GameSession(game: first, root: gameRoot)
        sessions.append(reopened)
        try await load(reopened)
        let saved = try await reopened.webView.evaluateJavaScript("localStorage.getItem('everplay-isolation-check')")
        XCTAssertEqual(saved as? String, "game-a", "Reopening must keep the first game's data and origin")
        let dialogue = try await reopened.webView.evaluateJavaScript("document.querySelector('[data-translate]').textContent")
        XCTAssertTrue((dialogue as? String)?.contains("こんばんは") == true, "Module JavaScript and JSON must actually execute in WKWebView")
    }

    @MainActor
    private func load(_ session: GameSession) async throws {
        await session.start()
        let deadline = Date().addingTimeInterval(20)
        while session.error == nil && Date() < deadline {
            if !session.loading {
                let ready = try await session.webView.evaluateJavaScript("document.body?.dataset.ready === 'true'")
                if ready as? Bool == true { return }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail(session.error ?? "The demo's module/JSON readiness marker did not appear")
        throw NSError(domain: "EverPlay.GameSessionTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: session.error ?? "WKWebView readiness timed out"])
    }
}
