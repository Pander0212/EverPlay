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

    /// The official downloads (rpgmakerweb.com › Run Time Package) for the names in Game.ini.
    static let officialDownloads: [String: String] = [
        "rpgvxace": "https://assets.rpgmakerweb.com/RPGVXAce_RTP.zip",
        "rpgvx": "https://assets.rpgmakerweb.com/vx_rtp102e.zip",
        "standard": "https://assets.rpgmakerweb.com/xp_rtp104e.exe",
    ]

    public static func officialDownload(for name: String) -> URL? {
        officialDownloads[name.lowercased()].flatMap(URL.init(string:))
    }

    /// Installs an RTP as `name` from a ZIP with its Graphics and Audio folders, or from the
    /// official installer (Setup.exe, alone or in its ZIP), which is unpacked without running it.
    public static func install(package: URL, name: String, into root: URL, importer: GameImporter = .init()) throws {
        guard let target = folder(name, in: root) else { throw EverPlayError.unsafePath(name) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let unpacked = staging.appendingPathComponent("app", isDirectory: true)
        if package.pathExtension.lowercased() == "exe" {
            try InnoSetupArchive(setup: package).extract(into: unpacked)
        } else {
            let archive = staging.appendingPathComponent("zip", isDirectory: true)
            let files = try importer.extractArchive(zip: package, into: archive)
            if runtimeFolder(in: archive) == nil {
                let installer = files.map { archive.appendingPathComponent($0.path) }
                    .filter { $0.pathExtension.lowercased() == "exe" }
                    .first(where: InnoSetupArchive.isInstaller)
                guard let installer else { throw EverPlayError.notRuntimePackage }
                try InnoSetupArchive(setup: installer).extract(into: unpacked)
            }
        }
        guard let base = runtimeFolder(in: staging) else { throw EverPlayError.notRuntimePackage }
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: base, to: target)
    }

    /// The shallowest folder that holds a Graphics or Audio folder.
    static func runtimeFolder(in folder: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        var best: (URL, Int)?
        for case let url as URL in walker where ["graphics", "audio"].contains(url.lastPathComponent.lowercased()) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let depth = url.pathComponents.count
            if best == nil || depth < best!.1 { best = (url.deletingLastPathComponent(), depth) }
        }
        return best?.0
    }

    /// Points mkxp-z at the installed RTPs the game asks for. Returns the names still missing.
    @discardableResult
    /// `preloadScripts` run before the game's own scripts (EverPlay's cheat menu).
    public static func configure(gameFolder: URL, root: URL, preloadScripts: [URL] = []) throws -> [String] {
        let wanted = names(gameFolder: gameFolder)
        let installed = wanted.compactMap { name in isInstalled(name, in: root) ? folder(name, in: root) : nil }
        let config = gameFolder.appendingPathComponent("mkxp.json")
        let marker = gameFolder.appendingPathComponent(Self.marker)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: config.path) || fileManager.fileExists(atPath: marker.path) {
            let json = try JSONSerialization.data(withJSONObject: ["RTP": installed.map(\.path),
                                                                   "preloadScript": preloadScripts.map(\.path)],
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try json.write(to: config, options: .atomic)
            try Data().write(to: marker)
        }
        return wanted.filter { !isInstalled($0, in: root) }
    }
}
