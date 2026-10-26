import XCTest
import ZIPFoundation
@testable import EverPlayCore

/// Little-endian bytes for archive fixtures.
private struct Bytes {
    var bytes: [UInt8] = []
    mutating func raw(_ values: [UInt8]) { bytes.append(contentsOf: values) }
    mutating func int<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func text(_ string: String) { bytes.append(UInt8(string.utf8.count)); bytes.append(contentsOf: Array(string.utf8)) }
    mutating func reference(_ id: Int32) { raw([9]); int(id) }
}

final class KiriKiriSchemesTests: FixtureTestCase {
    private func zlib(_ data: [UInt8]) throws -> [UInt8] {
        var out: [UInt8] = [0x78, 0x9C]
        let source = Data(data)
        _ = try Data.compress(size: Int64(source.count), bufferSize: 4096, provider: { position, size in
            source.subdata(in: Int(position) ..< min(Int(position) + size, source.count))
        }, consumer: { out += $0 })
        return out + [0, 0, 0, 0]
    }

    private func chunk(_ tag: String, _ body: [UInt8]) -> [UInt8] {
        var out = Bytes()
        out.raw(Array(tag.utf8))
        out.int(UInt64(body.count))
        out.raw(body)
        return out.bytes
    }

    /// An XP3 archive with startup.tjs (stored or zlib) and a stored index.
    private func xp3(startup: [UInt8], compressed: Bool) throws -> URL {
        let stored = compressed ? try zlib(startup) : startup
        var info = Bytes()
        info.int(UInt32(0)); info.int(UInt64(startup.count)); info.int(UInt64(stored.count)); info.int(UInt16(11))
        "startup.tjs".utf16.forEach { info.int($0) }
        var segm = Bytes()
        segm.int(UInt32(compressed ? 1 : 0)); segm.int(UInt64(19)); segm.int(UInt64(startup.count)); segm.int(UInt64(stored.count))
        var adlr = Bytes()
        adlr.int(UInt32(1))
        let index = chunk("File", chunk("info", info.bytes) + chunk("segm", segm.bytes) + chunk("adlr", adlr.bytes))
        var archive = Bytes()
        archive.raw(XP3Archive.magic)
        archive.int(UInt64(19 + stored.count))
        archive.raw(stored)
        archive.raw([0])
        archive.int(UInt64(index.count))
        archive.raw(index)
        let game = temporary.appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data(archive.bytes).write(to: game.appendingPathComponent("data.xp3"))
        return game
    }

    func testTellsPlainFromEncryptedArchives() throws {
        let script = Array("// startup.tjs\r\nScripts.execStorage(\"system/Initialize.tjs\");\r\n".utf8)
        XCTAssertEqual(KiriKiriGame.archiveState(gameRoot: try xp3(startup: script, compressed: false)), .plain)
        XCTAssertEqual(KiriKiriGame.archiveState(gameRoot: try xp3(startup: script, compressed: true)), .plain)
        let scrambled = script.enumerated().map { $0.element ^ UInt8(truncatingIfNeeded: $0.offset &* 37 &+ 0x5A) }
        XCTAssertEqual(KiriKiriGame.archiveState(gameRoot: try xp3(startup: scrambled, compressed: true)), .encrypted)
        XCTAssertEqual(KiriKiriGame.archiveState(gameRoot: temporary.appendingPathComponent("none")), .unknown)
    }

    /// A database with one CxDec title, as BinaryFormatter writes a KeyValuePair.
    private func database() throws -> Data {
        let cx = "GameRes.Formats.KiriKiri.CxEncryption"
        var r = Bytes()
        r.raw([UInt8](repeating: 0, count: 17))
        r.raw([12]); r.int(Int32(2)); r.text("GameRes")
        r.raw([5]); r.int(Int32(1)); r.text("KeyValuePair"); r.int(Int32(2)); r.text("key"); r.text("value")
        r.raw([1, 4]); r.text(cx); r.int(Int32(2)); r.int(Int32(2))
        r.raw([6]); r.int(Int32(3)); r.text("Test Game: Special Edition")
        r.raw([5]); r.int(Int32(4)); r.text(cx); r.int(Int32(6))
        ["m_mask", "m_offset", "PrologOrder", "OddBranchOrder", "EvenBranchOrder", "ControlBlock"].forEach { r.text($0) }
        r.raw([0, 0, 7, 7, 7, 7, 8, 8, 2, 2, 2, 15]); r.int(Int32(2))
        r.int(Int32(0x1F1)); r.int(Int32(0x2B4))
        (5 ... 8).forEach { r.reference(Int32($0)) }
        for (id, count) in [(5, 3), (6, 6), (7, 8)] {
            r.raw([15]); r.int(Int32(id)); r.int(Int32(count)); r.raw([2]); r.raw((0 ..< count).map(UInt8.init))
        }
        r.raw([15]); r.int(Int32(8)); r.int(Int32(1024)); r.raw([15])
        (0 ..< 1024).forEach { r.int(UInt32($0) &* 0x01010101) }
        r.raw([11])
        var file = Bytes()
        file.raw(Array("GARbroDB".utf8)); file.int(UInt32(0x94)); file.raw(try zlib(r.bytes))
        return Data(file.bytes)
    }

