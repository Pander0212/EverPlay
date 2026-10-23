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
    @State private var storageError: String?
    @State private var closing = false
    @AppStorage("preventSleep") private var preventSleep = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(game: GameRecord, store: LibraryStore) {
        self.game = game; self.store = store
        _session = StateObject(wrappedValue: GameSession(game: game, root: store.directory(for: game)))
        _controls = State(initialValue: game.controls)
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GameWebView(session: session).ignoresSafeArea(edges: .bottom)
            if controls.visible {
                VirtualControls(settings: $controls, editing: editingLayout, send: session.sendKey)
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
            HStack {
                if editingLayout {
                    Text("Drag each control group").font(.caption)
                    Button("Done") { editingLayout = false; saveControls() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("finishControlLayout")
                }
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
                            Button("Arrange controls", systemImage: "hand.draw") { editingLayout = true; menuVisible = false }
                                .accessibilityIdentifier("arrangeControls")
                            Button("Reset layout") { controls = ControlSettings(); controls.visible = true }
                        }
                    }
                    if game.engine == .rpgMakerMV || game.engine == .rpgMakerMZ {
                        Section("Cheats") {
                            NavigationLink { CheatsView(session: session) } label: {
                                Label("Gold, items, variables, speed", systemImage: "wand.and.stars")
                            }
                            .accessibilityIdentifier("openCheats")
                        }
                    }
                    Section("Saving") {
                        Text("Save using the game’s own controls. Its browser storage is kept when you exit and reopen it.")
                        Text("The menu does not pause every game. Native save export and restore are not available yet.")
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
    private func releaseKeys() { for key in ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Enter", "Escape", "z", "x"] { session.sendKey(key, pressed: false) } }
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

private struct VirtualControls: View {
    @Binding var settings: ControlSettings
    let editing: Bool
    let send: (String, Bool) -> Void
    var body: some View {
        GeometryReader { geometry in
            dpad
                .opacity(settings.opacity)
                .padding(8).background(editing ? Color.mint.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(coordinateSpace: .named("controls")).onChanged { value in
                    guard editing else { return }
                    settings.leftX = min(0.82, max(0.18, value.location.x / geometry.size.width))
                    settings.leftY = min(0.82, max(0.18, value.location.y / geometry.size.height))
                }, including: editing ? .all : .subviews)
                .position(x: geometry.size.width * settings.leftX, y: geometry.size.height * settings.leftY)
            actions
                .opacity(settings.opacity)
                .padding(8).background(editing ? Color.mint.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(coordinateSpace: .named("controls")).onChanged { value in
                    guard editing else { return }
                    settings.rightX = min(0.82, max(0.18, value.location.x / geometry.size.width))
                    settings.rightY = min(0.82, max(0.18, value.location.y / geometry.size.height))
                }, including: editing ? .all : .subviews)
                .position(x: geometry.size.width * settings.rightX, y: geometry.size.height * settings.rightY)
        }.coordinateSpace(name: "controls")
    }
    private var dpad: some View {
        VStack(spacing: 4) {
            key("↑", "ArrowUp")
            HStack(spacing: 4) { key("←", "ArrowLeft"); Color.clear.frame(width: 42, height: 42); key("→", "ArrowRight") }
            key("↓", "ArrowDown")
        }
    }
    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { key("B", "x"); key("A", "z") }
            HStack(spacing: 8) { key("Esc", "Escape"); key("↵", "Enter") }
        }
    }
    private func key(_ label: String, _ key: String) -> some View {
        VirtualKey(label: label, key: key, enabled: !editing, send: send)
    }
}

private struct VirtualKey: View {
    let label: String
    let key: String
    let enabled: Bool
    let send: (String, Bool) -> Void
    @State private var pressed = false
    var body: some View {
        Text(label).font(.headline).frame(width: 42, height: 42)
            .background(pressed ? Color.mint : Color.gray.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(pressed ? .black : .white)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if enabled && !pressed { pressed = true; send(key, true) }
            }.onEnded { _ in if pressed { pressed = false; send(key, false) } }, including: enabled ? .all : .none)
            .onDisappear { if pressed { send(key, false); pressed = false } }
            .accessibilityLabel(key).accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { send(key, true); send(key, false) } }
    }
}
