import SwiftUI
import UniformTypeIdentifiers
import EverPlayCore

struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var renpy: RenPyLibrary
    @StateObject private var downloads = URLImporter()
    @State private var showSettings = false
    @State private var showLog = false
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
        .sheet(isPresented: $showLog) { NavigationStack { DiagnosticsLogView() } }
        .sheet(isPresented: $showHelp) { NavigationStack { ImportHelpView() } }
        .fullScreenCover(item: $library.selectedGame, onDismiss: { Task { await library.refresh() } }) { game in
            if let store = library.store {
                if game.engine.isWeb { GamePlayerView(game: game, store: store) }
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

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let busy { ImportToast(detail: busy) }
            HStack(alignment: .center) {
                HStack(spacing: 26) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("openSettings")
                    Button { showLog = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                        .accessibilityLabel("Diagnostics log")
                }
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 26).padding(.vertical, 18)
                .surface(Capsule())
                Spacer()
                Menu {
                    Button("ZIP from Files", systemImage: "doc.zipper") { pickArchive() }
                    Button("Game folder", systemImage: "folder") { pickFolder() }
                    Button("Direct link", systemImage: "link") { link = ""; showLinkPrompt = true }
                    Divider()
                    Button("Demo game", systemImage: "leaf") { Task { await library.importDemo() } }
                    Button("Import help", systemImage: "questionmark.circle") { showHelp = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
                }
                .accessibilityLabel("Add game").accessibilityIdentifier("addGame")
                .disabled(busy != nil || library.store == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: busy)
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
    /// Changes when a game is hidden or shown, so the list updates.
    @State private var hiddenVersion = 0
    /// Set by the details page; acted on once its sheet is gone.
    @State private var afterDetail: (() -> Void)?

    private var items: [LibraryItem] {
        let web = library.games.map { LibraryItem.web($0, cover: webCovers[$0.id]) }
        let renpyItems = renpy.games.map { LibraryItem.renpy($0) }
        _ = hiddenVersion
        return (web + renpyItems).filter { showHidden || !HiddenGames.contains($0.id) }.sorted { lhs, rhs in
            switch (lhs.lastPlayed, rhs.lastPlayed) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
    private var visibleItems: [LibraryItem] {
        search.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
    /// The most recently played game, shown on top when there is more than one game.
    private var hero: LibraryItem? {
        guard search.isEmpty, items.count > 1, let first = items.first, first.lastPlayed != nil else { return nil }
        return first
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
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Continue playing", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            row(hero, identifier: "continue-\(hero.title)")
                        }
                    }
                    ForEach(visibleItems.filter { $0.id != hero?.id }) { item in
                        row(item, identifier: "game-\(item.title)")
                    }
                    if visibleItems.isEmpty {
                        Text("No games match “\(search)”.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
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

    private func row(_ item: LibraryItem, identifier: String) -> some View {
        GameRow(item: item, identifier: identifier, open: { detail = item }, play: { play(item) })
            .contextMenu {
                Button("Play", systemImage: "play.fill") { play(item) }
                Button("Details", systemImage: "info.circle") { detail = item }
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
    }

    private func remove(_ item: LibraryItem) {
        switch item {
        case .web(let game, _): archiveCandidate = game
        case .renpy(let game): deleteCandidate = game
        }
    }

    private func play(_ item: LibraryItem) {
        switch item {
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
                Text("Add Ren'Py, RPG Maker (2000/2003, MV, MZ), TyranoBuilder or HTML games with the + button: a ZIP, a game folder or a direct link. You can also copy games into On My iPhone › EverPlay.")
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
            }
            Section("Saves") {
                Text("Ren'Py saves: On My iPhone › EverPlay › Saves › game folder. Web games keep their saves in EverPlay's private storage.")
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
