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
    func testRecognisesRenPyArchivesWithoutExtracting() throws {
        XCTAssertTrue(GameImporter.archiveContainsRenPyGame(try zip([("MyGame-1.0-pc/game/archive.rpa", Data())])))
        XCTAssertTrue(GameImporter.archiveContainsRenPyGame(try zip([("game/script.rpyc", Data())])))
        XCTAssertTrue(GameImporter.archiveContainsRenPyGame(try zip([("Big/renpy/__init__.py", Data())])))
        XCTAssertFalse(GameImporter.archiveContainsRenPyGame(try zip([("www/index.html", html), ("game/readme.txt", Data())])))
    }

    func testExtractArchiveWritesFilesAndRejectsEscapes() throws {
        let target = temporary.appendingPathComponent("out")
        let files = try GameImporter().extractArchive(zip: try zip([("Game/game/script.rpy", Data("label start:".utf8))]), into: target)
        XCTAssertEqual(files.map(\.path), ["Game/game/script.rpy"])
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("Game/game/script.rpy"), encoding: .utf8), "label start:")
        XCTAssertThrowsError(try GameImporter().extractArchive(zip: try zip([("../escape.txt", Data())]),
                                                               into: temporary.appendingPathComponent("bad")))
    }

    func testPickedFolderImportsLikeAZIPWithStablePortBelowEphemeralRange() async throws {
        let folder = temporary.appendingPathComponent("My Game/www", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try html.write(to: folder.appendingPathComponent("index.html"))
        let packed = temporary.appendingPathComponent("packed.zip")
        try GameImporter.packFolder(temporary.appendingPathComponent("My Game"), to: packed)
        let store = try LibraryStore(root: temporary.appendingPathComponent("library"))
        let game = try await store.importZIP(at: packed, title: "My Game")
        XCTAssertEqual(game.entryPoint, "www/index.html")
        XCTAssertTrue((30000...39999).contains(game.port))
    }

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
    func testShiftJISFileNamesFromJapaneseArchives() throws {
        // Stored ZIP whose names are Shift-JIS without the UTF-8 flag (as Japanese Windows writes them):
        // ゲーム/RPG_RT.ldb, ゲーム/RPG_RT.lmt, ゲーム/CharSet/主人公.png
        let base64 = "UEsDBBQAAAAAAAAAIQAovPTjAgAAAAIAAAARAAAAg1GBW4OAL1JQR19SVC5sZGJkYlBLAwQUAAAAAAAAACEA3F4+twQAAAAEAAAAEQAAAINRgVuDgC9SUEdfUlQubG10dHJlZVBLAwQUAAAAAAAAACEAAAAAAAAAAAAAAAAAGQAAAINRgVuDgC9DaGFyU2V0L47lkGyM9i5wbmdQSwECFAMUAAAAAAAAACEAKLz04wIAAAACAAAAEQAAAAAAAAAAAAAAgAEAAAAAg1GBW4OAL1JQR19SVC5sZGJQSwECFAMUAAAAAAAAACEA3F4+twQAAAAEAAAAEQAAAAAAAAAAAAAAgAExAAAAg1GBW4OAL1JQR19SVC5sbXRQSwECFAMUAAAAAAAAACEAAAAAAAAAAAAAAAAAGQAAAAAAAAAAAAAAgAFkAAAAg1GBW4OAL0NoYXJTZXQvjuWQbIz2LnBuZ1BLBQYAAAAAAwADAMUAAACbAAAAAAA="
        let url = temporary.appendingPathComponent("japanese.zip")
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
        let game = try GameImporter().prepare(zip: url, stagingParent: temporary.appendingPathComponent("staging"))
        XCTAssertEqual(game.validation.engine, .rpgMaker2000)
        XCTAssertEqual(game.validation.entryPoint, "ゲーム/RPG_RT.ldb")
        XCTAssertTrue(FileManager.default.fileExists(atPath: game.directory.appendingPathComponent("ゲーム/CharSet/主人公.png").path))
    }
    func testRPGMaker2000GameIsDetectedByItsDatabase() throws {
        let game = try prepare([("Yume/RPG_RT.ldb", Data("LcfDataBase".utf8)), ("Yume/RPG_RT.lmt", Data("LcfMapTree".utf8)),
                                ("Yume/Map0001.lmu", Data()), ("Yume/RPG_RT.exe", Data("MZ".utf8)), ("Yume/Picture/title.png", Data())])
        XCTAssertEqual(game.validation.engine, .rpgMaker2000)
        XCTAssertEqual(game.validation.entryPoint, "Yume/RPG_RT.ldb")
        XCTAssertFalse(GameEngine.rpgMaker2000.isWeb)
        XCTAssertThrowsError(try prepare([("Broken/RPG_RT.ldb", Data())]), "a database without its map tree is not a game")
    }
    func testNWJSPackageNextToTheExecutable() throws {
        let inner = try zip([("index.html", html), ("tyrano/tyrano.js", Data("tyrano".utf8))], name: "inner")
        let game = try prepare([("MyTyranoGame/Game.exe", Data("MZ".utf8)), ("MyTyranoGame/package.nw", try Data(contentsOf: inner))])
        XCTAssertEqual(game.validation.entryPoint, "MyTyranoGame/package_nw/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: game.directory.appendingPathComponent("MyTyranoGame/package_nw/tyrano/tyrano.js").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.directory.appendingPathComponent("MyTyranoGame/package.nw").path))
    }
    /// An app.asar as Electron's asar tool writes it (header pickle, then the file data).
    func asar(_ tree: [String: Any], data: Data) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: ["files": tree])
        let padded = json + Data(repeating: 0, count: (4 - json.count % 4) % 4)
        func le(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        return le(4) + le(padded.count + 8) + le(padded.count + 4) + le(json.count) + padded + data
    }
    func testElectronAppAsarNextToTheExecutable() throws {
        let script = Data("tyrano".utf8)
        let packed = try asar(["index.html": ["size": html.count, "offset": "0"],
                               "tyrano": ["files": ["tyrano.js": ["size": script.count, "offset": String(html.count)]]],
                               "node": ["link": "../elsewhere"],
                               "native.node": ["size": 3, "unpacked": true]],
                              data: html + script)
        let game = try prepare([("MyTyranoGame/MyTyranoGame.exe", Data("MZ".utf8)), ("MyTyranoGame/LICENSES.chromium.html", html),
                                ("MyTyranoGame/resources/app.asar", packed),
                                ("MyTyranoGame/resources/app.asar.unpacked/native.node", Data("abc".utf8))])
        XCTAssertEqual(game.validation.entryPoint, "MyTyranoGame/resources/app_asar/index.html")
        let root = game.directory.appendingPathComponent("MyTyranoGame/resources")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("app_asar/tyrano/tyrano.js")), script)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("app_asar/native.node")), Data("abc".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("app.asar").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("app_asar/node").path))
    }
    func testAsarEntriesOutsideTheArchiveOrPathsEscapingAreRejected() throws {
        let beyond = try asar(["index.html": ["size": 400, "offset": "0"]], data: html)
        XCTAssertThrowsError(try AsarArchive.extract(writeTemporary(beyond), into: temporary.appendingPathComponent("a")))
        let escaping = try asar(["..": ["files": ["index.html": ["size": html.count, "offset": "0"]]]], data: html)
        XCTAssertThrowsError(try AsarArchive.extract(writeTemporary(escaping), into: temporary.appendingPathComponent("b")))
        XCTAssertThrowsError(try AsarArchive.extract(writeTemporary(Data("not an asar".utf8)), into: temporary.appendingPathComponent("c")))
    }
    func writeTemporary(_ data: Data) throws -> URL {
        let url = temporary.appendingPathComponent(UUID().uuidString + ".asar")
        try data.write(to: url)
        return url
    }
    func testRPGMakerXPVXAceGamesAreDetectedByGameIniAndScriptsOrArchive() throws {
        let xp = try prepare([("Aedemphia/Game.exe", Data("MZ".utf8)), ("Aedemphia/Game.ini", Data("[Game]".utf8)),
                              ("Aedemphia/Data/Scripts.rxdata", Data([4, 8])), ("Aedemphia/Graphics/Titles/t.png", Data())])
        XCTAssertEqual(xp.validation.engine, .rgss)
        XCTAssertEqual(xp.validation.entryPoint, "Aedemphia/Game.ini")
        XCTAssertFalse(GameEngine.rgss.isWeb)
        let ace = try prepare([("Game.ini", Data("[Game]".utf8)), ("Game.rgss3a", Data([1]))])
        XCTAssertEqual(ace.validation.entryPoint, "Game.ini")
        XCTAssertThrowsError(try prepare([("Broken/Data/Scripts.rvdata2", Data([1]))]), "scripts without Game.ini are not a game")
    }
    func testONScripterGameIsDetectedByItsScript() throws {
        let game = try prepare([("Tsukihime/Game.exe", Data("MZ".utf8)), ("Tsukihime/nscript.dat", Data([1, 2])),
                                ("Tsukihime/default.ttf", Data()), ("Tsukihime/readme.html", html)])
        XCTAssertEqual(game.validation.engine, .onscripter)
        XCTAssertEqual(game.validation.entryPoint, "Tsukihime/onsyuri.html")
        XCTAssertEqual(game.validation.warnings, [])
        XCTAssertTrue(GameEngine.onscripter.isWeb)
        let plain = try prepare([("0.txt", Data("*define".utf8)), ("bgm/a.ogg", Data())])
        XCTAssertEqual(plain.validation.entryPoint, "onsyuri.html")
        XCTAssertEqual(plain.validation.warnings.count, 1, "no default.ttf")
    }
    func testONScripterShellIsCopiedWithAFileIndex() throws {
        let shell = temporary.appendingPathComponent("shell")
        let game = temporary.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: game.appendingPathComponent("my bgm"), withIntermediateDirectories: true)
        for name in ONScripterShell.files { try Data(name.utf8).write(to: shell.appendingPathComponent(name)) }
        try Data("*define".utf8).write(to: game.appendingPathComponent("0.txt"))
        try Data().write(to: game.appendingPathComponent("my bgm/曲#1.ogg"))
        try ONScripterShell.install(shell: shell, gameFolder: game)
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("onsyuri.wasm")), Data("onsyuri.wasm".utf8))
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: game.appendingPathComponent("onsyuri_index.json"))) as! [String: Any]
        let files = index["files"] as! [[String: String]]
        XCTAssertEqual(files.map { $0["path"]! }, ["0.txt", "my bgm/曲#1.ogg"])
        XCTAssertEqual(files[1]["url"], "my%20bgm/%E6%9B%B2%231.ogg")
        XCTAssertEqual(index["lazyload"] as? Bool, true)
        // A newer build replaces the copy; an unchanged one is left alone.
        try Data("new".utf8).write(to: shell.appendingPathComponent("onsyuri.js"))
        try ONScripterShell.install(shell: shell, gameFolder: game)
        XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent("onsyuri.js")), Data("new".utf8))
        try FileManager.default.removeItem(at: shell.appendingPathComponent("onsyuri.wasm"))
        XCTAssertThrowsError(try ONScripterShell.install(shell: shell, gameFolder: game))
    }
    func testSingleFileHTMLGameWithoutIndex() throws {
        let story = Data(("<!doctype html><title>Story</title>" + String(repeating: "x", count: 4000)).utf8)
        let game = try prepare([("DoL/Degrees of Lewdity 0.5.html", story), ("DoL/credits.html", html),
                                ("DoL/img/ui/icon.png", Data()), ("DoL/extras/notes.html", html)])
        XCTAssertEqual(game.validation.entryPoint, "DoL/Degrees of Lewdity 0.5.html")
        XCTAssertEqual(game.validation.engine, .html5)
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

final class ControlLayoutTests: XCTestCase {
    func testDefaultLayoutIsStableAndOlderSettingsStillDecode() throws {
        XCTAssertEqual(ControlButton.defaultLayout().map(\.id), ControlButton.defaultLayout().map(\.id))
        let old = Data(#"{"visible":true,"opacity":0.5,"leftX":0.2,"leftY":0.7,"rightX":0.8,"rightY":0.7}"#.utf8)
        let settings = try JSONDecoder().decode(ControlSettings.self, from: old)
        XCTAssertNil(settings.buttons)
        XCTAssertEqual(settings.layout.first?.kind, .dpad)
        XCTAssertEqual(settings.layout.first?.x, 0.2)
        XCTAssertEqual(ControlKey.named("a")?.keyCode, 65)
        XCTAssertEqual(ControlKey.named(" ")?.code, "Space")
        XCTAssertNil(ControlKey.named("<script>"))
    }
}
