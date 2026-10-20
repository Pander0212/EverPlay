import XCTest
import ZIPFoundation
@testable import EverPlayCore

class FixtureTestCase: XCTestCase {
    var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    func zip(_ files: [(String, Data)], name: String = UUID().uuidString, type: Entry.EntryType = .file,
             compressed: Bool = false) throws -> URL {
        let url = temporary.appendingPathComponent(name + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count),
                                 compressionMethod: compressed ? .deflate : .none) { offset, count in
                data.subdata(in: Int(offset)..<(Int(offset) + count))
            }
        }
        return url
    }
    func prepare(_ files: [(String, Data)], limits: ImportLimits = .init()) throws -> PreparedGame {
        try GameImporter(limits: limits).prepare(zip: zip(files), stagingParent: temporary.appendingPathComponent("staging"))
    }
    let html = Data("<!doctype html><title>Test</title>".utf8)
}

final class ImporterTests: FixtureTestCase {
    func testBundledDemoZIPImportsAndServesModuleAndJSON() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let zip = project.appendingPathComponent("App/Resources/EverPlayDemo.zip")
        let game = try GameImporter().prepare(zip: zip, stagingParent: temporary.appendingPathComponent("staging"))
        XCTAssertEqual(game.validation.entryPoint, "LanternGarden/index.html")
        let router = HTTPResourceRouter(root: game.directory, port: 49152, token: "demo")
        for (path, mime) in [("game.js", "text/javascript; charset=utf-8"), ("dialogue.json", "application/json"), ("style.css", "text/css; charset=utf-8")] {
            let request = Data("GET /demo/LanternGarden/\(path) HTTP/1.1\r\nHost: 127.0.0.1:49152\r\n\r\n".utf8)
            let response = try router.response(to: request)
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.headers["Content-Type"], mime)
            XCTAssertGreaterThan(response.count, 0)
        }
        let dialogue = try Data(contentsOf: game.directory.appendingPathComponent("LanternGarden/dialogue.json"))
        XCTAssertTrue(String(decoding: dialogue, as: UTF8.self).contains("こんばんは"))
    }
    func testValidZIPExtractsRealContents() throws {
        let game = try prepare([("index.html", html), ("assets/test.json", Data("{}".utf8))])
        XCTAssertEqual(game.validation.engine, .html5)
        XCTAssertEqual(try Data(contentsOf: game.directory.appendingPathComponent("index.html")), html)
        XCTAssertEqual(game.fingerprint.count, 64)
    }
    func testNestedGameAndRelativeAssets() throws {
        let game = try prepare([("My Game/www/index.html", html), ("My Game/www/js/main.js", Data())])
        XCTAssertEqual(game.validation.entryPoint, "My Game/www/index.html")
    }
    func testMissingIndexRollsBackStaging() throws {
        XCTAssertThrowsError(try prepare([("readme.txt", html)])) { XCTAssertEqual($0 as? EverPlayError, .missingEntryPoint) }
        let items = try FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent("staging").path)
        XCTAssertTrue(items.isEmpty)
    }
    func testUnsupportedEngineIsNotPretendedToBeWeb() throws {
        XCTAssertThrowsError(try prepare([("Game.rgssad", Data()), ("Data/Actors.rxdata", Data())])) {
            XCTAssertEqual($0 as? EverPlayError, .unsupportedGame)
        }
    }
    func testUnknownInputHasNoWebEntryPoint() throws {
        XCTAssertThrowsError(try prepare([("mystery.bin", Data())]))
    }
    func testCorruptZIPIsRejected() throws {
        let input = temporary.appendingPathComponent("broken.zip")
        try Data("not a ZIP".utf8).write(to: input)
        XCTAssertThrowsError(try GameImporter().prepare(zip: input, stagingParent: temporary))
    }
    func testCRCMismatchIsRejected() throws {
        let archive = try zip([("index.html", html)])
        var bytes = try Data(contentsOf: archive)
        let range = try XCTUnwrap(bytes.range(of: html))
        bytes[range.lowerBound] ^= 1
        try bytes.write(to: archive)
        XCTAssertThrowsError(try GameImporter().prepare(zip: archive, stagingParent: temporary.appendingPathComponent("staging")))
    }
    func testTraversalAndPlatformPathsRejected() throws {
        for path in ["../index.html", "/index.html", "a/../../index.html", "C:/index.html", "a\\index.html", "a//index.html", "./index.html"] {
            XCTAssertThrowsError(try prepare([(path, html)]), path)
        }
    }
    func testNullAndControlPathsRejected() {
        for path in ["a\0b", "a\nb", "a/./b", "a/../b"] { XCTAssertThrowsError(try SafePath.components(path)) }
    }
    func testCaseCollisionsAndFileDirectoryCollisionsRejected() throws {
        for files in [[("index.html", html), ("INDEX.html", html)],
                      [("index.html", html), ("assets", Data()), ("assets/a.js", Data())]] {
            XCTAssertThrowsError(try prepare(files))
        }
    }
    func testUnicodeNormalizationCollisionRejected() throws {
        XCTAssertThrowsError(try prepare([("index.html", html), ("é.txt", Data()), ("e\u{301}.txt", Data())]))
    }
    func testSymlinkZIPRejected() throws {
        let input = try zip([("index.html", Data("/etc/passwd".utf8))], type: .symlink)
        XCTAssertThrowsError(try GameImporter().prepare(zip: input, stagingParent: temporary))
    }
    func testArchiveInputSymlinkRejected() throws {
        let archive = try zip([("index.html", html)])
        let link = temporary.appendingPathComponent("input-link.zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archive)
        XCTAssertThrowsError(try GameImporter().prepare(zip: link, stagingParent: temporary))
    }
    func testExistingSymlinkPathRejected() throws {
        try FileManager.default.createSymbolicLink(at: temporary.appendingPathComponent("alias"), withDestinationURL: temporary)
        XCTAssertThrowsError(try SafePath.destination("alias/index.html", in: temporary))
    }
    func testSizeAndCountLimits() throws {
        var limits = ImportLimits(); limits.maximumFileBytes = 4
        XCTAssertThrowsError(try prepare([("index.html", html)], limits: limits))
        limits = ImportLimits(); limits.maximumEntries = 1
        XCTAssertThrowsError(try prepare([("index.html", html), ("a.js", Data())], limits: limits))
        limits = ImportLimits(); limits.maximumExpandedBytes = 5
        XCTAssertThrowsError(try prepare([("index.html", html)], limits: limits))
        limits = ImportLimits(); limits.maximumArchiveBytes = 1
        XCTAssertThrowsError(try prepare([("index.html", html)], limits: limits))
    }
    func testCompressionBombRejected() throws {
        let data = Data(repeating: 65, count: 2_000_000)
        let input = try zip([("index.html", data)], compressed: true)
        XCTAssertThrowsError(try GameImporter().prepare(zip: input, stagingParent: temporary)) {
            XCTAssertEqual($0 as? EverPlayError, .limitExceeded("compression ratio"))
        }
    }
    func testMultipleIndependentGamesAreAmbiguous() throws {
        XCTAssertThrowsError(try prepare([("one/index.html", html), ("two/index.html", html)])) {
            XCTAssertEqual($0 as? EverPlayError, .ambiguousEntryPoints)
        }
    }
    func testRPGMakerMVAndMZDetection() throws {
        for (file, engine) in [("rpg_core.js", GameEngine.rpgMakerMV), ("rmmz_core.js", .rpgMakerMZ)] {
            let game = try prepare([("www/index.html", html), ("www/js/" + file, Data()), ("www/data/System.json", Data("{}".utf8))])
            XCTAssertEqual(game.validation.engine, engine)
            XCTAssertFalse(game.validation.warnings.isEmpty)
        }
    }
    func testSymlinkedAncestorPreservesRelativeEntryAndEngineDetection() throws {
        let parent = temporary.appendingPathComponent("actual")
        let game = parent.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("www/js"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: game.appendingPathComponent("www/data"), withIntermediateDirectories: true)
        try html.write(to: game.appendingPathComponent("www/index.html"))
        try Data().write(to: game.appendingPathComponent("www/js/rpg_core.js"))
        try Data("{}".utf8).write(to: game.appendingPathComponent("www/data/System.json"))
        let alias = temporary.appendingPathComponent("linked-parent")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)
        let result = try GameDetector.detect(at: alias.appendingPathComponent("export"))
        XCTAssertEqual(result.entryPoint, "www/index.html")
        XCTAssertEqual(result.engine, .rpgMakerMV)
    }
    func testIncompleteRPGMakerExportRejected() throws {
        XCTAssertThrowsError(try prepare([("index.html", html), ("js/rpg_core.js", Data())])) {
            XCTAssertEqual($0 as? EverPlayError, .incompleteEngine("RPG Maker MV"))
        }
    }
}

