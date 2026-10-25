import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var coverError: String?
    @State private var pretranslating: PretranslateJob?
    /// Bumped when the cover changes, so the library and this page show the new one.
    @AppStorage("library.coverVersion") private var coverVersion = 0

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
                switch current {
                case .renpy(let game):
                    translationOptions(key: game.folder, gameRoot: nil)
                    runtimeOptions(game)
                case .web(let game, _):
                    if game.engine == .rpgMakerMV || game.engine == .rpgMakerMZ {
                        translationOptions(key: GameSession.translationKey(game),
                                           gameRoot: library.store.map { $0.directory(for: game).appendingPathComponent(game.entryPoint).deletingLastPathComponent() })
                    }
                    if game.engine == .rgss, let directory = library.store?.directory(for: game) {
                        RTPSection(gameFolder: MKXPLauncher.gameFolder(game, directory: directory))
                    }
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
        .sheet(item: $pretranslating) { job in PretranslateView(job: job) }
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
        let _ = coverVersion
        return ZStack(alignment: .bottomLeading) {
            CoverView(item: current, cornerRadius: 0)
                .scaleEffect(1.4)
                .blur(radius: 30)
                .overlay(LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: 16) {
                CoverView(item: current, cornerRadius: 18)
                    .frame(width: 120, height: 160)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(current.engineLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(current.tint.opacity(0.55), in: Capsule())
                    Menu {
                        Button("Choose from Photos", systemImage: "photo") { pickingPhoto = true }
                        Button("Choose from Files", systemImage: "folder") {
                            FilePicker.present(types: [.image], asCopy: true) { url in
                                setCover(UIImage(contentsOfFile: url.path))
                            }
                        }
                        if CustomCovers.url(for: current.id) != nil {
                            Button("Use the game's picture", systemImage: "arrow.uturn.backward") {
                                CustomCovers.remove(current.id)
                                coverVersion += 1
                            }
                        }
                    } label: {
                        Label("Change cover", systemImage: "photo.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    .accessibilityIdentifier("changeCover")
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                setCover(data.flatMap(UIImage.init(data:)))
                photo = nil
            }
        }
        .alert("Cover not changed", isPresented: Binding(get: { coverError != nil }, set: { if !$0 { coverError = nil } })) {
            Button("OK") { coverError = nil }
        } message: { Text(coverError ?? "") }
    }

    private func setCover(_ image: UIImage?) {
        guard let image else { coverError = "The picture could not be read."; return }
        do {
            try CustomCovers.set(image, for: current.id)
            coverVersion += 1
        } catch {
            coverError = error.localizedDescription
        }
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

    private func translationOptions(key: String, gameRoot: URL?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { translate }, set: { translate = $0; TranslationPreferences.setEnabled($0, for: key) })) {
                Label("Translate this game", systemImage: "character.bubble").font(.headline)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("translateGame")
            Text(TranslationPreferences.settings.provider == .off
                 ? "Choose a translation service in Settings › Translation first."
                 : "Dialogue and choices are translated with \(TranslationPreferences.settings.provider.title) into “\(TranslationPreferences.settings.targetLanguage)” while you play; each line is translated once and remembered. The game menu switches between original and translation.")
                .font(.footnote).foregroundStyle(.secondary)
            if TranslationPreferences.settings.provider != .off {
                let language = TranslationPreferences.settings.targetLanguage
                NavigationLink {
                    TranslationMemoryView(game: key, language: language)
                } label: {
                    Label("Edit translations", systemImage: "text.badge.checkmark").font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("editTranslations")
                if translate {
                    if let gameRoot {
                        Button { pretranslating = PretranslateJob(key: key, gameRoot: gameRoot) } label: {
                            Label("Translate the whole game now", systemImage: "text.badge.star").font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("translateWholeGame")
                        Text("Translates every message and choice before you play, like MTool, so lines appear without waiting.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("To translate the whole game up front: start it, then ☰ › Translate whole game. It continues in the background while you play.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .surface(cornerRadius: 22)
        .onAppear { translate = TranslationPreferences.isEnabled(for: key) }
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
                NavigationLink {
                    SaveManagerView(title: game.title, folder: renpy.saveFolder(of: game))
                } label: {
                    Label("Manage saves and cheats", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("manageSaves")
            case .web(let game, _) where game.engine == .rgss:
                Text("Saves: On My iPhone › EverPlay › Saves › \(game.title). EverPlay copies them into the game when it starts and back after you play.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    SaveManagerView(title: game.title, folder: SaveFolders.libretro(game))
                } label: {
                    Label("Manage saves", systemImage: "externaldrive")
                }
            case .web(let game, _) where !game.engine.isWeb:
                Text("Saves: On My iPhone › EverPlay › Saves › \(game.title)").font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    SaveManagerView(title: game.title, folder: SaveFolders.libretro(game))
                } label: {
                    Label("Manage saves", systemImage: "externaldrive")
                }
            case .web:
                Text("Stored in EverPlay's private storage with the game's own browser saves. Cheats and value editing: game menu › Cheats while playing.")
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
