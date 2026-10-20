import XCTest
import EverPlayCore
@testable import EverPlay

final class LocalGameServerTests: XCTestCase {
    func testRealHTTPTransportServesImportedGameAndRanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(root: root)
        let demo = try XCTUnwrap(Bundle.main.url(forResource: "EverPlayDemo", withExtension: "zip"))
        let game = try await library.importZIP(at: demo)
        let server = LocalGameServer(root: library.directory(for: game), game: game)
        try await server.start()
        defer { server.stop() }
        let base = URL(string: "http://127.0.0.1:\(game.port)/\(game.resourceToken)/LanternGarden/")!
        let (html, response) = try await URLSession.shared.data(from: base.appendingPathComponent("index.html"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains("Lantern Garden"))
        let (module, moduleResponse) = try await URLSession.shared.data(from: base.appendingPathComponent("game.js"))
        XCTAssertFalse(module.isEmpty)
        XCTAssertEqual((moduleResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "text/javascript; charset=utf-8")
        var request = URLRequest(url: base.appendingPathComponent("index.html"))
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        let (range, rangeResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((rangeResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(range, html.prefix(10))
        let (_, blocked) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(game.port)/wrong/index.html")!)
        XCTAssertEqual((blocked as? HTTPURLResponse)?.statusCode, 404)
    }
}
