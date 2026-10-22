import XCTest
import UIKit
import WebKit
import EverPlayCore
@testable import EverPlay

/// A real, owner-supplied Ren'Py desktop game assembled by scripts/assemble-renpy-desktop-data.py.
/// It is only bundled by private CI; everywhere else this test skips. Mirrors
/// scripts/test-renpy-desktop-game-browser.mjs: input uses only EverPlay's virtual keys and
/// state is read through the runtime's own renpy_get() with read-only expressions.
/// Assertions and failure messages contain statement positions and counts, never game text.
final class RenPyDesktopGameTests: XCTestCase {
    private struct Position: Equatable, CustomStringConvertible {
        let file: String, line: Int, history: Int
        init?(_ value: Any) {
            guard let parts = value as? [Any], parts.count == 3, let file = parts[0] as? String,
                  let line = (parts[1] as? NSNumber)?.intValue,
                  let history = (parts[2] as? NSNumber)?.intValue else { return nil }
            self.file = file; self.line = line; self.history = history
        }
        var description: String { "\(file):\(line) history \(history)" }
    }

    private static let focusExpression = "(lambda f: [] if f is None else [(type(a).__name__, str(getattr(a, 'name', '')), str(getattr(a, 'screen', '')), str(getattr(a, 'value', ''))) for a in (f.action if isinstance(getattr(f, 'action', None), list) else [getattr(f, 'action', None)])])(renpy.display.focus.get_focused())"
    private static let screensExpression = "[n for n in ('langset', 'main_menu', 'say', 'save', 'load', 'confirm') if renpy.get_screen(n)]"
    private static let positionExpression = "list(renpy.get_filename_line()) + [len(_history_list)]"

