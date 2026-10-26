import Foundation

public struct WebGameAdapter: GameEngineAdapter {
    public let engineIdentifier: GameEngine
    public var capabilities: EngineCapabilities { [.touch, .keyboard, .browserStorage] }
    public init(engine: GameEngine = .html5) { engineIdentifier = engine }
    public func validateGame(at root: URL) throws -> GameValidationResult {
        let result = try GameDetector.detect(at: root)
        guard result.engine == engineIdentifier else { throw EverPlayError.unsupportedGame }
        return result
    }
}

public enum GameDetector {
    public static func detect(at suppliedRoot: URL) throws -> GameValidationResult {
        // Darwin enumerators resolve aliases such as /var -> /private/var in returned URLs.
        // Use the same canonical base before deriving relative paths or resolving engine files.
        let root = suppliedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let manager = FileManager.default
        var scanError: Error?
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                   errorHandler: { _, error in scanError = error; return false }) else {
            throw EverPlayError.missingEntryPoint
        }
        var entries: [String] = []
        // Other pages, for games that are a single HTML file (Twine/SugarCube such as Degrees of Lewdity).
        var pages: [(path: String, size: Int)] = []
        var legacy = false
        // RPG Maker 2000/2003: RPG_RT.ldb (database) next to RPG_RT.lmt (map tree).
        var databases: [String] = []
        var mapTrees: Set<String> = []
        // ONScripter: its script (0.txt, 00.txt or an encrypted nscript.dat and the like).
        var onsScripts: [String] = []
        // RPG Maker XP/VX/VX Ace: Game.ini next to an encrypted archive or Data/Scripts.*.
        var gameInis: [String] = []
        var rgssFolders: Set<String> = []
        // KiriKiri: data.xp3 (or other .xp3 archives) or startup.tjs, usually beside the game's .exe.
        var kirikiriEntries: [String] = []
        // Godot: a .pck, or a pack appended to the .exe (read from their headers below).
        var godotFiles: [String] = []
        var webAssembly = false
        // Every file, to name the engine of a game EverPlay cannot play (EngineFingerprint).
        var allPaths: [String] = []
        let rootComponents = root.pathComponents
        for case let enumeratedURL as URL in enumerator {
            let url = enumeratedURL.standardizedFileURL.resolvingSymlinksInPath()
            let components = url.pathComponents
            guard components.count > rootComponents.count,
                  components.starts(with: rootComponents) else {
                throw EverPlayError.unsafePath("resource outside game root: \(enumeratedURL.lastPathComponent)")
            }
            let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
            if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) { continue }
            if allPaths.count < 50_000 { allPaths.append(relative) }
            if ["rxdata", "rvdata", "rvdata2", "rpa", "pck", "ldb"].contains(url.pathExtension.lowercased()) { legacy = true }
            switch url.pathExtension.lowercased() {
            case "pck", "exe": if godotFiles.count < 64 { godotFiles.append(relative) }
            case "wasm": webAssembly = true
            default: break
            }
            switch url.lastPathComponent.lowercased() {
            case "rpg_rt.ldb": databases.append(relative)
            case "rpg_rt.lmt": mapTrees.insert((relative as NSString).deletingLastPathComponent.lowercased())
            case let name where ONScripterShell.scriptNames.contains(name): onsScripts.append(relative)
            case "game.ini": gameInis.append(relative)
            case "data.xp3", "startup.tjs": kirikiriEntries.append(relative)
            case "game.rgssad", "game.rgss2a", "game.rgss3a":
                rgssFolders.insert((relative as NSString).deletingLastPathComponent.lowercased())
            case "scripts.rxdata", "scripts.rvdata", "scripts.rvdata2":
                let data = (relative as NSString).deletingLastPathComponent
                if (data as NSString).lastPathComponent.lowercased() == "data" {
                    rgssFolders.insert((data as NSString).deletingLastPathComponent.lowercased())
                }
            default: break
            }
            let pageExtension = ["html", "htm"].contains(url.pathExtension.lowercased())
            if pageExtension, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                if url.lastPathComponent == "index.html" {
                    entries.append(relative)
                } else if url.lastPathComponent.lowercased() != "credits.html" {  // NW.js's own licence page
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    pages.append((relative, size))
                }
            }
        }
        if let scanError { throw scanError }
        let games2000 = databases.filter { mapTrees.contains(($0 as NSString).deletingLastPathComponent.lowercased()) }
        if let database = games2000.min(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            return GameValidationResult(engine: .rpgMaker2000, entryPoint: database, warnings: [
                "Games that need the original RTP show missing graphics until an RTP is added."
            ])
        }
        let rgssGames = gameInis.filter { rgssFolders.contains(($0 as NSString).deletingLastPathComponent.lowercased()) }
        if let ini = rgssGames.min(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            return GameValidationResult(engine: .rgss, entryPoint: ini, warnings: [
                "Games that need the RPG Maker RTP show missing graphics or sounds until an RTP is added."
            ])
        }
        if let entry = kirikiriEntries.min(by: { ($0.split(separator: "/").count, $0.hasSuffix(".tjs") ? 1 : 0)
                                                  < ($1.split(separator: "/").count, $1.hasSuffix(".tjs") ? 1 : 0) }) {
            return GameValidationResult(engine: .kirikiri, entryPoint: entry, warnings: [
                "Games with encrypted archives need their scheme from GARbro's database."
            ])
        }
        // Godot's web exports (.wasm next to the page) play in the web player.
        if !webAssembly, let godot = try godotGame(root: root, candidates: godotFiles) { return godot }
        if entries.isEmpty, let script = onsScripts.min(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            let folder = (script as NSString).deletingLastPathComponent
            let hasFont = manager.fileExists(atPath: root.appendingPathComponent(folder).appendingPathComponent("default.ttf").path)
            return GameValidationResult(engine: .onscripter, entryPoint: (folder.isEmpty ? "" : folder + "/") + ONScripterShell.page,
                                        warnings: hasFont ? [] : ["The game has no default.ttf; text needs that font."])
        }
        if entries.isEmpty, !legacy, !pages.isEmpty {
            // No index.html: take the page closest to the top, the largest if several are equally
            // close (a story file outweighs its credits or readme page).
            let depth = pages.map { $0.path.split(separator: "/").count }.min()!
            entries = [pages.filter { $0.path.split(separator: "/").count == depth }.max { $0.size < $1.size }!.path]
        }
        guard !entries.isEmpty else {
            if let report = EngineFingerprint.identify(paths: allPaths), !report.playable {
                throw EverPlayError.recognizedEngine(report)
            }
            throw legacy ? EverPlayError.unsupportedGame : .missingEntryPoint
        }
        // Prefer a package root, or the conventional NW.js www root. Otherwise require a single shallowest root.
        let entry: String
        if entries.contains("index.html") { entry = "index.html" }
        else if entries.contains("www/index.html") { entry = "www/index.html" }
        else {
            let depth = entries.map { $0.split(separator: "/").count }.min()!
            let candidates = entries.filter { $0.split(separator: "/").count == depth }
            guard candidates.count == 1 else { throw EverPlayError.ambiguousEntryPoints }
            entry = candidates[0]
        }
        let gameRoot = root.appendingPathComponent(entry).deletingLastPathComponent()
        func exists(_ file: String) -> Bool { manager.fileExists(atPath: gameRoot.appendingPathComponent(file).path) }
        let engine: GameEngine = exists("js/rmmz_core.js") ? .rpgMakerMZ : exists("js/rpg_core.js") ? .rpgMakerMV : .html5
        if engine != .html5 && !exists("data/System.json") { throw EverPlayError.incompleteEngine(engine.title) }
        return GameValidationResult(engine: engine, entryPoint: entry, warnings: engine == .html5 ? [] : [
            "Desktop Node.js plugins and proprietary media codecs may not work in WebKit."
        ])
    }

    /// The Godot pack closest to the top (a .pck before an .exe with an embedded one), or nil. A
    /// pack EverPlay cannot play (Godot 3, encrypted, newer than its runtimes) stops the import with the reason.
    static func godotGame(root: URL, candidates: [String]) throws -> GameValidationResult? {
        let ordered = candidates.sorted {
            ($0.split(separator: "/").count, $0.lowercased().hasSuffix(".pck") ? 0 : 1, $0)
                < ($1.split(separator: "/").count, $1.lowercased().hasSuffix(".pck") ? 0 : 1, $1)
        }
        for path in ordered {
            guard let pack = GodotPack.read(root.appendingPathComponent(path)) else { continue }
            let runtime = try GodotRuntime.framework(for: pack)
            return GameValidationResult(engine: .godot, entryPoint: path, warnings: [
                "Made with Godot \(pack.version); plays on EverPlay's \(runtime.dropFirst(5).map(String.init).joined(separator: ".")) runtime. Games with C# or native plug-ins do not run."
            ])
        }
        return nil
    }
}
