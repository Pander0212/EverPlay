import Foundation

/// The RPG Maker XP/VX/VX Ace run time packages (RTP): shared graphics and sounds that many games
/// leave out. Each one is kept once under its Game.ini name (Standard, RPGVX, RPGVXAce) and handed
/// to mkxp-z through an mkxp.json in the game's folder.
public enum RGSSRuntimePackage {
    /// mkxp.json written by EverPlay; a game's own mkxp.json is left alone.
    static let marker = ".everplay-mkxp"

    /// The RTP names a game asks for: `RTP=` (VX, VX Ace) and `RTP1=`…`RTP3=` (XP) in [Game].
    public static func names(gameIni: String) -> [String] {
        var inGame = false
        var names: [String] = []
        for raw in gameIni.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inGame = line.lowercased() == "[game]"
                continue
            }
            guard inGame, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard ["rtp", "rtp1", "rtp2", "rtp3"].contains(key), !value.isEmpty, !names.contains(value) else { continue }
            names.append(value)
        }
        return names
    }

    public static func names(gameFolder: URL) -> [String] {
        guard let data = try? Data(contentsOf: gameFolder.appendingPathComponent("Game.ini")) else { return [] }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return names(gameIni: text)
    }

    /// A name safe to use as a folder (Game.ini is game data).
    static func folderName(_ name: String) -> String? {
        let cleaned = name.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
        return cleaned.isEmpty || cleaned.count > 64 ? nil : cleaned
    }

    public static func folder(_ name: String, in root: URL) -> URL? {
        folderName(name).map { root.appendingPathComponent($0, isDirectory: true) }
    }

    public static func isInstalled(_ name: String, in root: URL) -> Bool {
        guard let folder = folder(name, in: root) else { return false }
        return FileManager.default.fileExists(atPath: folder.path)
    }

    /// Installs an RTP from a ZIP: the shallowest folder with Graphics or Audio becomes `name`.
    public static func install(zip: URL, name: String, into root: URL, importer: GameImporter = .init()) throws {
        guard let target = folder(name, in: root) else { throw EverPlayError.unsafePath(name) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let files = try importer.extractArchive(zip: zip, into: staging)
        let roots = files.compactMap { file -> String? in
            let parts = file.path.split(separator: "/")
            guard let index = parts.firstIndex(where: { ["graphics", "audio"].contains($0.lowercased()) }) else { return nil }
            return parts[..<index].joined(separator: "/")
        }
        guard let base = roots.min(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) else {
            throw EverPlayError.notRuntimePackage
        }
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: base.isEmpty ? staging : staging.appendingPathComponent(base), to: target)
    }

    /// Points mkxp-z at the installed RTPs the game asks for. Returns the names still missing.
    @discardableResult
    public static func configure(gameFolder: URL, root: URL) throws -> [String] {
        let wanted = names(gameFolder: gameFolder)
        let installed = wanted.compactMap { name in isInstalled(name, in: root) ? folder(name, in: root) : nil }
        let config = gameFolder.appendingPathComponent("mkxp.json")
        let marker = gameFolder.appendingPathComponent(Self.marker)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: config.path) || fileManager.fileExists(atPath: marker.path) {
            let json = try JSONSerialization.data(withJSONObject: ["RTP": installed.map(\.path)],
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try json.write(to: config, options: .atomic)
            try Data().write(to: marker)
        }
        return wanted.filter { !isInstalled($0, in: root) }
    }
}
