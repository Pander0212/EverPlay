import SwiftUI
import EverPlayCore

/// Plays an RPG Maker 2000/2003 game with the bundled EasyRPG Player core.
struct LibretroPlayerView: View {
    let game: GameRecord
    let store: LibraryStore
    @StateObject private var session: LibretroSession
    @State private var controls: ControlSettings
    @State private var menuVisible = false
    @State private var editingLayout = false
    @State private var selectedControl: UUID?
    @State private var notice: String?
    @AppStorage("preventSleep") private var preventSleep = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(game: GameRecord, store: LibraryStore) {
        self.game = game
        self.store = store
        _session = StateObject(wrappedValue: LibretroSession(game: game, directory: store.directory(for: game)))
        var controls = game.controls
        if controls.buttons == nil, let profile = ControlProfiles.load(for: game.engine) { controls.buttons = profile }
        // The core has no touch input, so its controls start visible.
        if game.playSeconds == 0 && game.lastPlayedAt == nil { controls.visible = true }
        _controls = State(initialValue: controls)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let frame = session.frame {
                Image(decorative: frame, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .accessibilityLabel("Game screen")
            } else if session.error == nil {
                ProgressView("Starting \(game.title)…").tint(.white).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if controls.visible {
                ControlLayer(settings: $controls, editing: editingLayout, selection: $selectedControl) { key, down in
                    session.press(key, down)
                }
            }
            if let error = session.error {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Unable to play").font(.title2.bold())
                    Text(error).multilineTextAlignment(.center)
                    Button("Exit game") { close() }.buttonStyle(.borderedProminent)
                }
                .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9))
                .foregroundStyle(.white)
            }
            if editingLayout {
                ControlEditorPanel(settings: $controls, selection: $selectedControl, engine: game.engine) {
                    editingLayout = false; selectedControl = nil; saveControls()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 64)
            }
            Button { menuVisible = true } label: {
                Image(systemName: "ellipsis").font(.title3.bold()).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Game menu").accessibilityIdentifier("gameMenu")
            .padding(12)
            if let notice {
                Text(notice).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            UIApplication.shared.isIdleTimerDisabled = preventSleep
            session.start()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; session.stop() }
        .onChange(of: scenePhase) { _, phase in session.setPaused(phase != .active || menuVisible) }
        .onChange(of: menuVisible) { _, shown in session.setPaused(shown) }
        .sheet(isPresented: $menuVisible, onDismiss: { saveControls() }) { menu }
    }

    private var menu: some View {
        NavigationStack {
            Form {
                Section {
                    Text(game.title).font(.title2.bold())
                    Text(game.engine.title + " · " + game.engine.compatibility).font(.caption).foregroundStyle(.secondary)
                    Button("Resume", systemImage: "play.fill") { menuVisible = false }.accessibilityIdentifier("resumeGame")
                }
                Section {
                    Button("Quick save", systemImage: "square.and.arrow.down") {
                        session.quickSave { ok in show(ok ? "Saved" : "Quick save is not available here") }
                        menuVisible = false
                    }
                    Button("Quick load", systemImage: "square.and.arrow.up") {
                        session.quickLoad { ok in show(ok ? "Loaded" : "No quick save yet") }
                        menuVisible = false
                    }
                    .disabled(!session.hasQuickSave)
                    Button("Restart game", systemImage: "arrow.counterclockwise") { session.reset(); menuVisible = false }
                } header: {
                    Text("Game")
                } footer: {
                    Text("Quick save stores the whole game state, also where the game itself does not allow saving. The game's own save slots work as usual.")
                }
                Section("Controls") {
                    Toggle("Show virtual controls", isOn: $controls.visible).accessibilityIdentifier("virtualControlsToggle")
                    if controls.visible {
                        LabeledContent("Opacity") { Slider(value: $controls.opacity, in: 0.15...1).frame(maxWidth: 180) }
                        Button("Edit controls", systemImage: "hand.draw") { editingLayout = true; menuVisible = false }
                            .accessibilityIdentifier("arrangeControls")
                    }
                    Text("Keys: Z, Enter or Space confirm; X, Esc or Backspace cancel and open the menu; Shift is the third button.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Exit to library", systemImage: "rectangle.portrait.and.arrow.right") { close() }
                        .accessibilityIdentifier("exitGame")
                }
            }
            .navigationTitle("Game menu").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { notice = nil } }
    }

    private func saveControls() {
        Task { try? await store.updateControls(id: game.id, settings: controls) }
    }

    private func close() {
        session.stop()
        Task {
            try? await store.updateControls(id: game.id, settings: controls)
            if let started = session.startedAt { try? await store.recordPlay(id: game.id, seconds: Date().timeIntervalSince(started)) }
            menuVisible = false
            dismiss()
        }
    }
}

@MainActor
final class LibretroSession: ObservableObject {
    @Published var frame: CGImage?
    @Published var error: String?
    @Published private(set) var hasQuickSave = false
    private(set) var startedAt: Date?
    private let game: GameRecord
    private let core: LibretroCore
    private var started = false

    init(game: GameRecord, directory: URL) {
        self.game = game
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        core = LibretroCore(gamePath: directory.appendingPathComponent(game.entryPoint).path,
                            saveDirectory: SaveFolders.libretro(game),
                            systemDirectory: support.appendingPathComponent("EverPlay/libretro-system", isDirectory: true))
        hasQuickSave = FileManager.default.fileExists(atPath: quickSaveFile.path)
    }

    private var quickSaveFile: URL { core.saveDirectory.appendingPathComponent("EverPlay quick save.state") }

    func start() {
        guard !started else { return }
        started = true
        core.onFrame = { [weak self] image in MainActor.assumeIsolated { self?.frame = image } }
        do {
            try core.start()
            startedAt = Date()
            EverPlayLog.write("Started RPG Maker 2000/2003 game \(game.title) with EasyRPG Player")
        } catch {
            self.error = error.localizedDescription
            EverPlayLog.write("RPG Maker 2000/2003 game \(game.title) failed to start: \(error)")
        }
    }

    func stop() { core.stop() }
    func setPaused(_ paused: Bool) { core.setPaused(paused) }
    func reset() { core.resetGame() }

    func quickSave(_ done: @escaping (Bool) -> Void) {
        core.saveState(to: quickSaveFile) { [weak self] ok in
            MainActor.assumeIsolated {
                if ok { self?.hasQuickSave = true }
                done(ok)
            }
        }
    }

    func quickLoad(_ done: @escaping (Bool) -> Void) { core.loadState(from: quickSaveFile, completion: done) }

    /// Keyboard keys of the shared control layer, mapped to the joypad EasyRPG reads.
    func press(_ key: String, _ down: Bool) {
        let mapping: [String: LibretroCore.Button] = [
            "ArrowUp": .up, "ArrowDown": .down, "ArrowLeft": .left, "ArrowRight": .right,
            "z": .a, "Enter": .a, " ": .a,
            "x": .b, "Escape": .b, "Backspace": .b,
            "Shift": .x, "c": .y, "PageUp": .l, "PageDown": .r, "Tab": .select, "F12": .start,
        ]
        if let button = mapping[key] { core.set(button, pressed: down) }
    }
}

enum SaveFolders {
    /// Saves of native (libretro) games, visible in Files under On My iPhone › EverPlay › Saves, like Ren'Py saves.
    static func libretro(_ game: GameRecord) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saves/\(game.title.replacingOccurrences(of: "/", with: "-"))", isDirectory: true)
    }
}
