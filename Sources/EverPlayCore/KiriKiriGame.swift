import Foundation

/// What EverPlay prepares before a KiriKiri game starts: its saves visible in Files, and the
/// name of its PC executable, which KiriKiri games read (System.exeName) but never run.
public enum KiriKiriGame {
    /// KiriKiri writes saves to `savedata/` in the game's folder. It becomes a link to the
    /// visible Saves folder; saves already in the game (from the ZIP or an earlier start) move there.
    public static func linkSaves(gameRoot: URL, saveFolder: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let link = gameRoot.appendingPathComponent("savedata")
        let values = try? link.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true {
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == saveFolder.path { return }
            try fileManager.removeItem(at: link)
        } else if values?.isDirectory == true {
            for name in try fileManager.contentsOfDirectory(atPath: link.path) {
                let target = saveFolder.appendingPathComponent(name)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.moveItem(at: link.appendingPathComponent(name), to: target)
                }
            }
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: saveFolder)
    }

    /// The game's own executable (not an installer, uninstaller or config tool); "game.exe" if none.
    public static func executableName(in gameRoot: URL) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: gameRoot.path)) ?? []).sorted()
        return names.first { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".exe") && !["unins", "setup", "config", "steam", "crash"].contains(where: lower.contains)
        } ?? "game.exe"
    }
}
