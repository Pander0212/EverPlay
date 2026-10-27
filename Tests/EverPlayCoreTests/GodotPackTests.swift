import XCTest
@testable import EverPlayCore

final class GodotPackTests: FixtureTestCase {
    /// A pack header as Godot writes it: "GDPC", format, major, minor, patch, then (format 2+) flags.
    private func pack(format: UInt32, _ major: UInt32, _ minor: UInt32, _ patch: UInt32, flags: UInt32 = 2) -> Data {
        var data = Data("GDPC".utf8)
        for value in [format, major, minor, patch, flags] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(Data(count: 100))  // file base, directory, reserved words: not read
        return data
    }

    /// A Windows executable with the pack appended (Godot's "embed pck"): exe | pack | size | "GDPC".
    private func executable(embedding pack: Data) -> Data {
        var data = Data("MZ".utf8) + Data(count: 4094)
        data.append(pack)
        withUnsafeBytes(of: UInt64(pack.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(Data("GDPC".utf8))
        return data
    }

    func testReadsStandaloneAndEmbeddedPacks() throws {
        let standalone = temporary.appendingPathComponent("Game.pck")
        try pack(format: 3, 4, 5, 1).write(to: standalone)
        XCTAssertEqual(GodotPack.read(standalone), GodotPack(formatVersion: 3, major: 4, minor: 5, patch: 1, encryptedDirectory: false, offset: 0))

        let exe = temporary.appendingPathComponent("Game.exe")
        try executable(embedding: pack(format: 4, 4, 7, 2)).write(to: exe)
        XCTAssertEqual(GodotPack.read(exe)?.version, "4.7.2")
        XCTAssertEqual(GodotPack.read(exe)?.offset, 4096)

        let encrypted = temporary.appendingPathComponent("Locked.exe")
        try executable(embedding: pack(format: 2, 4, 4, 1, flags: 3)).write(to: encrypted)
        XCTAssertEqual(GodotPack.read(encrypted)?.encryptedDirectory, true)

        let plain = temporary.appendingPathComponent("Other.exe")
        try (Data("MZ".utf8) + Data(count: 4000)).write(to: plain)
        XCTAssertNil(GodotPack.read(plain))
    }

    func testChoosesARuntimeOrSaysWhyNot() throws {
        XCTAssertEqual(try GodotRuntime.framework(for: GodotPack(formatVersion: 3, major: 4, minor: 5, patch: 1, encryptedDirectory: false, offset: 0)), "Godot47")
        XCTAssertEqual(try GodotRuntime.framework(for: GodotPack(formatVersion: 4, major: 4, minor: 7, patch: 2, encryptedDirectory: false, offset: 0)), "Godot47")
        XCTAssertEqual(try GodotRuntime.framework(for: GodotPack(formatVersion: 2, major: 4, minor: 4, patch: 1, encryptedDirectory: false, offset: 0)), "Godot44")
        XCTAssertEqual(try GodotRuntime.framework(for: GodotPack(formatVersion: 2, major: 4, minor: 3, patch: 0, encryptedDirectory: false, offset: 0)), "Godot44")
        XCTAssertEqual(try GodotRuntime.framework(for: GodotPack(formatVersion: 1, major: 3, minor: 5, patch: 3, encryptedDirectory: false, offset: 0)), "Godot36")
        for (pack, words) in [
            (GodotPack(formatVersion: 1, major: 2, minor: 1, patch: 0, encryptedDirectory: false, offset: 0), "Godot 3 and 4 games"),
            (GodotPack(formatVersion: 4, major: 4, minor: 9, patch: 0, encryptedDirectory: false, offset: 0), "newer Godot"),
            (GodotPack(formatVersion: 2, major: 4, minor: 4, patch: 1, encryptedDirectory: true, offset: 0), "encrypted"),
        ] {
            XCTAssertThrowsError(try GodotRuntime.framework(for: pack)) { error in
                XCTAssertTrue(error.localizedDescription.contains(words), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.hasPrefix("This is a Godot \(pack.version) game."), error.localizedDescription)
            }
        }
    }

    func testImportsAGameWithItsPackInTheExe() throws {
        let game = try prepare([("Game/Game.exe", executable(embedding: pack(format: 4, 4, 7, 2)))])
        XCTAssertEqual(game.validation.engine, .godot)
        XCTAssertEqual(game.validation.entryPoint, "Game/Game.exe")
    }

    func testImportsAGameWithAPckBesideTheExe() throws {
        let game = try prepare([("Game.exe", Data("MZ".utf8) + Data(count: 100)), ("Game.pck", pack(format: 3, 4, 5, 1))])
        XCTAssertEqual(game.validation.engine, .godot)
        XCTAssertEqual(game.validation.entryPoint, "Game.pck")
    }

    func testRejectsAnEncryptedGameWithTheReason() throws {
        XCTAssertThrowsError(try prepare([("Locked.exe", executable(embedding: pack(format: 2, 4, 4, 1, flags: 3)))])) { error in
            XCTAssertTrue(error.localizedDescription.contains("encrypted"), error.localizedDescription)
        }
    }

    func testAnExeWithoutAPackIsStillAWindowsProgram() throws {
        XCTAssertThrowsError(try prepare([("Setup.exe", Data("MZ".utf8) + Data(count: 100))])) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("This is a Windows program game"), error.localizedDescription)
        }
    }
}
