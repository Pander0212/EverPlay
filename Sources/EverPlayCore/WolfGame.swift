import Foundation

/// WOLF RPG Editor games: where their data is and which folder the engine opens.
///
/// A game keeps its data loose in Data/BasicData/Game.dat (and the maps, pictures and sounds in
/// Data/…), or packed in Data.wolf or one archive per folder (Data/BasicData.wolf, …) beside
/// Game.exe (GamePro.exe for WOLF RPG Editor Pro).
public enum WolfGame {
    /// The extensions of WOLF archives: .wolf, and others WOLF RPG Editor Pro games may use.
    static let archiveExtensions: Set<String> = ["wolf", "data", "pak", "bin", "assets", "content", "res", "resource"]

    /// The key file of a Pro game's archives, in Data (lowercase names without extension).
    static let proKeyFiles: Set<String> = ["game", "list", "data2", "gamefile", "basicdata2"]

    private static func isArchive(_ lower: String) -> Bool { archiveExtensions.contains((lower as NSString).pathExtension) }

    /// Whether a file (its path in the import) marks a WOLF game; it is then the entry point.
    static func marker(_ relative: String) -> Bool {
        let lower = relative.lowercased()
        if lower == "data/basicdata/game.dat" || lower.hasSuffix("/data/basicdata/game.dat") { return true }
        guard isArchive(lower) else { return false }
        let base = (lower as NSString).deletingPathExtension
        return base == "data/basicdata" || base.hasSuffix("/data/basicdata") || (base as NSString).lastPathComponent == "data"
    }

    /// Whether the marker is a packed archive (which needs Game.exe beside it to count).
    static func isArchiveMarker(_ relative: String) -> Bool { !relative.lowercased().hasSuffix("game.dat") }

    /// The game folder (relative to the import, "" for its top) of an entry point from `marker`.
    public static func folder(ofEntryPoint entry: String) -> String {
        let lower = entry.lowercased()
        let base = (lower as NSString).deletingPathExtension
        let levels = lower.hasSuffix("basicdata/game.dat") ? 3 : base.hasSuffix("data/basicdata") ? 2 : 1
        var components = entry.split(separator: "/").map(String.init)
        components.removeLast(min(levels, components.count))
        return components.joined(separator: "/")
    }

    /// The executables WOLF games ship with, lowercased.
    static let executables: Set<String> = ["game.exe", "gamepro.exe"]

    /// Archives of WOLF RPG Editor Pro that EverPlay cannot open: their key comes from a key file in
    /// Data (Game.wolf, List.wolf, …), and these games have none. Pro archives are DxLib version 8
    /// archives whose header names an encryption version of 1000 or more.
    public static func proArchives(gameFolder: URL) -> [String] {
        var candidates: [URL] = []
        if let top = try? FileManager.default.contentsOfDirectory(at: gameFolder, includingPropertiesForKeys: nil) {
            candidates += top.filter { $0.deletingPathExtension().lastPathComponent.lowercased() == "data"
                && archiveExtensions.contains($0.pathExtension.lowercased()) }
        }
        if let data = caseInsensitiveFile("Data", in: gameFolder),
           let inside = try? FileManager.default.contentsOfDirectory(at: data, includingPropertiesForKeys: nil) {
            let archives = inside.filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
            let hasKeyFile = archives.contains { proKeyFiles.contains($0.deletingPathExtension().lastPathComponent.lowercased()) }
            if hasKeyFile { return [] }
            candidates += archives
        }
        return candidates.filter { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 48), head.count == 48 else { return false }
            return isProHeader([UInt8](head))
        }.map(\.lastPathComponent).sorted()
    }

    /// Whether an archive header ("DX", version 8, flags at byte 44) is one of WOLF RPG Editor Pro.
    static func isProHeader(_ head: [UInt8]) -> Bool {
        guard head.count >= 48, head[0] == 0x44, head[1] == 0x58, head[2] == 8, head[3] == 0 else { return false }
        let cryptVersion = Int(head[46]) | Int(head[47]) << 8
        return cryptVersion >= 1000
    }

    /// A file's real path when the import changed the case of its folders or name.
    static func caseInsensitiveFile(_ relative: String, in folder: URL) -> URL? {
        var current = folder
        for part in relative.split(separator: "/") {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  let match = names.first(where: { $0.lowercased() == part.lowercased() }) else { return nil }
            current = current.appendingPathComponent(match)
        }
        return current
    }
}
