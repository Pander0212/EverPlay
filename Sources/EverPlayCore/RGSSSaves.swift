import Foundation

/// RPG Maker XP/VX/VX Ace games write their saves (Save1.rxdata, Save01.rvdata2, …) next to
/// Game.ini. EverPlay mirrors them into the visible Saves folder: into the game before it starts,
/// back out after it has run (the game closes EverPlay, so at the next start).
public enum RGSSSaves {
    static func isSave(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasPrefix("save") else { return false }
        return ["rxdata", "rvdata", "rvdata2"].contains((lower as NSString).pathExtension)
    }

    static func saves(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter(isSave)
    }

    /// Makes `target`'s saves an exact copy of `source`'s. Other files are not touched.
    public static func mirror(from source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let wanted = Set(saves(in: source))
        for name in saves(in: target) where !wanted.contains(name) {
            try fileManager.removeItem(at: target.appendingPathComponent(name))
        }
        for name in wanted {
            let from = source.appendingPathComponent(name), to = target.appendingPathComponent(name)
            if fileManager.contentsEqual(atPath: from.path, andPath: to.path) { continue }
            if fileManager.fileExists(atPath: to.path) { try fileManager.removeItem(at: to) }
            try fileManager.copyItem(at: from, to: to)
        }
    }

    /// Before the game starts: the Saves folder wins (the player may have changed it in Files).
    /// The first time, the game's own saves seed it.
    public static func prepare(gameFolder: URL, saveFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: saveFolder.path) {
            try mirror(from: gameFolder, to: saveFolder)
        }
        try mirror(from: saveFolder, to: gameFolder)
    }

    /// After the game has run: its saves go back to the Saves folder.
    public static func collect(gameFolder: URL, saveFolder: URL) throws {
        try mirror(from: gameFolder, to: saveFolder)
    }
}
