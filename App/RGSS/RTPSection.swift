import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

/// On an XP/VX/VX Ace game's page: which RTP the game needs, and importing it from a ZIP.
struct RTPSection: View {
    let gameFolder: URL
    @State private var names: [String]
    @State private var installed: Set<String> = []
    @State private var working: String?
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
                            Button(installed.contains(name) ? "Replace" : "Import ZIP") { pick(name) }
                                .disabled(working != nil)
                        }
                    }
                }
                Text("This game uses shared graphics and sounds from the RTP. Import a ZIP with the RTP's Graphics and Audio folders (copied from a PC where it is installed). It is stored once and used by every game that needs it.")
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

    private func pick(_ name: String) {
        FilePicker.present(types: [.zip], asCopy: true) { url in
            working = name
            message = nil
            let root = MKXPLauncher.rtpRoot
            Task {
                let error: String? = await Task.detached {
                    do {
                        try RGSSRuntimePackage.install(zip: url, name: name, into: root)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                try? FileManager.default.removeItem(at: url)
                EverPlayLog.write("RTP \(name) import: \(error ?? "done")")
                message = error
                working = nil
                refresh()
            }
        }
    }
}
