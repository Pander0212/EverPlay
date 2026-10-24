import XCTest
@testable import EverPlayCore

final class RGSSRuntimePackageTests: FixtureTestCase {
    func testReadsRTPNamesFromTheGameSection() {
        XCTAssertEqual(RGSSRuntimePackage.names(gameIni: "[Game]\r\nRTP=RPGVXAce\r\nLibrary=System\\RGSS301.dll\r\n"), ["RPGVXAce"])
        XCTAssertEqual(RGSSRuntimePackage.names(gameIni: "[Game]\nRTP1=Standard\nRTP2=\nRTP3=Standard\n[Other]\nRTP=X"), ["Standard"])
        XCTAssertEqual(RGSSRuntimePackage.names(gameIni: "[Game]\nTitle=No RTP\n"), [])
    }

    func testRejectsUnsafeFolderNames() {
        XCTAssertNil(RGSSRuntimePackage.folder("../..", in: temporary))
        XCTAssertEqual(RGSSRuntimePackage.folder("RPGVXAce", in: temporary)?.lastPathComponent, "RPGVXAce")
    }

    func testInstallsTheFolderWithGraphicsAndConfiguresTheGame() throws {
        let root = temporary.appendingPathComponent("RTP")
        let package = try zip([("RTP/RPGVXAce/Graphics/System/Window.png", Data([1])),
                               ("RTP/RPGVXAce/Audio/SE/Cursor1.ogg", Data([2]))])
        try RGSSRuntimePackage.install(package: package, name: "RPGVXAce", into: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RPGVXAce/Graphics/System/Window.png").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["RPGVXAce"])

        let game = temporary.appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("[Game]\nRTP=RPGVXAce\n".utf8).write(to: game.appendingPathComponent("Game.ini"))
        XCTAssertEqual(try RGSSRuntimePackage.configure(gameFolder: game, root: root), [])
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: game.appendingPathComponent("mkxp.json"))) as? [String: [String]]
        XCTAssertEqual(config?["RTP"], [root.appendingPathComponent("RPGVXAce", isDirectory: true).path])
    }

    func testKeepsTheGamesOwnConfigAndRejectsOtherZips() throws {
        let game = temporary.appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("[Game]\nRTP=RPGVX\n".utf8).write(to: game.appendingPathComponent("Game.ini"))
        try Data("{\"fullscreen\": true}".utf8).write(to: game.appendingPathComponent("mkxp.json"))
        XCTAssertEqual(try RGSSRuntimePackage.configure(gameFolder: game, root: temporary.appendingPathComponent("RTP")), ["RPGVX"])
        XCTAssertEqual(try String(contentsOf: game.appendingPathComponent("mkxp.json"), encoding: .utf8), "{\"fullscreen\": true}")
        XCTAssertThrowsError(try RGSSRuntimePackage.install(package: try zip([("readme.txt", Data([1]))]), name: "RPGVX",
                                                            into: temporary.appendingPathComponent("RTP")))
    }

    /// Installs the official downloads named in EVERPLAY_RTP_TEST ("name=file;…"), which are not in the repository.
    func testInstallsOfficialPackagesFromTheEnvironment() throws {
        guard let list = ProcessInfo.processInfo.environment["EVERPLAY_RTP_TEST"] else { throw XCTSkip("EVERPLAY_RTP_TEST not set") }
        let root = temporary.appendingPathComponent("RTP")
        for pair in list.split(separator: ";") {
            let parts = pair.split(separator: "=").map(String.init)
            try RGSSRuntimePackage.install(package: URL(fileURLWithPath: parts[1]), name: parts[0], into: root)
            let graphics = root.appendingPathComponent(parts[0]).appendingPathComponent("Graphics")
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: graphics.path).isEmpty, parts[0])
        }
        XCTAssertNotNil(RGSSRuntimePackage.officialDownload(for: "RPGVXAce"))
    }
}