    @MainActor
    func testRealDesktopGameRunsSavesAndRestoresInWebKit() async throws {
        guard let bundle = Bundle.main.url(forResource: "EverPlayRenPyDesktopGame", withExtension: "zip") else {
            throw XCTSkip("Private real-game test: no assembled desktop game is bundled")
        }
        var language = "ger"
        if let configuration = Bundle.main.url(forResource: "EverPlayRenPyDesktopGame", withExtension: "json"),
           let object = try JSONSerialization.jsonObject(with: Data(contentsOf: configuration)) as? [String: Any],
           let configured = object["language"] as? String {
            language = configured
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LibraryStore(root: root)
        // Production ZIP validation, detection, library identity, HTTP server and WKWebView.
        let game = try await library.importZIP(at: bundle, title: "Ren'Py desktop game")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        var sessions: [GameSession] = []
        defer {
            sessions.forEach { $0.stop(); $0.webView.removeFromSuperview() }
            window.isHidden = true
            try? FileManager.default.removeItem(at: root)
        }
        func open() async -> GameSession {
            let session = GameSession(game: game, root: library.directory(for: game))
            sessions.append(session)
            session.webView.frame = window.bounds
            session.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.rootViewController!.view.addSubview(session.webView)
            await session.start()
            return session
        }
        let started = Date()
        func mark(_ event: String, _ position: Position) {
            print("RenPy desktop game: \(event) at \(position) after \(Int(Date().timeIntervalSince(started))) s")
        }

        // First launch: the game's own language picker and its confirmation button.
        var session = await open()
        _ = try await until(session, Self.screensExpression, "language picker", timeout: 180) {
            ($0 as? [String])?.contains("langset") == true
        }
        try await focus(session, "language button", hint: repeated("ArrowRight", 8)) { $0[0] == "SetScreenVariable" && $0[3] == language }
        try await press(session, "Enter")
        try await focus(session, "language confirmation", hint: repeated("ArrowDown", 8)) { $0[0] == "Language" }
        try await press(session, "Enter")
        _ = try await until(session, "_preferences.language", "language preference") { $0 as? String == language }
        // Title-menu buttons animate in; they are only usable once focusable.
        _ = try await until(session, Self.screensExpression, "title menu") { ($0 as? [String])?.contains("main_menu") == true }
        try await focus(session, "start button", hint: repeated("ArrowRight", 5) + repeated("ArrowLeft", 5)) { $0[0] == "Start" }
        try await press(session, "Enter")
        var position = try await waitForPosition(session, "first dialogue") { $0.history >= 1 }
        position = try await advance(session, from: position)
        position = try await advance(session, from: position)
        mark("before save", position)

        try await press(session, "Escape")
        _ = try await until(session, Self.screensExpression, "save screen") { ($0 as? [String])?.contains("save") == true }
        try await focus(session, "save slot", hint: repeated("ArrowDown", 3)) { $0[0] == "FileSave" }
        try await press(session, "Enter")
        _ = try await until(session, "len(renpy.list_saved_games(fast=True))", "save file") { ($0 as? NSNumber)?.intValue == 1 }
        try await press(session, "Escape")
        _ = try await until(session, Self.screensExpression, "return to dialogue") {
            guard let screens = $0 as? [String] else { return false }
            return screens.contains("say") && !screens.contains("save")
        }
        let afterSave = Position(try await get(session, Self.positionExpression))
        XCTAssertEqual(afterSave, position, "Saving changed the dialogue position")
        let saved = position
        position = try await advance(session, from: position)
        position = try await advance(session, from: position)
        mark("progressed", position)
        try await attachSnapshot(of: session, name: "Real Ren'Py desktop game after saving")

        // Close the session and reopen the same library game; its WebKit storage must persist.
        session.stop(); session.webView.removeFromSuperview()
        session = await open()
        _ = try await until(session, Self.screensExpression, "title menu after reopen", timeout: 180) {
            ($0 as? [String])?.contains("main_menu") == true
        }
        let restoredLanguage = try await get(session, "_preferences.language") as? String
        XCTAssertEqual(restoredLanguage, language, "Language preference was not restored")
        try await focus(session, "load menu button", hint: repeated("ArrowRight", 5) + repeated("ArrowLeft", 5)) {
            $0[0] == "ShowMenu" && $0[2] == "load"
        }
        try await press(session, "Enter")
        _ = try await until(session, Self.screensExpression, "load screen") { ($0 as? [String])?.contains("load") == true }
        try await focus(session, "saved slot", hint: repeated("ArrowDown", 3)) { $0[0] == "FileLoad" }
        try await press(session, "Enter")
        position = try await waitForPosition(session, "restored dialogue") { $0 == saved }
        mark("restored after reopen", position)

        // Play on, then load the same save from inside the running game.
        position = try await advance(session, from: position)
        try await press(session, "Escape")
        _ = try await until(session, Self.screensExpression, "game menu") { ($0 as? [String])?.contains("save") == true }
        try await focus(session, "load tab", hint: repeated("ArrowDown", 4) + repeated("ArrowLeft", 12) + repeated("ArrowUp", 8)) {
            $0[0] == "ShowMenu" && $0[2] == "load"
        }
        try await press(session, "Enter")
        _ = try await until(session, Self.screensExpression, "load screen in game") { ($0 as? [String])?.contains("load") == true }
        try await focus(session, "saved slot in game", hint: repeated("ArrowRight", 3) + repeated("ArrowDown", 3)) { $0[0] == "FileLoad" }
        try await press(session, "Enter")
        let afterLoad = try await until(session, Self.screensExpression, "load confirmation") {
            guard let names = $0 as? [String] else { return false }
            return names.contains("confirm") || names.contains("say")
        }
        if (afterLoad as? [String])?.contains("confirm") == true {
            try await focus(session, "confirm yes", hint: ["ArrowDown"]) { $0[0] == "FileLoad" }
            try await press(session, "Enter")
        }
        position = try await waitForPosition(session, "restored dialogue in game") { $0 == saved }
        mark("restored in game", position)
        try await attachSnapshot(of: session, name: "Real Ren'Py desktop game restored from its save")
    }

    private func repeated(_ key: String, _ count: Int) -> [String] { Array(repeating: key, count: count) }

    // Same path as the on-screen controls: GameSession.sendKey.
    @MainActor
    private func press(_ session: GameSession, _ key: String) async throws {
        session.sendKey(key, pressed: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        session.sendKey(key, pressed: false)
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    /// Evaluates a read-only Python expression with the runtime's renpy_get() and returns its JSON value.
    @MainActor
    private func get(_ session: GameSession, _ expression: String) async throws -> Any {
        let literal = String(data: try JSONSerialization.data(withJSONObject: [expression]), encoding: .utf8)!
        let request = """
        (() => {
          if (typeof window.renpy_get !== 'function') return false;
          const slot = window.__everplayRenPyGet = {state: 'pending'};
          Promise.race([window.renpy_get(\(literal)[0]),
            new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 5000))])
            .then(value => { slot.state = 'done'; slot.value = JSON.stringify([value]); },
                  () => { slot.state = 'failed'; });
          return true;
        })()
        """
        guard (try await session.webView.evaluateJavaScript(request)) as? Bool == true else {
            throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 2, userInfo: [NSLocalizedDescriptionKey: "Runtime not ready"])
        }
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 50_000_000)
            let state = try await session.webView.evaluateJavaScript("window.__everplayRenPyGet.state") as? String
            if state == "done", let json = try await session.webView.evaluateJavaScript("window.__everplayRenPyGet.value") as? String,
               let wrapped = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any], let value = wrapped.first {
                return value
            }
            if state != "pending" { break }
        }
        throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 3, userInfo: [NSLocalizedDescriptionKey: "renpy_get failed"])
    }

    @MainActor
    private func until(_ session: GameSession, _ expression: String, _ label: String, timeout: TimeInterval = 120,
                       _ predicate: (Any) -> Bool) async throws -> Any {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && session.error == nil {
            if !session.loading, let value = try? await get(session, expression), predicate(value) { return value }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail(session.error ?? "Ren'Py desktop game timed out waiting for \(label)")
        throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 1)
    }

    @MainActor
    private func waitForPosition(_ session: GameSession, _ label: String,
                                 _ predicate: (Position) -> Bool) async throws -> Position {
        let value = try await until(session, Self.positionExpression, label, timeout: 60) {
            Position($0).map(predicate) ?? false
        }
        guard let position = Position(value) else { throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 6) }
        return position
    }

    /// Moves focus with virtual arrows until a focused button carries a matching action. Tries the expected
    /// moves first; Ren'Py's spatial navigation is not symmetric, so the fallback is a vertical pass and
    /// then a snake from the top that enters rows from both edges.
    @MainActor
    private func focus(_ session: GameSession, _ label: String, hint: [String],
                       _ matches: ([String]) -> Bool) async throws {
        func focused() async throws -> Bool {
            let actions = (try await get(session, Self.focusExpression) as? [[Any]]) ?? []
            return actions.contains { action in
                let fields = action.map { "\($0)" }
                return fields.count == 4 && matches(fields)
            }
        }
        if try await focused() { return }
        var moves = hint + repeated("ArrowDown", 8) + repeated("ArrowUp", 16)
        for row in 0..<10 { moves += repeated(row % 2 == 0 ? "ArrowRight" : "ArrowLeft", 6) + ["ArrowDown"] }
        moves += repeated("ArrowLeft", 6) + repeated("ArrowUp", 16)
        for move in moves {
            try await press(session, move)
            if try await focused() { return }
        }
        XCTFail("Could not focus \(label)")
        throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 4)
    }

    /// One Enter may only finish the text animation; press until a new line is shown.
    @MainActor
    private func advance(_ session: GameSession, from: Position) async throws -> Position {
        for _ in 0..<20 {
            try await press(session, "Enter")
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline {
                if let position = Position(try await get(session, Self.positionExpression)),
                   position.history > from.history, position.file != from.file || position.line != from.line {
                    return position
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        XCTFail("Dialogue did not advance from \(from)")
        throw NSError(domain: "EverPlay.RenPyDesktopGame", code: 5)
    }

    @MainActor
    private func attachSnapshot(of session: GameSession, name: String) async throws {
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            session.webView.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? NSError(domain: "EverPlay.RenPySnapshot", code: 1)) }
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