final class LibraryTests: FixtureTestCase {
    func testImportAndReopenRetainsIdentityAndSettings() async throws {
        let root = temporary.appendingPathComponent("library")
        let store = try LibraryStore(root: root)
        let game = try await store.importZIP(at: zip([("index.html", html)]))
        var controls = ControlSettings(); controls.visible = true; controls.opacity = 0.4
        try await store.updateControls(id: game.id, settings: controls)
        try await store.recordPlay(id: game.id, seconds: 12)
        let reopened = try LibraryStore(root: root)
        let saved = await reopened.games()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].id, game.id)
        XCTAssertEqual(saved[0].port, game.port)
        XCTAssertEqual(saved[0].resourceToken, game.resourceToken)
        XCTAssertEqual(saved[0].controls, controls)
        XCTAssertEqual(saved[0].playSeconds, 12)
    }
    func testRepackedDuplicateRejectedWithoutDeletingOriginal() async throws {
        let store = try LibraryStore(root: temporary.appendingPathComponent("library"))
        let game = try await store.importZIP(at: zip([("index.html", html), ("a.js", Data())]))
        do {
            try await store.importZIP(at: zip([("a.js", Data()), ("index.html", html)]))
            XCTFail("Duplicate import succeeded")
        } catch { XCTAssertEqual(error as? EverPlayError, .duplicateGame) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory(for: game).appendingPathComponent("index.html").path))
        let games = await store.games(); XCTAssertEqual(games.count, 1)
    }
    func testGamesUseDistinctOrigins() async throws {
        let store = try LibraryStore(root: temporary.appendingPathComponent("library"))
        let a = try await store.importZIP(at: zip([("index.html", html)]))
        let b = try await store.importZIP(at: zip([("index.html", html + Data("different".utf8))]))
        XCTAssertNotEqual(a.port, b.port); XCTAssertNotEqual(a.id, b.id); XCTAssertNotEqual(a.resourceToken, b.resourceToken)
    }
    func testInterruptedImportIsPreservedInRecovery() throws {
        let root = temporary.appendingPathComponent("library")
        let orphan = root.appendingPathComponent("Staging/interrupted")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try html.write(to: orphan.appendingPathComponent("index.html"))
        _ = try LibraryStore(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        let recovered = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path)
        XCTAssertEqual(recovered.count, 1)
    }
    func testArchiveRemovesFromLibraryAndPreservesFiles() async throws {
        let root = temporary.appendingPathComponent("library")
        let store = try LibraryStore(root: root)
        let game = try await store.importZIP(at: zip([("index.html", html)]))
        try await store.archive(id: game.id)
        let games = await store.games(); XCTAssertTrue(games.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path).count, 1)
    }
    func testInterruptedArchiveRestoresStillReferencedGame() async throws {
        let root = temporary.appendingPathComponent("library")
        let store = try LibraryStore(root: root)
        let game = try await store.importZIP(at: zip([("index.html", html)]))
        let recovery = root.appendingPathComponent("Recovery/interrupted-archive")
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try JSONEncoder().encode(game).write(to: recovery.appendingPathComponent("record.json"))
        try FileManager.default.moveItem(at: store.directory(for: game), to: recovery.appendingPathComponent("game"))
        let reopened = try LibraryStore(root: root)
        let games = await reopened.games()
        XCTAssertEqual(games.map(\.id), [game.id])
        XCTAssertEqual(try Data(contentsOf: reopened.directory(for: game).appendingPathComponent("index.html")), html)
    }
    func testArchivePreservesIdentityForFutureRestore() async throws {
        let root = temporary.appendingPathComponent("library")
        let store = try LibraryStore(root: root)
        let game = try await store.importZIP(at: zip([("index.html", html)]))
        try await store.archive(id: game.id)
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil).first)
        let record = try JSONDecoder().decode(GameRecord.self, from: Data(contentsOf: recovery.appendingPathComponent("record.json")))
        XCTAssertEqual(record, game)
        XCTAssertEqual(try Data(contentsOf: recovery.appendingPathComponent("game/index.html")), html)
    }
    func testUnknownSchemaAndCorruptMetadataFailClosed() throws {
        let root = temporary.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("library.json")
        try Data("{\"schemaVersion\":999,\"games\":[]}".utf8).write(to: manifest)
        XCTAssertThrowsError(try LibraryStore(root: root)) { XCTAssertEqual($0 as? EverPlayError, .unsupportedSchema(999)) }
        try Data("broken".utf8).write(to: manifest)
        XCTAssertThrowsError(try LibraryStore(root: root)) { XCTAssertEqual($0 as? EverPlayError, .invalidLibrary) }
        XCTAssertEqual(try String(contentsOf: manifest), "broken")
    }
}
