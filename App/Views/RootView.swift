import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var showImporter = false
    @State private var archiveCandidate: GameRecord?
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR NEXT ADVENTURE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.mint)
                            Text("A little escape.\nAlways with you.").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("Your games, in one quiet place.").foregroundStyle(.secondary)
                        }.padding(.top, 12)
                        if library.games.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 48)).foregroundStyle(.mint)
                                Text("Make room for play").font(.title2.bold())
                                Text("Import an HTML5 game ZIP, or explore the original demo.")
                                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                Button("Play the demo") { Task { await library.importDemo() } }
                                    .buttonStyle(.borderedProminent).disabled(library.importing)
                                    .accessibilityIdentifier("importDemo")
                                Button("Import a game") { showImporter = true }.disabled(library.importing)
                            }.frame(maxWidth: .infinity).padding(28).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
                        } else {
                            HStack {
                                Text("Your library").font(.title2.bold())
                                Spacer(); Text("\(library.games.count) games").font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 20) {
                                ForEach(library.games) { game in
                                    Button { library.selectedGame = game } label: { GameCard(game: game) }
                                        .buttonStyle(.plain).accessibilityIdentifier("game-\(game.title)")
                                        .contextMenu {
                                            Button("Archive game", systemImage: "archivebox") { archiveCandidate = game }
                                        }
                                }
                            }
                        }
                        if library.importing { ProgressView("Checking and importing game…").frame(maxWidth: .infinity) }
                    }.padding(24)
                }
                .background(Color(red: 0.035, green: 0.05, blue: 0.08))
                .navigationTitle("EverPlay")
                .toolbar {
                    Button { showImporter = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Import ZIP").disabled(library.importing || library.store == nil)
                }
            }.tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            NavigationStack {
                List {
                    Section {
                        Label("Bring your own adventures", systemImage: "tray.and.arrow.down.fill").font(.headline)
                        Text("Choose a ZIP containing one HTML5 game and its index.html. Nested folders are supported.")
                            .foregroundStyle(.secondary)
                        Button("Choose ZIP from Files", systemImage: "folder") { showImporter = true }
                        Button("Import Lantern Garden demo", systemImage: "leaf") { Task { await library.importDemo() } }
                    }.disabled(library.importing || library.store == nil)
                    if library.importing { ProgressView("Validating and extracting…") }
                    if let message = library.importMessage { Section("Last import") { Text(message).foregroundStyle(.mint) } }
                    Section("Compatibility") {
                        Text("HTML5 games run offline in WebKit. MV/MZ web exports are experimental.")
                        Text("Desktop plugins, other RPG Maker engines, Ren’Py and Godot packages are not supported in this build.")
                            .foregroundStyle(.secondary)
                    }
                }.navigationTitle("Import")
            }.tabItem { Label("Import", systemImage: "plus.app") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .task { await library.refresh() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await library.importZIP(url) } }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .alert("EverPlay", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .confirmationDialog("Archive this game? Its files and browser saves will be retained; restore UI is planned.",
                            isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })) {
            Button("Archive game") { if let game = archiveCandidate { Task { await library.archive(game) } }; archiveCandidate = nil }
        }
        .fullScreenCover(item: $library.selectedGame, onDismiss: { Task { await library.refresh() } }) { game in
            if let store = library.store { GamePlayerView(game: game, store: store) }
        }
    }
}

private struct GameCard: View {
    let game: GameRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(colors: [.teal.opacity(0.8), .indigo.opacity(0.6), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: game.engine == .html5 ? "leaf.fill" : "sparkles")
                    .font(.system(size: 52, weight: .light)).foregroundStyle(.white.opacity(0.85))
                VStack { Spacer(); HStack { Text(game.engine.title).font(.caption2.bold()).padding(7).background(.ultraThinMaterial, in: Capsule()); Spacer() } }.padding(12)
            }.aspectRatio(0.85, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 20))
            Text(game.title).font(.headline).lineLimit(2)
            Text(game.engine.compatibility).font(.caption).foregroundStyle(.secondary)
            if game.playSeconds > 60 { Text("\(Int(game.playSeconds / 60)) min played").font(.caption2).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @AppStorage("preventSleep") private var preventSleep = true
    var body: some View {
        Form {
            Section("While playing") {
                Toggle("Keep screen awake", isOn: $preventSleep)
                Text("Virtual controls, their layout and transparency are saved separately for each game in the player menu.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Text("Games stay on this device in EverPlay’s private storage. Each game has its own persistent browser storage.")
                Text("Use the game’s save function before exiting. Uninstalling EverPlay removes its local data.")
                    .foregroundStyle(.secondary)
            }
            Section("Development status") {
                Label("HTML5 foundation", systemImage: "globe")
                Text("Translation, mod installation, cheats and Bridge pairing are planned. No external AI service is contacted.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("EverPlay · 0.1.0")
                Text("Original demo and app source: MIT license.")
                NavigationLink("Third-party licenses") {
                    ScrollView {
                        Text(thirdPartyNotices).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding()
                    }.navigationTitle("Licenses")
                }
            }
        }.navigationTitle("Settings")
    }
    private var thirdPartyNotices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License notices are missing from this build." }
        return text
    }
}
