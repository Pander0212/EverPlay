import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

@MainActor
final class LibraryModel: ObservableObject {
    @Published var games: [GameRecord] = []
    @Published var importing = false
    @Published var error: String?
    @Published var selectedGame: GameRecord?
    @Published var importMessage: String?
    /// Game folders and ZIPs the user placed in On My iPhone › EverPlay.
    @Published var inbox: [URL] = []
    let store: LibraryStore?
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            store = try LibraryStore(root: support.appendingPathComponent("EverPlay", isDirectory: true))
        } catch { store = nil; self.error = error.localizedDescription }
        // The Files app only lists an app's folder once it contains something.
        let readme = documents.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? Data(Self.readmeText.utf8).write(to: readme, options: .atomic)
        }
    }
    private static let readmeText = """
        EverPlay
        Put a game folder or a game ZIP here, then open EverPlay › Import and tap it.
        The game is checked and copied into EverPlay; you can delete it here afterwards.

        Lege hier einen Spielordner oder eine Spiel-ZIP ab und tippe sie dann in EverPlay unter Import an.
        Das Spiel wird geprüft und in EverPlay kopiert; danach kannst du es hier löschen.
        """
    func refresh() async {
        if let store { games = await store.games() }
        refreshInbox()
    }
    func refreshInbox() {
        let items = (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        inbox = items.filter { url in
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return directory || url.pathExtension.lowercased() == "zip"
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    func importZIP(_ url: URL, title: String? = nil) async {
        guard !importing, let store else { return }
        importing = true; importMessage = nil
        defer { importing = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            // Document-provider materialization and a stable private copy happen away from the main thread.
            let local = try await Task.detached(priority: .userInitiated) {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var copyError: Error?
                coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
                    do {
                        let values = try readable.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                        if values.isDirectory == true && values.isSymbolicLink != true {
                            // A game folder is packed into a private ZIP and then passes the same importer checks.
                            try GameImporter.packFolder(readable, to: copy)
                            let packed = try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max
                            guard packed <= Int(ImportLimits().maximumArchiveBytes) else { throw EverPlayError.limitExceeded("archive size") }
                            return
                        }
                        guard values.isRegularFile == true, values.isSymbolicLink != true else {
                            throw EverPlayError.unsupportedEntry(readable.lastPathComponent)
                        }
                        let limit = Int(ImportLimits().maximumArchiveBytes)
                        guard let size = values.fileSize, size <= limit else { throw EverPlayError.limitExceeded("archive size") }
                        guard FileManager.default.createFile(atPath: copy.path, contents: nil) else { throw EverPlayError.invalidArchive }
                        let input = try FileHandle(forReadingFrom: readable)
                        defer { try? input.close() }
                        let output = try FileHandle(forWritingTo: copy)
                        defer { try? output.close() }
                        var copied = 0
                        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                            try Task.checkCancellation()
                            copied += chunk.count
                            guard copied <= limit else { throw EverPlayError.limitExceeded("archive size") }
                            try output.write(contentsOf: chunk)
                        }
                    } catch { copyError = error }
                }
                if let error = coordinationError { try? FileManager.default.removeItem(at: copy); throw error }
                if let error = copyError { try? FileManager.default.removeItem(at: copy); throw error }
                return copy
            }.value
            defer { try? FileManager.default.removeItem(at: local) }
            let game = try await store.importZIP(at: local, title: title ?? url.deletingPathExtension().lastPathComponent)
            await refresh()
            importMessage = "\(game.title) is ready in your library."
        } catch { self.error = error.localizedDescription }
    }
    func importDemo() async {
        guard let url = Bundle.main.url(forResource: "EverPlayDemo", withExtension: "zip") else {
            error = "The demo ZIP is missing from this build."; return
        }
        await importZIP(url, title: "Lantern Garden")
    }
    func archive(_ game: GameRecord) async {
        do { try await store?.archive(id: game.id); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
