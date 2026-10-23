import XCTest
@testable import EverPlay

final class RenPyPluginTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func game(_ name: String, files: [String: String]) throws -> URL {
        let folder = root.appendingPathComponent(name)
        for (path, text) in files {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        return folder
    }

    func testDetectsDesktopGamesAndTheirEngineVersion() throws {
        let shipped = try game("Shipped", files: ["game/archive.rpa": "", "renpy/__init__.py": "",
                                                  "renpy/vc_version.py": "branch = 'fix'\nversion = '8.4.1.25072401'\n"])
        XCTAssertTrue(RenPyGame.isGame(shipped))
        XCTAssertEqual(RenPyGame.version(of: shipped), "8.4.1")

        let legacy = try game("Legacy", files: ["game/script.rpyc": "", "renpy/__init__.py": "",
                                                "renpy/vc_version.py": "version = u'7.4.11.2266'\n"])
        XCTAssertEqual(RenPyGame.version(of: legacy), "7.4.11")

        let scriptOnly = try game("ScriptOnly", files: ["game/script.rpy": "", "game/script_version.txt": "(8, 2, 3)"])
        XCTAssertTrue(RenPyGame.isGame(scriptOnly))
        XCTAssertEqual(RenPyGame.version(of: scriptOnly), "8.2.3")

        let web = try game("Web", files: ["index.html": "<!doctype html>"])
        XCTAssertFalse(RenPyGame.isGame(web))
    }
}
