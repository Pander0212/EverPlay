import SwiftUI
import EverPlayCore

struct GamePlayerView: View {
    let game: GameRecord
    let store: LibraryStore
    @StateObject private var session: GameSession
    @State private var controls: ControlSettings
    @State private var menuVisible = false
    @State private var menuDetent: PresentationDetent = .large
    @State private var editingLayout = false
    @State private var selectedControl: UUID?
    @State private var showOriginal = false
    @State private var storageError: String?
    @State private var closing = false
    @AppStorage("preventSleep") private var preventSleep = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(game: GameRecord, store: LibraryStore) {
        self.game = game; self.store = store
        _session = StateObject(wrappedValue: GameSession(game: game, root: store.directory(for: game)))
        var controls = game.controls
        // A game whose layout was never edited starts with the engine's saved default, if any.
        if controls.buttons == nil, let profile = ControlProfiles.load(for: game.engine) { controls.buttons = profile }
        _controls = State(initialValue: controls)
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GameWebView(session: session).ignoresSafeArea(edges: .bottom)
            if controls.visible {
                ControlLayer(settings: $controls, editing: editingLayout, selection: $selectedControl, send: session.sendKey)
            }
            if session.loading { ProgressView("Opening game…").padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let error = session.error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Unable to play").font(.title2.bold())
                    Text(error).multilineTextAlignment(.center)
                    Button("Exit game") { close() }.buttonStyle(.borderedProminent)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9))
            }
            if editingLayout {
                ControlEditorPanel(settings: $controls, selection: $selectedControl, engine: game.engine) {
                    editingLayout = false; selectedControl = nil; saveControls()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 64)
            }
            HStack {
                Button { menuVisible = true } label: {
                    Image(systemName: "ellipsis").font(.title3.bold()).frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }.accessibilityLabel("Game menu").accessibilityIdentifier("gameMenu")
            }.padding(12)
        }
        .statusBarHidden()
        .task { UIApplication.shared.isIdleTimerDisabled = preventSleep; await session.start() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; session.stop() }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active && preventSleep
            if phase != .active { releaseKeys() }
        }
        .sheet(isPresented: $menuVisible, onDismiss: { saveControls() }) {
            NavigationStack {
                Form {
                    Section {
                        Text(game.title).font(.title2.bold())
                        Text(game.engine.title + " · " + game.engine.compatibility).font(.caption).foregroundStyle(.secondary)
                        Button("Resume", systemImage: "play.fill") { menuVisible = false }
                            .accessibilityIdentifier("resumeGame")
                    }
                    Section("Controls") {
                        Toggle("Show virtual controls", isOn: $controls.visible)
                            .accessibilityIdentifier("virtualControlsToggle")
                        if controls.visible {
                            LabeledContent("Opacity") { Slider(value: $controls.opacity, in: 0.15...1).frame(maxWidth: 180) }
                            Button("Edit controls", systemImage: "hand.draw") { editingLayout = true; menuVisible = false }
                                .accessibilityIdentifier("arrangeControls")
                            Button("Reset layout") { controls = ControlSettings(); controls.visible = true }
                        }
                    }
                    if TranslationPreferences.settings.provider != .off,
                       TranslationPreferences.isEnabled(for: GameSession.translationKey(game)) {
                        Section("Translation") {
                            Toggle("Show original text", isOn: Binding(get: { showOriginal },
                                                                       set: { showOriginal = $0; session.showOriginalText($0) }))
                        }
                    }
                    if game.engine == .rpgMakerMV || game.engine == .rpgMakerMZ {
                        Section("Cheats") {
                            NavigationLink { CheatsView(session: session) } label: {
                                Label("Gold, items, variables, speed", systemImage: "wand.and.stars")
                            }
                            .accessibilityIdentifier("openCheats")
                            NavigationLink { SaveEditorView(session: session) } label: {
                                Label("Save editor", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("openSaveEditor")
                        }
                    }
                    Section("Saving") {
                        Text("Save using the game’s own controls. Its browser storage is kept when you exit and reopen it.")
                        Text("The menu does not pause every game.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Exit to library", systemImage: "rectangle.portrait.and.arrow.right") { close() }
                            .disabled(closing).accessibilityIdentifier("exitGame")
                    }
                }.navigationTitle("Game menu").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium, .large], selection: $menuDetent)
                .presentationDragIndicator(.visible).preferredColorScheme(.dark)
        }
        .onChange(of: menuVisible) { _, shown in if shown { releaseKeys() } }
        .alert("Storage error", isPresented: Binding(get: { storageError != nil }, set: { if !$0 { storageError = nil } })) {
            Button("OK") { storageError = nil }
        } message: { Text(storageError ?? "") }
    }
    private func saveControls() {
        Task {
            do { try await store.updateControls(id: game.id, settings: controls) }
            catch { storageError = error.localizedDescription }
        }
    }
    private func releaseKeys() {
        let keys = Set(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"] + controls.layout.map(\.key)).filter { !$0.isEmpty }
        for key in keys { session.sendKey(key, pressed: false) }
    }
    private func close() {
        guard !closing else { return }
        closing = true; releaseKeys()
        Task {
            do {
                try await store.updateControls(id: game.id, settings: controls)
                if let started = session.startedAt { try await store.recordPlay(id: game.id, seconds: Date().timeIntervalSince(started)) }
                session.stop(); menuVisible = false; dismiss()
            } catch { closing = false; storageError = error.localizedDescription }
        }
    }
}
