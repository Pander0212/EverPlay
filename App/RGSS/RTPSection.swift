import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

/// On an XP/VX/VX Ace game's page: which RTP the game needs, downloading it from rpgmakerweb.com
/// or importing it from a file.
struct RTPSection: View {
    let gameFolder: URL
    @State private var names: [String]
    @State private var installed: Set<String> = []
    @State private var working: String?
    @State private var status: String?
    @State private var message: String?

    init(gameFolder: URL) {
        self.gameFolder = gameFolder
        let names = RGSSRuntimePackage.names(gameFolder: gameFolder)
        _names = State(initialValue: names)
        _installed = State(initialValue: Set(names.filter { RGSSRuntimePackage.isInstalled($0, in: MKXPLauncher.rtpRoot) }))
    }

    var body: some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("RPG Maker RTP", systemImage: "shippingbox").font(.headline)
                ForEach(names, id: \.self) { name in
                    HStack {
                        Image(systemName: installed.contains(name) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(installed.contains(name) ? .green : .orange)
                        Text(name)
                        Spacer()
                        if working == name {
                            ProgressView()
                        } else {
                            Menu(installed.contains(name) ? "Replace" : "Get RTP") {
                                if RGSSRuntimePackage.officialDownload(for: name) != nil {
                                    Button("Download from rpgmakerweb.com", systemImage: "arrow.down.circle") { download(name) }
                                }
                                Button("Import file…", systemImage: "folder") { pick(name) }
                            }
                            .disabled(working != nil)
                        }
                    }
                    if working == name, let status {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("This game uses shared graphics and sounds from the RPG Maker RTP. EverPlay downloads the free official RTP and unpacks its installer without running it. A ZIP with the RTP's Graphics and Audio folders also works. It is stored once for every game that needs it.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .surface(cornerRadius: 22)
        }
    }

    private func refresh() {
        names = RGSSRuntimePackage.names(gameFolder: gameFolder)
        installed = Set(names.filter { RGSSRuntimePackage.isInstalled($0, in: MKXPLauncher.rtpRoot) })
    }

    private func download(_ name: String) {
        guard let source = RGSSRuntimePackage.officialDownload(for: name) else { return }
        start(name, status: "Downloading from rpgmakerweb.com…")
        Task {
            do {
                let (temporary, response) = try await URLSession.shared.download(from: source)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                // install(package:) tells an installer from a ZIP by its extension.
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
                try FileManager.default.moveItem(at: temporary, to: file)
                await install(file, name: name)
            } catch {
                finish(name, error: error.localizedDescription)
            }
        }
    }

    private func pick(_ name: String) {
        let types = [UTType.zip] + [UTType(filenameExtension: "exe")].compactMap { $0 }
        FilePicker.present(types: types, asCopy: true) { url in
            start(name, status: nil)
            Task { await install(url, name: name) }
        }
    }

    private func start(_ name: String, status: String?) {
        working = name
        self.status = status
        message = nil
    }

    private func install(_ file: URL, name: String) async {
        status = "Unpacking…"
        let root = MKXPLauncher.rtpRoot
        let error: String? = await Task.detached {
            do {
                try RGSSRuntimePackage.install(package: file, name: name, into: root)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        try? FileManager.default.removeItem(at: file)
        finish(name, error: error)
    }

    private func finish(_ name: String, error: String?) {
        EverPlayLog.write("RTP \(name): \(error ?? "installed")")
        message = error
        working = nil
        status = nil
        refresh()
    }
}
