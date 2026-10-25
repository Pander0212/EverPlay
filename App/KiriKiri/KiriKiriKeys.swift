import SwiftUI
import EverPlayCore

/// The key each encrypted KiriKiri game plays with: a title from GARbro's database, chosen once
/// per game and written as the engine's scheme file.
enum KiriKiriKeys {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/KiriKiri", isDirectory: true)
    }
    private static var databaseFile: URL { folder.appendingPathComponent("Formats.dat") }
    private static func defaultsKey(_ game: GameRecord) -> String { "kirikiriKey.\(game.id.uuidString)" }

    static func schemeFile(for game: GameRecord) -> URL {
        folder.appendingPathComponent("Schemes/\(game.id.uuidString).shcx")
    }

    /// The chosen title; "" when the player chose to start without a key.
    static func chosenTitle(for game: GameRecord) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(game))
    }

    static func choose(_ title: String, scheme: Data?, for game: GameRecord) throws {
        let file = schemeFile(for: game)
        try? FileManager.default.removeItem(at: file)
        if let scheme {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try scheme.write(to: file, options: .atomic)
        }
        UserDefaults.standard.set(title, forKey: defaultsKey(game))
    }

    static func forget(_ game: GameRecord) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(game))
        try? FileManager.default.removeItem(at: schemeFile(for: game))
    }

    /// GARbro's database: the copy from the last week, else downloaded again (else any copy).
    static func catalog() async throws -> KiriKiriSchemes.Catalog {
        let fileManager = FileManager.default
        let age = ((try? fileManager.attributesOfItem(atPath: databaseFile.path))?[.modificationDate] as? Date)
            .map { Date().timeIntervalSince($0) }
        if (age ?? .infinity) > 7 * 24 * 3600 {
            do {
                let (data, response) = try await URLSession.shared.data(from: KiriKiriSchemes.database)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                _ = try KiriKiriSchemes.catalog(from: data)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: databaseFile, options: .atomic)
            } catch {
                guard age != nil else { throw error }
                EverPlayLog.write("KiriKiri: GARbro's list could not be updated: \(error.localizedDescription)")
            }
        }
        let data = try Data(contentsOf: databaseFile)
        return try await Task.detached { try KiriKiriSchemes.catalog(from: data) }.value
    }
}

/// Starts a KiriKiri game: first asks for the key when its archives are encrypted and none
/// has been chosen yet.
struct KiriKiriLaunchView: View {
    let game: GameRecord
    let store: LibraryStore
    private enum Stage { case checking, choosingKey, playing }
    @State private var stage = Stage.checking

    var body: some View {
        switch stage {
        case .playing:
            KiriKiriPlayerView(game: game, store: store, scheme: scheme)
        case .choosingKey:
            KiriKiriKeyPicker(game: game, gameRoot: gameRoot) { stage = .playing }
        case .checking:
            Color.black.task {
                if KiriKiriKeys.chosenTitle(for: game) != nil { stage = .playing; return }
                let root = gameRoot
                let state = await Task.detached { KiriKiriGame.archiveState(gameRoot: root) }.value
                EverPlayLog.write("KiriKiri: \(game.title) archives: \(state)")
                stage = state == .encrypted ? .choosingKey : .playing
            }
        }
    }

    private var gameRoot: URL {
        store.directory(for: game).appendingPathComponent(game.entryPoint).deletingLastPathComponent()
    }

    private var scheme: URL? {
        let file = KiriKiriKeys.schemeFile(for: game)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}

/// GARbro's titles, the ones resembling the game first.
struct KiriKiriKeyPicker: View {
    let game: GameRecord
    let gameRoot: URL
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: KiriKiriSchemes.Catalog?
    @State private var failure: String?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    list(catalog)
                } else if let failure {
                    ContentUnavailableView {
                        Label("No list of keys", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                        Button("Start without key") { choose(nil, catalog: nil) }
                    }
                } else {
                    ProgressView("Loading GARbro's list of games…")
                }
            }
            .navigationTitle("Encrypted game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func list(_ catalog: KiriKiriSchemes.Catalog) -> some View {
        let names = [game.title, gameRoot.lastPathComponent, KiriKiriGame.executableName(in: gameRoot)]
        let suggestions = catalog.suggestions(for: names)
        let matches = search.isEmpty ? catalog.titles : catalog.titles.filter { $0.localizedCaseInsensitiveContains(search) }
        return List {
            Section {
                Text("\(game.title) keeps its files encrypted. Pick the game below and EverPlay opens it with the key from GARbro's list. The files stay as they are.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if search.isEmpty, !suggestions.isEmpty {
                Section("Suggested") {
                    ForEach(suggestions, id: \.self) { title in row(title, catalog) }
                }
            }
            Section(search.isEmpty ? "All games" : "Results") {
                ForEach(matches, id: \.self) { title in row(title, catalog) }
            }
            Section {
                Button("Start without key") { choose(nil, catalog: catalog) }
            } footer: {
                Text("If the game is not in the list, EverPlay cannot open it yet.")
            }
        }
        .searchable(text: $search, prompt: "Game title")
    }

    private func row(_ title: String, _ catalog: KiriKiriSchemes.Catalog) -> some View {
        Button(title) { choose(title, catalog: catalog) }
            .foregroundStyle(.primary)
    }

    private func load() async {
        failure = nil
        do {
            catalog = try await KiriKiriKeys.catalog()
        } catch {
            failure = "EverPlay needs the internet once to load GARbro's list of games. \(error.localizedDescription)"
        }
    }

    private func choose(_ title: String?, catalog: KiriKiriSchemes.Catalog?) {
        do {
            try KiriKiriKeys.choose(title ?? "", scheme: title.flatMap { catalog?.schemeFile(title: $0) }, for: game)
            EverPlayLog.write("KiriKiri: \(game.title) plays with key \(title ?? "none")")
            start()
        } catch {
            failure = error.localizedDescription
        }
    }
}
