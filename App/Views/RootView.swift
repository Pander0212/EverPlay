import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var renpy: RenPyLibrary
    @StateObject private var downloads = URLImporter()
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showLinkPrompt = false
    @State private var link = ""
    @State private var archiveCandidate: GameRecord?
    @State private var deleteCandidate: RenPyTitle?

    var body: some View {
        NavigationStack {
            LibraryView(archiveCandidate: $archiveCandidate, deleteCandidate: $deleteCandidate,
                        pickArchive: pickArchive, pickFolder: pickFolder)
                .safeAreaInset(edge: .bottom) { bottomBar }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        addMenu
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings").accessibilityIdentifier("openSettings")
                    }
                }
        }
        .task {
            await library.refresh()
            renpy.refresh()
            // CI and development: start a Ren'Py game from the library directly.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-EverPlayAutoplayRenPy"), index + 1 < arguments.count,
               let game = renpy.games.first(where: { $0.folder == arguments[index + 1] }) {
                renpy.play(game)
            }
        }
        .alert("EverPlay", isPresented: Binding(get: { notice != nil }, set: { if !$0 { clearNotices() } })) {
            Button("OK") { clearNotices() }
        } message: { Text(notice ?? "") }
        .alert("Direct link", isPresented: $showLinkPrompt) {
            TextField("https://", text: $link)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("Download") {
                let text = link
                Task { await downloads.download(text, library: library, renpy: renpy) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a direct download link to a game ZIP. Pages of file hosts (Mega, Google Drive) need their direct-download link.")
        }
        .confirmationDialog("Archive this game? Its files and browser saves will be retained; restore UI is planned.",
                            isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })) {
            Button("Archive game") { if let game = archiveCandidate { Task { await library.archive(game) } }; archiveCandidate = nil }
        }
        .confirmationDialog("Delete this game? Its saves stay in EverPlay › Saves.",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete game", role: .destructive) { if let game = deleteCandidate { renpy.delete(game) }; deleteCandidate = nil }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }.accessibilityIdentifier("doneSettings")
                        }
                    }
            }
        }
        .sheet(isPresented: $showHelp) { NavigationStack { ImportHelpView() } }
        .fullScreenCover(item: $library.selectedGame, onDismiss: { Task { await library.refresh() } }) { game in
            if let store = library.store {
                if game.engine.isWeb { GamePlayerView(game: game, store: store) }
                else if game.engine == .kirikiri { KiriKiriLaunchView(game: game, store: store).ignoresSafeArea() }
                else { LibretroPlayerView(game: game, store: store) }
            }
        }
    }

    private var notice: String? { library.error ?? renpy.message ?? downloads.message }
    private func clearNotices() { library.error = nil; renpy.message = nil; downloads.message = nil }

    private var busy: String? {
        if let name = downloads.downloading { return "Downloading from \(name)…" }
        if let name = renpy.installing { return "Adding \(name)…" }
        if library.importing { return "Checking files and preparing the game…" }
        return nil
    }

    /// Only the import progress; adding games is in the top bar (the search field sits at the bottom on iOS 26).
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let busy { ImportToast(detail: busy) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: busy)
    }

    private var addMenu: some View {
        Menu {
            Button("ZIP from Files", systemImage: "doc.zipper") { pickArchive() }
            Button("Game folder", systemImage: "folder") { pickFolder() }
            Button("Direct link", systemImage: "link") { link = ""; showLinkPrompt = true }
            Divider()
            Button("Demo game", systemImage: "leaf") { Task { await library.importDemo() } }
            Button("Import help", systemImage: "questionmark.circle") { showHelp = true }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add game").accessibilityIdentifier("addGame")
        .disabled(busy != nil || library.store == nil)
    }

    private func pickArchive() {
        // A copy: the archive is read once and needs no lasting access to its source.
        FilePicker.present(types: [.zip, .archive, .data], asCopy: true) { url in
            Task { await GameImport.run(url, library: library, renpy: renpy) }
        }
    }

    private func pickFolder() {
        FilePicker.present(types: [.folder], asCopy: false) { url in
            Task { await GameImport.run(url, library: library, renpy: renpy) }
        }
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var renpy: RenPyLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Binding var archiveCandidate: GameRecord?
    @Binding var deleteCandidate: RenPyTitle?
    let pickArchive: () -> Void
    let pickFolder: () -> Void
    @State private var search = ""
    @State private var webCovers: [UUID: URL] = [:]
    @State private var detail: LibraryItem?
    @AppStorage("library.showHidden") private var showHidden = false
    @AppStorage("library.filter") private var filter = LibraryFilter.all
    @AppStorage("library.sort") private var sort = LibrarySort.recent
    @AppStorage("library.layout") private var layout = LibraryLayout.grid
    @AppStorage("library.coverVersion") private var coverVersion = 0
    /// Changes when a game is hidden, shown or marked as a favorite, so the list updates.
    @State private var hiddenVersion = 0
    /// Why a game could not start (RPG Maker XP/VX/VX Ace without mkxp-z in this build).
    @State private var playMessage: String?
    /// Set by the details page; acted on once its sheet is gone.
    @State private var afterDetail: (() -> Void)?

    private var items: [LibraryItem] {
        let web = library.games.map { LibraryItem.web($0, cover: webCovers[$0.id]) }
        let renpyItems = renpy.games.map { LibraryItem.renpy($0) }
        _ = hiddenVersion
        _ = coverVersion
        return sort.ordered((web + renpyItems).filter { showHidden || !HiddenGames.contains($0.id) })
    }
    private var visibleItems: [LibraryItem] {
        items.filter { filter.includes($0) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    /// Played games after the one on top, newest first.
    private var recent: [LibraryItem] {
        guard search.isEmpty, filter == .all, items.count > 3 else { return [] }
        return items.filter { $0.lastPlayed != nil && $0.id != hero?.id }
            .sorted { $0.lastPlayed! > $1.lastPlayed! }
            .prefix(10).map { $0 }
    }
    /// The most recently played game, shown on top when there is more than one game.
    private var hero: LibraryItem? {
        guard search.isEmpty, filter == .all, items.count > 1,
              let last = items.filter({ $0.lastPlayed != nil }).max(by: { $0.lastPlayed! < $1.lastPlayed! }) else { return nil }
        return last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if items.isEmpty {
                    EmptyLibrary(pickArchive: pickArchive)
                } else {
                    if !library.inbox.isEmpty { inboxSection }
                    if let hero {
                        ContinueCard(item: hero, open: { detail = hero }, play: { play(hero) })
                            .contextMenu { menu(for: hero) }
                    }
                    if recent.count > 1 {
                        RecentShelf(items: recent, play: play, menu: { AnyView(menu(for: $0)) })
                    }
                    if items.count > 1 { filterBar }
                    switch layout {
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 16)], spacing: 22) {
                            ForEach(visibleItems) { item in
                                PosterCard(item: item, favorite: FavoriteGames.contains(item.id),
                                           open: { detail = item }, play: { play(item) })
                                    .contextMenu { menu(for: item) }
                            }
                        }
                    case .list:
                        ForEach(visibleItems) { item in
                            row(item, identifier: "game-\(item.title)")
                        }
                    }
                    if visibleItems.isEmpty {
                        Text(search.isEmpty ? "No \(filter.title) games yet." : "No games match “\(search)”.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            // Room for the bottom bar and the search field below it, so the last game can scroll into view.
            .padding(.horizontal, 18).padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack(alignment: .top) {
                Theme.background
                RadialGradient(colors: [Theme.accent.opacity(0.20), .clear], center: .top, startRadius: 0, endRadius: 460)
                    .frame(height: 460)
                RadialGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.78).opacity(0.10), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
        .navigationTitle("EverPlay")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search your games")
        .onAppear { library.refreshInbox(); renpy.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshInbox(); renpy.refresh() }
        }
        .task(id: library.games.map(\.id)) { await loadWebCovers() }
        .alert("Cannot start this game", isPresented: Binding(get: { playMessage != nil }, set: { if !$0 { playMessage = nil } })) {
            Button("OK", role: .cancel) { playMessage = nil }
        } message: {
            Text(playMessage ?? "")
        }
        .sheet(item: $detail, onDismiss: {
            let action = afterDetail
            afterDetail = nil
            action?()
        }) { item in
            NavigationStack {
                GameDetailView(item: item, play: { afterDetail = { play(item) }; detail = nil },
                               remove: { afterDetail = { remove(item) }; detail = nil })
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Library").font(.system(size: 36, weight: .bold))
            Text(items.isEmpty ? "Your games, in one quiet place."
                 : "\(items.count) \(items.count == 1 ? "game" : "games") ready to play")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    /// Engine filter chips and the sort order.
    private var filterBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases) { option in
                        Button { withAnimation(.snappy) { filter = option } } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(filter == option ? .white : .primary)
                                .background(filter == option ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08)),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filter-\(option.rawValue)")
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button {
                withAnimation(.snappy) { layout = layout == .grid ? .list : .grid }
            } label: {
                Image(systemName: layout == .grid ? LibraryLayout.list.icon : LibraryLayout.grid.icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layout == .grid ? "Show as list" : "Show as covers")
            .accessibilityIdentifier("libraryLayout")
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Sort games")
            .accessibilityIdentifier("sortGames")
        }
    }

    private func row(_ item: LibraryItem, identifier: String) -> some View {
        GameRow(item: item, identifier: identifier, favorite: FavoriteGames.contains(item.id),
                open: { detail = item }, play: { play(item) })
            .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: LibraryItem) -> some View {
        Button("Play", systemImage: "play.fill") { play(item) }
        Button("Details", systemImage: "info.circle") { detail = item }
        if FavoriteGames.contains(item.id) {
            Button("Remove from favorites", systemImage: "star.slash") { FavoriteGames.set(item.id, favorite: false); hiddenVersion += 1 }
        } else {
            Button("Add to favorites", systemImage: "star") { FavoriteGames.set(item.id, favorite: true); hiddenVersion += 1 }
        }
        if HiddenGames.contains(item.id) {
            Button("Show in library", systemImage: "eye") { HiddenGames.set(item.id, hidden: false); hiddenVersion += 1 }
        } else {
            Button("Hide from library", systemImage: "eye.slash") { HiddenGames.set(item.id, hidden: true); hiddenVersion += 1 }
        }
        switch item {
        case .web:
            Button("Archive game", systemImage: "archivebox") { remove(item) }
        case .renpy:
            Button("Delete game", systemImage: "trash", role: .destructive) { remove(item) }
        }
    }

    private func remove(_ item: LibraryItem) {
        switch item {
        case .web(let game, _): archiveCandidate = game
        case .renpy(let game): deleteCandidate = game
        }
    }

    private func play(_ item: LibraryItem) {
        switch item {
        case .web(let game, _) where game.engine == .rgss:
            guard let store = library.store else { return }
            playMessage = MKXPLauncher.play(game, directory: store.directory(for: game))
        case .web(let game, _) where game.engine == .wolfRPG:
            guard let store = library.store else { return }
            playMessage = WolfLauncher.play(game, directory: store.directory(for: game))
        case .web(let game, _): library.selectedGame = game
        case .renpy(let game): renpy.play(game)
        }
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("In your EverPlay folder", systemImage: "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(library.inbox, id: \.self) { url in
                Button {
                    Task { await GameImport.run(url, library: library, renpy: renpy) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: url.pathExtension.lowercased() == "zip" ? "doc.zipper" : "folder.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(url.deletingPathExtension().lastPathComponent).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        Text("Import").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(12)
                    .surface(cornerRadius: 20)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func loadWebCovers() async {
        guard let store = library.store else { return }
        let games = library.games
        webCovers = await Task.detached(priority: .utility) { () -> [UUID: URL] in
            var covers: [UUID: URL] = [:]
            for game in games {
                covers[game.id] = WebCover.locate(in: store.directory(for: game), entryPoint: game.entryPoint)
            }
            return covers
        }.value
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var library: LibraryModel
    let pickArchive: () -> Void
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
                Text("Add Ren'Py, RPG Maker (2000/2003, XP, VX, VX Ace, MV, MZ), KiriKiri, WOLF RPG Editor, TyranoBuilder or HTML games with the + button: a ZIP, a game folder or a direct link. You can also copy games into On My iPhone › EverPlay.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button("Play the demo") { Task { await library.importDemo() } }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(library.importing)
                    .accessibilityIdentifier("importDemo")
                Button("Import a game") { pickArchive() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(library.importing || library.store == nil)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct ImportToast: View {
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            RingLoader()
            VStack(alignment: .leading, spacing: 2) {
                Text("Importing").font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).shimmer()
                TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                    if let fraction = ImportProgress.shared.fraction {
                        HStack(spacing: 8) {
                            ProgressView(value: fraction).tint(Theme.accent)
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surface(cornerRadius: 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Ways to add a game") {
                Label("ZIP from Files: a game archive, e.g. from Downloads.", systemImage: "doc.zipper")
                Label("Game folder: an unpacked game (the folder that contains game/ or index.html).", systemImage: "folder")
                Label("Direct link: a download link that points straight to a ZIP file.", systemImage: "link")
                Label("Files app: copy games into On My iPhone › EverPlay; they appear at the top of the library to import.", systemImage: "tray.and.arrow.down")
                Label("Share: long-press a ZIP in Files or Safari › Share › EverPlay.", systemImage: "square.and.arrow.up")
            }
            Section("Supported now") {
                Text("Ren'Py 6–8 desktop games (built-in Ren'Py 8.5, 8.4, 8.3, 8.2, 8.1 and 7.8; games that ship their own engine of an included version use it).")
                Text("RPG Maker MV/MZ, TyranoScript, NW.js and Electron builds (package.nw, app.asar), Twine and other HTML5 games.")
                Text("RPG Maker 2000/2003 games with EasyRPG Player (on iPhone and iPad).")
                Text("RPG Maker XP, VX and VX Ace games with mkxp-z; the free RTP is downloaded on the game's page.")
                Text("KiriKiri visual novels; encrypted ones with a key from GARbro's list.")
                Text("WOLF RPG Editor 2 and 3 games with EverPlay's own engine (experimental; archives of WOLF RPG Editor Pro not yet).")
            }
            Section("Saves") {
                Text("Ren'Py, RPG Maker 2000/2003, XP/VX/VX Ace, KiriKiri and WOLF RPG saves: On My iPhone › EverPlay › Saves › game. Web games keep their saves in EverPlay's private storage.")
            }
        }
        .navigationTitle("Import help")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// The diagnostics journal, shareable for bug reports.
struct DiagnosticsLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = EverPlayLog.read()
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Nothing recorded yet." : text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear", systemImage: "trash") { EverPlayLog.clear(); text = "" }
                ShareLink(item: EverPlayLog.file)
            }
        }
    }
}

/// UIKit's document picker, presented the UIKit way from the topmost view controller. Wrapped in a
/// SwiftUI sheet (and SwiftUI's own fileImporter before that) it showed the browser on a real
/// iPhone but nothing could be chosen.
@MainActor
enum FilePicker {
    private static var delegate: Delegate?

    static func present(types: [UTType], asCopy: Bool, onPick: @escaping (URL) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else {
            EverPlayLog.write("File picker: no window to present from")
            return
        }
        while let presented = top.presentedViewController { top = presented }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        picker.allowsMultipleSelection = false
        let handler = Delegate(onPick: onPick)
        delegate = handler
        picker.delegate = handler
        EverPlayLog.write("File picker opened for \(types.map(\.identifier).joined(separator: ", ")) (copy: \(asCopy))")
        top.present(picker, animated: true)
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            EverPlayLog.write("File picker returned \(urls.count) item(s): \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            if let url = urls.first { onPick(url) }
            Task { @MainActor in FilePicker.delegate = nil }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            EverPlayLog.write("File picker cancelled")
            Task { @MainActor in FilePicker.delegate = nil }
        }
    }
}

struct SettingsView: View {
    @AppStorage("preventSleep") private var preventSleep = true
    @AppStorage("appearanceStyle") private var appearance = AppearanceStyle.standard.rawValue
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(LinearGradient(colors: [Theme.accent, Color(red: 0.36, green: 0.62, blue: 0.78)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EverPlay").font(.title3.weight(.bold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
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
            RenPySettingsSection()
            SavesSettingsSection()
            TranslationSettingsSection()
            PrivacySettingsSection()
            Section("While playing") {
                Toggle("Keep screen awake", isOn: $preventSleep)
                Text("Virtual controls, their layout and transparency are saved separately for each game in the player menu.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Text("Ren'Py games and their saves are in On My iPhone › EverPlay (Ren'Py, Saves). Web games stay in EverPlay's private storage with their own browser storage.")
                Text("Uninstalling EverPlay removes its local data, including saves.")
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                NavigationLink("Diagnostics log") { DiagnosticsLogView() }
                Text("Imports, file picker results and game starts and ends are recorded here and in On My iPhone › EverPlay › EverPlay-log.txt. Share it when reporting a problem.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                Text("EverPlay · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
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

/// Settings › Saves & cheats: every game's saves in one place.
struct SavesSettingsSection: View {
    @EnvironmentObject private var renpy: RenPyLibrary
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        Section {
            ForEach(renpy.games) { game in
                NavigationLink(game.title) { SaveManagerView(title: game.title, folder: renpy.saveFolder(of: game)) }
            }
            ForEach(library.games.filter { !$0.engine.isWeb }) { game in
                NavigationLink(game.title) { SaveManagerView(title: game.title, folder: SaveFolders.libretro(game)) }
            }
            if renpy.games.isEmpty && !library.games.contains(where: { !$0.engine.isWeb }) {
                Text("No games with save files yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Saves & cheats")
        } footer: {
            Text("Back up, restore, share or delete save files. Values (money, stats, flags) are changed while playing: Ren'Py games with the ☰ button › Variables, RPG Maker MV/MZ games with the game menu › Cheats. Ren'Py saves are never opened outside the game, because reading them would run code from the file.")
        }
    }
}
