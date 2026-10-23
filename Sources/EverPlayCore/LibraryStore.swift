import Foundation

private struct LibraryDocument: Codable {
    var schemaVersion = 1
    var games: [GameRecord] = []
}

/// One writer serializes imports and atomic manifest updates. The UI never performs extraction.
public actor LibraryStore {
    public nonisolated let root: URL
    private var document: LibraryDocument
    private let manager = FileManager.default
    private var manifest: URL { root.appendingPathComponent("library.json") }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            do { document = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf: manifest)) }
            catch { throw EverPlayError.invalidLibrary }
            guard document.schemaVersion == 1 else { throw EverPlayError.unsupportedSchema(document.schemaVersion) }
            var ids: Set<UUID> = []
            var ports: Set<UInt16> = []
            for game in document.games {
                guard ids.insert(game.id).inserted, ports.insert(game.port).inserted,
                      (1024...65535).contains(game.port), UUID(uuidString: game.resourceToken) != nil,
                      game.fingerprint.count == 64,
                      (try? SafePath.components(game.entryPoint)) != nil else { throw EverPlayError.invalidLibrary }
            }
        } else { document = LibraryDocument() }
        for directory in ["Games", "Staging", "Recovery"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        // An interrupted archive can have moved files before its manifest update.
        // Restore those still-referenced games using their recovery record.
        let recoveryRoot = root.appendingPathComponent("Recovery")
        for recovery in try FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) {
            let recordURL = recovery.appendingPathComponent("record.json")
            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? JSONDecoder().decode(GameRecord.self, from: data),
                  document.games.contains(where: { $0.id == record.id }) else { continue }
            let original = root.appendingPathComponent("Games/\(record.id.uuidString)")
            let retained = recovery.appendingPathComponent("game")
            if !FileManager.default.fileExists(atPath: original.path) && FileManager.default.fileExists(atPath: retained.path) {
                try FileManager.default.moveItem(at: retained, to: original)
            }
        }
        // Interrupted imports are unreferenced. Preserve them in Recovery for inspection instead of deleting user data.
        let known = Set(document.games.map { $0.id.uuidString })
        for directory in ["Staging", "Games"] {
            let parent = root.appendingPathComponent(directory)
            for child in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                if directory == "Games" && known.contains(child.lastPathComponent) { continue }
                let recovery = root.appendingPathComponent("Recovery/\(UUID().uuidString)-\(child.lastPathComponent)")
                try FileManager.default.moveItem(at: child, to: recovery)
            }
        }
    }

    public func games() -> [GameRecord] { document.games.sorted { $0.importedAt > $1.importedAt } }
    public nonisolated func directory(for game: GameRecord) -> URL { root.appendingPathComponent("Games/\(game.id.uuidString)") }

    @discardableResult
    public func importZIP(at zip: URL, title: String? = nil, limits: ImportLimits = .init()) throws -> GameRecord {
        let prepared = try GameImporter(limits: limits).prepare(zip: zip, stagingParent: root.appendingPathComponent("Staging"))
        defer { try? manager.removeItem(at: prepared.directory) }
        guard !document.games.contains(where: { $0.fingerprint == prepared.fingerprint }) else { throw EverPlayError.duplicateGame }
        let used = Set(document.games.map(\.port))
        // Stay below iOS's ephemeral range (49152+), where system services such as device pairing
        // already listen on a real iPhone; the port is the game's storage origin, so it never changes.
        guard let port = (UInt16(30000)...UInt16(39999)).first(where: { !used.contains($0) }) else { throw EverPlayError.noAvailablePort }
        let game = GameRecord(id: UUID(), title: String((title ?? zip.deletingPathExtension().lastPathComponent).prefix(120)),
                              engine: prepared.validation.engine, entryPoint: prepared.validation.entryPoint,
                              fingerprint: prepared.fingerprint, importedAt: Date(), port: port,
                              resourceToken: UUID().uuidString, playSeconds: 0, controls: ControlSettings())
        let destination = directory(for: game)
        try manager.moveItem(at: prepared.directory, to: destination)
        var updated = document
        updated.games.append(game)
        do { try persist(updated) }
        catch { try? manager.removeItem(at: destination); throw error }
        return game
    }

    public func updateControls(id: UUID, settings: ControlSettings) throws {
        guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw EverPlayError.resourceNotFound }
        var updated = document
        var safe = settings
        safe.opacity = min(1, max(0.15, safe.opacity.isFinite ? safe.opacity : 0.65))
        safe.leftX = min(0.88, max(0.12, safe.leftX.isFinite ? safe.leftX : 0.18))
        safe.leftY = min(0.85, max(0.15, safe.leftY.isFinite ? safe.leftY : 0.74))
        safe.rightX = min(0.88, max(0.12, safe.rightX.isFinite ? safe.rightX : 0.82))
        safe.rightY = min(0.85, max(0.15, safe.rightY.isFinite ? safe.rightY : 0.74))
        updated.games[index].controls = safe
        try persist(updated)
    }

    public func recordPlay(id: UUID, seconds: TimeInterval) throws {
        guard let index = document.games.firstIndex(where: { $0.id == id }) else { return }
        var updated = document
        updated.games[index].playSeconds += seconds.isFinite ? max(0, seconds) : 0
        updated.games[index].lastPlayedAt = Date()
        try persist(updated)
    }

    /// Retain the installation in Recovery. Browser saves are retained in the per-game WebKit data store.
    public func archive(id: UUID) throws {
        guard let game = document.games.first(where: { $0.id == id }) else { return }
        let source = directory(for: game)
        let destination = root.appendingPathComponent("Recovery/\(UUID().uuidString)-\(id.uuidString)")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        // Keep identity, origin and settings alongside archived files for a future recovery UI.
        try JSONEncoder().encode(game).write(to: destination.appendingPathComponent("record.json"), options: .atomic)
        let retained = destination.appendingPathComponent("game")
        try manager.moveItem(at: source, to: retained)
        var updated = document
        updated.games.removeAll { $0.id == id }
        do { try persist(updated) }
        catch { try? manager.moveItem(at: retained, to: source); throw error }
    }

    private func persist(_ updated: LibraryDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try data.write(to: manifest, options: .atomic)
        document = updated
    }
}
