import SwiftUI
import EverPlayCore

/// A game's page: big cover, facts, per-game options and the actions that do not belong on the
/// library card.
struct GameDetailView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var renpy: RenPyLibrary
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    let play: () -> Void
    let remove: () -> Void
    @State private var size: Int64?
    @State private var translate = false
    @State private var reportText: String?

    /// The current version from the library, so a changed runtime shows right away.
    private var current: LibraryItem {
        if case .renpy(let game) = item, let fresh = renpy.games.first(where: { $0.folder == game.folder }) {
            return .renpy(fresh)
        }
        return item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(GlowButtonStyle())
                .accessibilityIdentifier("detailPlay")
                facts
                if case .renpy(let game) = current {
                    translationOptions(game)
                    runtimeOptions(game)
                }
                if case .renpy(let game) = current { reports(game) }
                storage
                Button(role: .destructive) {
                    remove()
                } label: {
                    Label(removeTitle, systemImage: removeIcon).foregroundStyle(.red)
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { size = await Self.measure(folder) }
        .sheet(isPresented: Binding(get: { reportText != nil }, set: { if !$0 { reportText = nil } })) {
            NavigationStack {
                ScrollView {
                    Text(reportText ?? "").font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle("Error report").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reportText = nil } } }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            CoverView(item: current, cornerRadius: 28)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(current.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(current.engineLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(current.tint.opacity(0.55), in: Capsule())
            }
            .padding(18)
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var facts: some View {
        VStack(spacing: 0) {
            fact("Played", value: current.playtime, icon: "clock")
            Divider().opacity(0.4)
            fact("Last played", icon: "calendar") {
                if let last = current.lastPlayed {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
            }
            Divider().opacity(0.4)
            fact("Size", value: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…",
                 icon: "internaldrive")
            if case .renpy(let game) = current {
                Divider().opacity(0.4)
                fact("Made with", value: game.engineVersion.map { "Ren'Py \($0)" } ?? "Unknown", icon: "hammer")
                Divider().opacity(0.4)
                fact("Runs on", value: game.runtime.map { "\($0.title) (\($0.version))" } ?? "No matching runtime",
                     icon: "cpu")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .surface(cornerRadius: 22)
    }

    private func translationOptions(_ game: RenPyTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { translate }, set: { translate = $0; TranslationPreferences.setEnabled($0, for: game.folder) })) {
                Label("Translate this game", systemImage: "character.bubble").font(.headline)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("translateGame")
            Text(TranslationPreferences.settings.provider == .off
                 ? "Choose a translation service in Settings › Translation first."
                 : "Dialogue and choices are translated with \(TranslationPreferences.settings.provider.title) into “\(TranslationPreferences.settings.targetLanguage)” while you play; each line is translated once and remembered. The in-game menu switches between original and translation.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .surface(cornerRadius: 22)
        .onAppear { translate = TranslationPreferences.isEnabled(for: game.folder) }
    }

    private func runtimeOptions(_ game: RenPyTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ren'Py runtime").font(.headline)
            Picker("Runtime", selection: Binding(get: { game.runtimeChoice ?? "" },
                                                 set: { renpy.setRuntime($0.isEmpty ? nil : $0, for: game) })) {
                Text("Automatic").tag("")
                ForEach(renpy.runtimes) { runtime in
                    Text(runtime.title).tag(runtime.id)
                }
            }
            .pickerStyle(.segmented)
            Text("Automatic uses the version the game was made with when it is included, otherwise the newest of the same major version. Try another one if a game shows an error at start.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .surface(cornerRadius: 22)
    }

    /// Ren'Py writes traceback.txt (errors while playing), errors.txt (script errors) and log.txt
    /// into the game folder on iOS.
    @ViewBuilder
    private func reports(_ game: RenPyTitle) -> some View {
        let folder = renpy.folder(of: game)
        let files = ["traceback.txt", "errors.txt", "log.txt"].map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Reports from Ren'Py", systemImage: "doc.text.magnifyingglass").font(.headline)
                ForEach(files, id: \.self) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent).font(.subheadline.weight(.semibold))
                            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                                Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("View") { reportText = (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
                            .buttonStyle(.bordered)
                        ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                }
                Text("traceback.txt explains the last error while playing; send it when a game stops with an error.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .surface(cornerRadius: 22)
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Files and saves", systemImage: "folder").font(.headline)
            switch current {
            case .renpy(let game):
                Text("Game: On My iPhone › EverPlay › Ren'Py › \(game.folder)\nSaves: On My iPhone › EverPlay › Saves › \(game.folder)")
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            case .web:
                Text("Stored in EverPlay's private storage with the game's own browser saves.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surface(cornerRadius: 22)
    }

    private func fact(_ title: String, value: String, icon: String) -> some View {
        fact(title, icon: icon) { Text(value) }
    }

    private func fact<Value: View>(_ title: String, icon: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            value().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 11)
    }

    private var removeTitle: String {
        if case .renpy = item { return "Delete game" }
        return "Archive game"
    }
    private var removeIcon: String {
        if case .renpy = item { return "trash" }
        return "archivebox"
    }

    private var folder: URL? {
        switch item {
        case .renpy(let game): return renpy.folder(of: game)
        case .web(let game, _): return library.store?.directory(for: game)
        }
    }

    private static func measure(_ folder: URL?) async -> Int64? {
        guard let folder else { return nil }
        return await Task.detached(priority: .utility) { () -> Int64 in
            var total: Int64 = 0
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
            while let file = files?.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
            }
            return total
        }.value
    }
}
