import Foundation

/// ONScripter games run in OnscripterYuri's WebAssembly build (onsyuri.html, .js, .wasm; GPL-2.0),
/// which EverPlay ships. Before a game starts, the build is copied next to the game's script with
/// an onsyuri_index.json that lists the game's files; OnscripterYuri then fetches each file from
/// EverPlay's game server the first time the game reads it.
public enum ONScripterShell {
    public static let page = "onsyuri.html"
    public static let files = ["onsyuri.html", "onsyuri.js", "onsyuri.wasm"]
    static let index = "onsyuri_index.json"
    /// File names (lowercased) of an ONScripter script, plain or in one of the encoded forms.
    static let scriptNames: Set<String> = ["0.txt", "00.txt", "nscript.dat", "nscr_sec.dat", "nscript.___",
                                           "onscript.nt", "onscript.nt2", "onscript.nt3", "pscript.dat"]

    /// Copies the build from `shell` into the game folder (replacing an older copy) and writes the
    /// file index. Saves stay in the game's browser storage under `/onsyuri_save/game`.
    public static func install(shell: URL, gameFolder: URL) throws {
        let manager = FileManager.default
        for name in files {
            let source = shell.appendingPathComponent(name)
            let target = gameFolder.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path) else { throw EverPlayError.incompleteEngine("ONScripter") }
            if let attributes = try? manager.attributesOfItem(atPath: target.path) {
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EverPlayError.unsafePath(name) }
                if manager.contentsEqual(atPath: source.path, andPath: target.path) { continue }
                try manager.removeItem(at: target)
            }
            try manager.copyItem(at: source, to: target)
        }
        let own = Set(files + [index])
        var entries: [[String: String]] = []
        let root = gameFolder.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        if let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator {
                let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
                guard (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      resolved.pathComponents.starts(with: rootComponents) else { continue }
                let path = resolved.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
                if own.contains(path) { continue }
                let encoded = path.split(separator: "/").map {
                    String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? String($0)
                }.joined(separator: "/")
                entries.append(["path": path, "url": encoded])
            }
        }
        entries.sort { $0["path"]! < $1["path"]! }
        let document: [String: Any] = ["title": "game", "gamedir": "/onsyuri/game", "savedir": "/onsyuri_save/game",
                                       "args": [String](), "lazyload": true, "files": entries]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: gameFolder.appendingPathComponent(index), options: .atomic)
    }
}
