import XCTest
import UIKit
import WebKit
import EverPlayCore
@testable import EverPlay

final class RenPyRuntimeTests: XCTestCase {
    @MainActor
    func testRenPyDesktopArchiveRunsAndRestoresSaveInWebKit() async throws {
        guard let fixture = Bundle.main.url(forResource: "EverPlayRenPyProbe", withExtension: "zip") else {
            throw XCTSkip("Optional RenPy experiment: run scripts/build-renpy-probe.py before generating the project")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LibraryStore(root: root)
        // Production ZIP validation, detection, library identity, HTTP server and WKWebView.
        let game = try await library.importZIP(at: fixture, title: "RenPy desktop-data probe")
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
        func present(_ session: GameSession) {
            session.webView.frame = window.bounds
            session.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.rootViewController!.view.addSubview(session.webView)
        }
        let first = GameSession(game: game, root: library.directory(for: game))
        sessions.append(first); present(first)
        await first.start()
        try await wait(first, for: "window.everplayProbe?.ready === true")
        try await wait(first, for: "window.everplayProbe.gold === 10")
        first.sendKey("z", pressed: true); first.sendKey("z", pressed: false)
        try await wait(first, for: "window.everplayProbe.gold === 20")
        first.sendKey("x", pressed: true); first.sendKey("x", pressed: false)
        try await wait(first, for: "window.everplayProbe.saved === true")
        first.sendKey("z", pressed: true); first.sendKey("z", pressed: false)
        try await wait(first, for: "window.everplayProbe.gold === 30")
        first.sendKey("Enter", pressed: true); first.sendKey("Enter", pressed: false)
        try await wait(first, for: "window.everplayProbe.gold === 20")
        let snapshot = try await first.webView.takeSnapshot(with: nil)
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "RenPy desktop archive running inside EverPlay WebKit"
        attachment.lifetime = .keepAlways; add(attachment)
        first.stop(); first.webView.removeFromSuperview()

        let reopened = GameSession(game: game, root: library.directory(for: game))
        sessions.append(reopened); present(reopened)
        await reopened.start()
        try await wait(reopened, for: "window.everplayProbe?.ready === true")
        try await wait(reopened, for: "window.everplayProbe.saved === true")
        reopened.sendKey("Enter", pressed: true); reopened.sendKey("Enter", pressed: false)
        try await wait(reopened, for: "window.everplayProbe.gold === 20")
    }

    @MainActor
    private func wait(_ session: GameSession, for expression: String) async throws {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline && session.error == nil {
            if !session.loading,
               (try? await session.webView.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail(session.error ?? "RenPy condition timed out: \(expression)")
        throw NSError(domain: "EverPlay.RenPyProbe", code: 1)
    }

}
