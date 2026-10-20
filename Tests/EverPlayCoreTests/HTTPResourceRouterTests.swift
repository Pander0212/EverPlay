import XCTest
@testable import EverPlayCore

final class HTTPResourceRouterTests: FixtureTestCase {
    var router: HTTPResourceRouter { .init(root: temporary, port: 49152, token: "test-token") }
    func request(_ target: String, method: String = "GET", extra: String = "", host: String = "127.0.0.1:49152") -> Data {
        Data("\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\n\(extra)\r\n".utf8)
    }
    override func setUpWithError() throws {
        try super.setUpWithError()
        try Data("0123456789".utf8).write(to: temporary.appendingPathComponent("index.html"))
    }
    func testHTMLResponseAndSecurityPolicy() throws {
        let response = try router.response(to: request("/test-token/index.html?v=1"))
        XCTAssertEqual(response.status, 200); XCTAssertEqual(response.count, 10)
        XCTAssertEqual(response.headers["Content-Type"], "text/html; charset=utf-8")
        XCTAssertTrue(response.headers["Content-Security-Policy"]!.contains("connect-src 'self'"))
        XCTAssertNil(response.headers["Access-Control-Allow-Origin"])
    }
    func testHeadAndMediaByteRanges() throws {
        XCTAssertTrue(try router.response(to: request("/test-token/index.html", method: "HEAD")).headOnly)
        for (range, offset, count) in [("bytes=2-5", 2, 4), ("bytes=-3", 7, 3), ("bytes=8-", 8, 2), ("bytes=0-50", 0, 10)] {
            let response = try router.response(to: request("/test-token/index.html", extra: "Range: \(range)\r\n"))
            XCTAssertEqual(response.status, 206); XCTAssertEqual(response.offset, UInt64(offset)); XCTAssertEqual(response.count, UInt64(count))
        }
    }
    func testInvalidRangesRejected() {
        for range in ["bytes=10-", "bytes=4-2", "bytes=0-1,4-5", "bytes=-0", "bytes=a-b"] {
            XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", extra: "Range: \(range)\r\n")))
        }
    }
    func testHostTokenAndTraversalBoundaries() {
        XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", host: "evil.example")))
        for path in ["/index.html", "/wrong/index.html", "/test-token/../index.html", "/test-token/%2e%2e/index.html", "/test-token/%2fetc/passwd", "/test-token/a%5cb"] {
            XCTAssertThrowsError(try router.response(to: request(path)), path)
        }
    }
    func testEncodedFileNamesAndNoDoubleDecode() throws {
        try Data().write(to: temporary.appendingPathComponent("my game.js"))
        XCTAssertEqual(try router.response(to: request("/test-token/my%20game.js")).headers["Content-Type"], "text/javascript; charset=utf-8")
        XCTAssertThrowsError(try router.response(to: request("/test-token/%252e%252e/index.html")))
    }
    func testSymlinkResourcesRejected() throws {
        try FileManager.default.createSymbolicLink(at: temporary.appendingPathComponent("linked.html"), withDestinationURL: temporary.appendingPathComponent("index.html"))
        XCTAssertThrowsError(try router.response(to: request("/test-token/linked.html")))
    }
    func testRequestSmugglingAndUnsupportedMethodsRejected() {
        XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", method: "POST")))
        XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", extra: "Host: evil.example\r\n")))
        XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", extra: "Transfer-Encoding: chunked\r\n")))
        XCTAssertThrowsError(try router.response(to: request("/test-token/index.html", extra: "Content-Length: 10\r\n")))
    }
    func testModuleJSONAndAudioMIMETypes() {
        XCTAssertEqual(HTTPResourceRouter.mimeType("mjs"), "text/javascript; charset=utf-8")
        XCTAssertEqual(HTTPResourceRouter.mimeType("json"), "application/json")
        XCTAssertEqual(HTTPResourceRouter.mimeType("m4a"), "audio/mp4")
        XCTAssertEqual(HTTPResourceRouter.mimeType("wasm"), "application/wasm")
    }
}
