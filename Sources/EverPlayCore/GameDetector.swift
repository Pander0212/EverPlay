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
        var legacy = false
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
            if ["rxdata", "rvdata", "rvdata2", "rpa", "pck", "ldb"].contains(url.pathExtension.lowercased()) { legacy = true }
            if url.lastPathComponent == "index.html", try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                entries.append(relative)
            }
        }
        if let scanError { throw scanError }
        guard !entries.isEmpty else { throw legacy ? EverPlayError.unsupportedGame : .missingEntryPoint }
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
}
