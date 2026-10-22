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
                LibraryView(showImporter: $showImporter, archiveCandidate: $archiveCandidate)
            }.tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            NavigationStack {
                ImportView(showImporter: $showImporter)
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

private struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @Binding var showImporter: Bool
    @Binding var archiveCandidate: GameRecord?
    @State private var search = ""
    @State private var filter: GameEngine?
    @Namespace private var chips

    private var visibleGames: [GameRecord] {
        library.games.filter { game in
            (filter == nil || game.engine == filter)
                && (search.isEmpty || game.title.localizedCaseInsensitiveContains(search))
        }
    }
    private var recentGames: [GameRecord] {
        library.games.filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(6).map { $0 }
    }
    private var engines: [GameEngine] { GameEngine.allCases.filter { engine in library.games.contains { $0.engine == engine } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if library.games.isEmpty {
                    EmptyLibrary(showImporter: $showImporter)
                } else {
                    if search.isEmpty && filter == nil && !recentGames.isEmpty { continueSection }
                    if engines.count > 1 { filterChips }
                    gameGrid
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.background
                RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 420)
                    .frame(height: 420)
            }.ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { if library.importing { ImportToast().padding(.bottom, 16) } }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: library.importing)
        .navigationTitle("EverPlay")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search your games")
        .toolbar {
            Button { showImporter = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Import ZIP").disabled(library.importing || library.store == nil)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Library").font(.system(size: 34, weight: .bold))
            Text(library.games.isEmpty ? "Your games, in one quiet place."
                 : "\(library.games.count) \(library.games.count == 1 ? "game" : "games") ready to play")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Continue playing")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(recentGames) { game in
                        Button { library.selectedGame = game } label: { ContinueCard(game: game) }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("continue-\(game.title)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", engine: nil)
                ForEach(engines, id: \.self) { chip($0.title, engine: $0) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, engine: GameEngine?) -> some View {
        let selected = filter == engine
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { filter = engine }
        } label: {
            HStack(spacing: 6) {
                if let engine { Circle().fill(Theme.engineColor(engine)).frame(width: 7, height: 7) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : .secondary)
            .background {
                if selected {
                    Capsule().fill(Theme.accentSoft).overlay(Capsule().stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                        .matchedGeometryEffect(id: "chip", in: chips)
                } else {
                    Capsule().stroke(Theme.stroke, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var gameGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(filter?.title ?? "All games")
            if visibleGames.isEmpty {
                Text("No games match “\(search)”.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(Array(visibleGames.enumerated()), id: \.element.id) { index, game in
                    Button { library.selectedGame = game } label: { GameCard(game: game, index: index) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("game-\(game.title)")
                        .contextMenu {
                            Button("Archive game", systemImage: "archivebox") { archiveCandidate = game }
                        }
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title3.weight(.semibold))
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var library: LibraryModel
    @Binding var showImporter: Bool
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                AmbientOrb(size: 200)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(26)
                    .surface(Circle())
            }
            .frame(height: 210)
            VStack(spacing: 8) {
                Text("Make room for play").font(.title2.weight(.bold))
                Text("Import a game ZIP from Files, or start with the original demo.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button("Play the demo") { Task { await library.importDemo() } }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(library.importing)
                    .accessibilityIdentifier("importDemo")
                Button("Import a game") { showImporter = true }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(library.importing || library.store == nil)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct GameCover: View {
    let game: GameRecord
    var cornerRadius: CGFloat = 22
    var body: some View {
        ZStack {
            Theme.cover(for: game.title)
            LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
            Text(Theme.initials(game.title))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct GameCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let game: GameRecord
    let index: Int
    @State private var appeared = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GameCover(game: game)
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(alignment: .topLeading) { EngineBadge(engine: game.engine).padding(10) }
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(reduceMotion ? 0 : Double(min(index, 8)) * 0.05)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var subtitle: String {
        game.playSeconds >= 60 ? "\(Int(game.playSeconds / 60)) min played" : (game.lastPlayedAt == nil ? "New" : "Just started")
    }
}

private struct ContinueCard: View {
    let game: GameRecord
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameCover(game: game, cornerRadius: 24)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title).font(.headline).lineLimit(1)
                    if let last = game.lastPlayedAt {
                        Text(last, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            }
            .padding(16)
        }
        .frame(width: 280, height: 168)
        .accessibilityElement(children: .combine)
    }
}

private struct ImportToast: View {
    var body: some View {
        HStack(spacing: 14) {
            RingLoader()
            VStack(alignment: .leading, spacing: 2) {
                Text("Importing").font(.subheadline.weight(.semibold))
                Text("Checking files and preparing the game…").font(.caption).foregroundStyle(.secondary).shimmer()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surface(cornerRadius: 22)
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ImportView: View {
    @EnvironmentObject private var library: LibraryModel
    @Binding var showImporter: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add a game").font(.system(size: 34, weight: .bold))
                    Text("Games are checked and stored privately on this device.").foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                ImportOption(icon: "folder.fill", title: "Choose a ZIP from Files",
                             detail: "One game with its index.html. Nested folders are fine.") { showImporter = true }
                ImportOption(icon: "leaf.fill", title: "Lantern Garden demo",
                             detail: "An original sample game to try the controls.") { Task { await library.importDemo() } }
                if library.importing { ImportToast().padding(.horizontal, -20) }
                if let message = library.importMessage {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compatibility").font(.headline)
                    Text("HTML5 games run offline in WebKit. RPG Maker MV/MZ web exports are experimental. Native Ren’Py support is in testing.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(cornerRadius: 20)
            }
            .padding(20)
            .disabled(library.importing || library.store == nil)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ImportOption: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .surface(cornerRadius: 20)
        }
        .buttonStyle(PressableStyle())
    }
}

struct SettingsView: View {
    @AppStorage("preventSleep") private var preventSleep = true
    @AppStorage("appearanceStyle") private var appearance = AppearanceStyle.standard.rawValue
    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $appearance) {
                    ForEach(AppearanceStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text(AppearanceStyle.liquidGlassAvailable
                     ? "Liquid Glass uses the system glass material of iOS 26."
                     : "Liquid Glass needs iOS 26; on this device a frosted material is used instead.")
            }
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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }
    private var thirdPartyNotices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License notices are missing from this build." }
        return text
    }
}
