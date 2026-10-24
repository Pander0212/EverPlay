import XCTest
@testable import EverPlayCore

final class InnoSetupArchiveTests: XCTestCase {
    /// Extracts real installers named in EVERPLAY_INNO_TEST ("setup.exe=output folder;…"); they are
    /// not in the repository. Compare the output with innoextract.
    func testExtractsInstallersFromTheEnvironment() throws {
        guard let list = ProcessInfo.processInfo.environment["EVERPLAY_INNO_TEST"] else {
            throw XCTSkip("EVERPLAY_INNO_TEST not set")
        }
        for pair in list.split(separator: ";") {
            let parts = pair.split(separator: "=").map(String.init)
            let archive = try InnoSetupArchive(setup: URL(fileURLWithPath: parts[0]))
            let count = try archive.extract(into: URL(fileURLWithPath: parts[1]))
            print("\(archive.version): \(archive.files.count) files, \(count) written")
            XCTAssertGreaterThan(count, 100)
        }
    }

    func testRejectsOtherFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".exe")
        try Data("MZ not an installer".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(InnoSetupArchive.isInstaller(file))
        XCTAssertThrowsError(try InnoSetupArchive(setup: file))
    }
}
