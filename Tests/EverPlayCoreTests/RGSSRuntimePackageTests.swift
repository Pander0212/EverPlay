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
        let cheats = temporary.appendingPathComponent("EverPlayRGSS.rb")
        let soundFont = temporary.appendingPathComponent("TimGM6mb.sf2")
        XCTAssertEqual(try RGSSRuntimePackage.configure(gameFolder: game, root: root, preloadScripts: [cheats], soundFont: soundFont), [])
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: game.appendingPathComponent("mkxp.json"))) as? [String: Any]
        XCTAssertEqual(config?["preloadScript"] as? [String], [cheats.path])
        XCTAssertEqual(config?["midiSoundFont"] as? String, soundFont.path)
        XCTAssertEqual(config?["RTP"] as? [String], [root.appendingPathComponent("RPGVXAce", isDirectory: true).path])
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

final class RGSSSavesTests: FixtureTestCase {
    func testMirrorsOnlySavesBothWays() throws {
        let game = temporary.appendingPathComponent("Game"), saves = temporary.appendingPathComponent("Saves")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data([1]).write(to: game.appendingPathComponent("Save01.rvdata2"))
        try Data([9]).write(to: game.appendingPathComponent("Game.ini"))

        // First start: the game's saves seed the visible folder.
        try RGSSSaves.prepare(gameFolder: game, saveFolder: saves)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: saves.path), ["Save01.rvdata2"])

        // The player deletes it in Files and adds another: the game gets exactly that.
        try FileManager.default.removeItem(at: saves.appendingPathComponent("Save01.rvdata2"))
        try Data([2]).write(to: saves.appendingPathComponent("Save02.rvdata2"))
        try RGSSSaves.prepare(gameFolder: game, saveFolder: saves)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: game.path)), ["Game.ini", "Save02.rvdata2"])

        // The game saves: collected back.
        try Data([3]).write(to: game.appendingPathComponent("Save02.rvdata2"))
        try Data([4]).write(to: game.appendingPathComponent("Save3.rxdata"))
        try RGSSSaves.collect(gameFolder: game, saveFolder: saves)
        XCTAssertEqual(try Data(contentsOf: saves.appendingPathComponent("Save02.rvdata2")), Data([3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saves.appendingPathComponent("Save3.rxdata").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saves.appendingPathComponent("Game.ini").path))
    }
}