    func testWritesTheEnginesSchemeFileForATitle() throws {
        let catalog = try KiriKiriSchemes.catalog(from: try database())
        XCTAssertEqual(catalog.titles, ["Test Game: Special Edition"])
        let scheme = try XCTUnwrap(catalog.schemeFile(title: "Test Game: Special Edition"))
        XCTAssertEqual(scheme.count, 16 + 20 + 4096)
        var head = Bytes()
        head.raw(Array("SHCX".utf8)); head.int(UInt32(1)); head.int(UInt32(0x1F1)); head.int(UInt32(0x2B4))
        XCTAssertEqual(Array(scheme.prefix(16)), head.bytes)
        XCTAssertEqual(Array(scheme[16 ..< 36]), [0, 1, 2, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 0])
        XCTAssertEqual(Array(scheme[44 ..< 48]), [2, 2, 2, 2])
        XCTAssertEqual(catalog.suggestions(for: ["TestGame.exe"]), ["Test Game: Special Edition"])
        XCTAssertEqual(catalog.suggestions(for: ["Other"]), [])
        XCTAssertThrowsError(try KiriKiriSchemes.catalog(from: Data("not a database".utf8)))
    }

    /// Reads GARbro's real database from EVERPLAY_GARBRO_TEST (a path), which is not in the repository.
    func testReadsGARbrosDatabaseFromTheEnvironment() throws {
        guard let path = ProcessInfo.processInfo.environment["EVERPLAY_GARBRO_TEST"] else { throw XCTSkip("EVERPLAY_GARBRO_TEST not set") }
        let catalog = try KiriKiriSchemes.catalog(from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertGreaterThan(catalog.titles.count, 100)
        for title in ["KARAKARA 2", "Riddle Joker [Steam]"] {
            let scheme = try XCTUnwrap(catalog.schemeFile(title: title), title)
            XCTAssertGreaterThanOrEqual(scheme.count, 16 + 20 + 4096)
        }
        print("GARbro titles:", catalog.titles.count, "Hx:", catalog.schemes.values.filter(\.hx).count,
              "suggestions for Karakara2.exe:", catalog.suggestions(for: ["Karakara2.exe"]))
    }
}

final class RPGMakerTextTests: FixtureTestCase {
    func testReadsMessagesChoicesAndSpeakersOnceFromTheDataFiles() throws {
        let data = temporary.appendingPathComponent("www/data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: data.appendingPathComponent("System.json"))
        let map = """
        {"events":[null,{"pages":[{"list":[
          {"code":101,"indent":0,"parameters":["Actor1",0,0,2,"Reid"]},
          {"code":401,"indent":0,"parameters":["Hello there."]},
          {"code":102,"indent":0,"parameters":[["Yes","No"],1]},
          {"code":401,"indent":0,"parameters":["Hello there."]},
          {"code":122,"indent":0,"parameters":[1,1,0,4,"\\"script\\""]},
          {"code":0,"indent":0,"parameters":[]}]}]}]}
        """
        try Data(map.utf8).write(to: data.appendingPathComponent("Map001.json"))
        try Data(#"[null,{"list":[{"code":405,"parameters":["The end"]},{"code":401,"parameters":["  "]}]}]"#.utf8)
            .write(to: data.appendingPathComponent("CommonEvents.json"))
        let folder = try XCTUnwrap(RPGMakerText.dataFolder(gameRoot: temporary))
        XCTAssertEqual(RPGMakerText.lines(dataFolder: folder), ["The end", "Reid", "Hello there.", "Yes", "No"])
    }

    func testOldTranslationSettingsStillDecode() throws {
        let old = Data(#"{"provider":"google","targetLanguage":"de","model":"","baseURL":""}"#.utf8)
        let settings = try JSONDecoder().decode(TranslationSettings.self, from: old)
        XCTAssertEqual(settings.provider, .google)
        XCTAssertNil(settings.sourceLanguage)
    }
}
