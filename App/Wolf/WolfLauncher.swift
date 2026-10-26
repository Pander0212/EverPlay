import UIKit
import EverPlayCore

/// Starts WOLF RPG Editor games in this process with EverPlay's own engine (Frameworks/WolfRPG.framework,
/// built from Engines/WolfRPG by scripts/build-wolfrpg-ios.sh). Like mkxp-z it takes over the screen until
/// the game quits, which also closes EverPlay. Saves go straight to On My iPhone › EverPlay › Saves › game.
@MainActor
enum WolfLauncher {
    static var binary: URL? {
        let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("WolfRPG.framework/WolfRPG")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    static func gameFolder(_ game: GameRecord, directory: URL) -> URL {
        let folder = WolfGame.folder(ofEntryPoint: game.entryPoint)
        return folder.isEmpty ? directory : directory.appendingPathComponent(folder, isDirectory: true)
    }

    /// The engine's output of the last game, with the signal and stack if it crashed.
    static var logFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/wolfrpg.log")
    }

    /// Copies the last game's engine output into the diagnostics log once (at app start).
    static func collectPreviousLog() {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8), !text.isEmpty else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60)
        EverPlayLog.write("WOLF RPG output of the last game:\n" + lines.joined(separator: "\n"))
        try? FileManager.default.removeItem(at: logFile)
    }

    /// Returns a message for the player when the game cannot start.
    static func play(_ game: GameRecord, directory: URL) -> String? {
        guard let binary else { return "This EverPlay build does not include the WOLF RPG engine." }
        let folder = gameFolder(game, directory: directory)
        let pro = WolfGame.proArchives(gameFolder: folder)
        if !pro.isEmpty {
            return "This game was made with WOLF RPG Editor Pro; its archives (\(pro.joined(separator: ", "))) "
                + "need the game's own key file, which is missing."
        }
        EverPlayLog.write("Starting \(game.title) with the WOLF RPG engine")
        let saves = SaveFolders.libretro(game)
        try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: WolfCheatBridge.folder, withIntermediateDirectories: true)
        // For games whose fonts are missing (most ask for MS Gothic, whose metrics BIZ UDGothic shares).
        let font = Bundle.main.url(forResource: "BIZUDGothic-Regular", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "BIZUDGothic-Regular", withExtension: "ttf", subdirectory: "Fonts")
        let soundFont = Bundle.main.url(forResource: "TimGM6mb", withExtension: "sf2")
        // WOLF games are landscape; rotate before SDL creates its window.
        setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        let delay = scene?.interfaceOrientation.isLandscape == true ? 0.05 : 0.8
        // A run loop timer, not DispatchQueue.main: the game loop never returns (see MKXPLauncher.play).
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated {
            guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_LOCAL),
                  let symbol = dlsym(handle, "everplay_wolf_main") else {
                EverPlayLog.write("The WOLF RPG engine could not be loaded: \(dlerror().map { String(cString: $0) } ?? "unknown")")
                return
            }
            typealias Entry = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>,
                                              UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
            let entry = unsafeBitCast(symbol, to: Entry.self)
            EverPlayLog.write("WOLF RPG engine loaded; running \(game.title)")
            WolfCheatBridge.listen()
            UIApplication.shared.isIdleTimerDisabled = true
            // The engine sends stdout to its log; EverPlay's buffered output would land there too.
            fflush(stdout)
            let arguments = [folder.path, saves.path, font?.path ?? "",
                             soundFont?.path ?? "", WolfCheatBridge.folder.path, logFile.path]
            let copies = arguments.map { strdup($0)! }
            let status = entry(copies[0], copies[1], copies[2], copies[3], copies[4], copies[5])
            copies.forEach { free($0) }
            EverPlayLog.write("The WOLF RPG engine returned with status \(status) for \(game.title)")
            exit(status)
        } }
        return nil
    }
}
