import UIKit
import EverPlayCore

/// Starts RPG Maker XP, VX and VX Ace games in this process with mkxp-z (Frameworks/MKXP.framework,
/// built by scripts/build-mkxp-ios.sh). Like Ren'Py, mkxp-z takes over the screen until the game
/// quits, which also closes EverPlay.
@MainActor
enum MKXPLauncher {
    static var binary: URL? {
        let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("MKXP.framework/MKXP")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// mkxp-z's output of the last game, with the signal and stack if it crashed.
    static var logFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/mkxp-z.log")
    }

    /// Copies the last game's mkxp-z output into the diagnostics log once (at app start).
    static func collectPreviousLog() {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8), !text.isEmpty else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60)
        EverPlayLog.write("mkxp-z output of the last game:\n" + lines.joined(separator: "\n"))
        try? FileManager.default.removeItem(at: logFile)
    }

    /// Returns a message for the player when the game cannot start.
    static func play(_ game: GameRecord, directory: URL) -> String? {
        guard let binary else { return "This EverPlay build does not include mkxp-z for RPG Maker XP/VX/VX Ace." }
        let folder = directory.appendingPathComponent(game.entryPoint).deletingLastPathComponent()
        EverPlayLog.write("Starting \(game.title) with mkxp-z")
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        setenv("EVERPLAY_MKXP_LOG", logFile.path, 1)
        // RPG Maker games are landscape; rotate before SDL creates its window.
        setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        let delay = scene?.interfaceOrientation.isLandscape == true ? 0.05 : 0.8
        // A run loop timer, not DispatchQueue.main: the game loop never returns (see RenPyLibrary.play).
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated {
            guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_LOCAL),
                  let symbol = dlsym(handle, "everplay_mkxp_main") else {
                EverPlayLog.write("mkxp-z could not be loaded: \(dlerror().map { String(cString: $0) } ?? "unknown")")
                return
            }
            typealias Entry = @convention(c) (UnsafePointer<CChar>) -> Int32
            let entry = unsafeBitCast(symbol, to: Entry.self)
            EverPlayLog.write("mkxp-z loaded; running \(game.title)")
            UIApplication.shared.isIdleTimerDisabled = true
            let status = folder.path.withCString { entry($0) }
            EverPlayLog.write("mkxp-z returned with status \(status) for \(game.title)")
            exit(status)
        } }
        return nil
    }
}
