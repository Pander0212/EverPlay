import Foundation
import EverPlayCore

/// One way in for every import path: file and folder pickers, the EverPlay folder in Files,
/// "Open in EverPlay" and URL downloads. Ren'Py games (folders or ZIPs) go to the Ren'Py
/// library, everything else through the checked web-game importer.
@MainActor
enum GameImport {
    static func run(_ url: URL, library: LibraryModel, renpy: RenPyLibrary) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        EverPlayLog.write("Import \(isDirectory ? "folder" : "file") \(url.lastPathComponent) (security scope: \(accessed))")
        if isDirectory {
            if await renpy.install(folder: url) { return }
            await library.importZIP(url)
        } else if GameImporter.archiveContainsRenPyGame(url) {
            await renpy.install(zip: url)
        } else {
            await library.importZIP(url)
        }
    }
}

/// Downloads a game archive from a direct link, then imports it like a picked file.
@MainActor
final class URLImporter: ObservableObject {
    @Published private(set) var downloading: String?
    @Published var message: String?

    func download(_ text: String, library: LibraryModel, renpy: RenPyLibrary) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            message = "Enter a link that starts with https://"
            return
        }
        downloading = url.host ?? url.absoluteString
        defer { downloading = nil }
        EverPlayLog.write("Downloading \(url.host ?? "?")\(url.path)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            if response.mimeType == "text/html" {
                // Hosting pages (Mega, Google Drive previews, …) return a web page, not the file.
                try? FileManager.default.removeItem(at: temporary)
                message = "This link opens a web page, not a file. Use the host's direct download link."
                EverPlayLog.write("Download returned a web page instead of a file")
                return
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = response.suggestedFilename ?? (url.lastPathComponent.isEmpty ? "download.zip" : url.lastPathComponent)
            let file = folder.appendingPathComponent(name)
            try FileManager.default.moveItem(at: temporary, to: file)
            EverPlayLog.write("Downloaded \(name)")
            await GameImport.run(file, library: library, renpy: renpy)
        } catch {
            EverPlayLog.write("Download failed: \(error)")
            message = "The download failed: \(error.localizedDescription)"
        }
    }
}
