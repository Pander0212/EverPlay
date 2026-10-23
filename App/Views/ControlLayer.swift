import SwiftUI
import EverPlayCore

/// The on-screen controls of a web game. In arrange mode every control can be dragged and
/// selected; otherwise keys send key events to the game.
struct ControlLayer: View {
    @Binding var settings: ControlSettings
    let editing: Bool
    @Binding var selection: UUID?
    let send: (String, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            ForEach(settings.layout) { button in
                control(button)
                    .scaleEffect(button.scale)
                    .opacity(settings.opacity)
                    .padding(8)
                    .background(highlight(button), in: RoundedRectangle(cornerRadius: 20))
                    .contentShape(Rectangle())
                    .highPriorityGesture(arrangeGesture(button, in: geometry.size), including: editing ? .gesture : .subviews)
                    .position(x: geometry.size.width * button.x, y: geometry.size.height * button.y)
            }
        }
        .coordinateSpace(name: "controls")
    }

    private func highlight(_ button: ControlButton) -> Color {
        guard editing else { return .clear }
        return selection == button.id ? Theme.accent.opacity(0.4) : Color.mint.opacity(0.2)
    }

    private func arrangeGesture(_ button: ControlButton, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("controls"))
            .onChanged { value in
                selection = button.id
                guard hypot(value.translation.width, value.translation.height) > 4 else { return }
                update(button.id) {
                    $0.x = min(0.95, max(0.05, value.location.x / max(size.width, 1)))
                    $0.y = min(0.95, max(0.05, value.location.y / max(size.height, 1)))
                }
            }
    }

    private func update(_ id: UUID, _ change: (inout ControlButton) -> Void) {
        var buttons = settings.layout
        guard let index = buttons.firstIndex(where: { $0.id == id }) else { return }
        change(&buttons[index])
        settings.buttons = buttons
    }

    @ViewBuilder
    private func control(_ button: ControlButton) -> some View {
        switch button.kind {
        case .dpad:
            VStack(spacing: 4) {
                key("↑", "ArrowUp")
                HStack(spacing: 4) { key("←", "ArrowLeft"); Color.clear.frame(width: 46, height: 46); key("→", "ArrowRight") }
                key("↓", "ArrowDown")
            }
        case .key:
            VirtualKey(label: button.label, key: button.key, toggles: button.toggles, round: true, enabled: !editing, send: send)
        }
    }

    private func key(_ label: String, _ key: String) -> some View {
        VirtualKey(label: label, key: key, toggles: false, round: false, enabled: !editing, send: send)
    }
}

struct VirtualKey: View {
    let label: String
    let key: String
    let toggles: Bool
    let round: Bool
    let enabled: Bool
    let send: (String, Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 3 ? 13 : 17, weight: .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: 46, height: 46)
            .background(pressed ? Color.mint : Color.black.opacity(0.45), in: shape)
            .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 1))
            .foregroundStyle(pressed ? .black : .white)
            .contentShape(Rectangle())
            .gesture(touch, including: enabled ? .all : .none)
            .onDisappear { if pressed { send(key, false); pressed = false } }
            .accessibilityLabel(key)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { if toggles { flip() } else { send(key, true); send(key, false) } } }
    }

    private var shape: AnyShape { round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)) }

    /// Held keys press on touch-down and release on lift; toggle keys flip on lift.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in if !toggles && !pressed { pressed = true; send(key, true) } }
            .onEnded { _ in
                if toggles { flip() } else if pressed { pressed = false; send(key, false) }
            }
    }

    private func flip() {
        pressed.toggle()
        send(key, pressed)
    }
}

/// The arrange-mode panel: selected control's size, toggle mode and removal; adding keys; profiles.
struct ControlEditorPanel: View {
    @Binding var settings: ControlSettings
    @Binding var selection: UUID?
    let engine: GameEngine
    let done: () -> Void
    @State private var savedNotice = false

    private var selected: ControlButton? { settings.layout.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 10) {
            if let selected {
                HStack(spacing: 12) {
                    Text(selected.kind == .dpad ? "D-pad" : "Key \(selected.label)").font(.subheadline.bold())
                    Slider(value: Binding(get: { selected.scale }, set: { value in change { $0.scale = value } }), in: 0.6...1.8)
                        .frame(maxWidth: 160)
                    if selected.kind == .key {
                        Toggle("Hold", isOn: Binding(get: { selected.toggles }, set: { value in change { $0.toggles = value } }))
                            .toggleStyle(.button)
                    }
                    Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Remove control")
                }
            } else {
                Text("Drag controls to move them. Tap one to resize it or remove it.").font(.caption)
            }
            HStack(spacing: 10) {
                Menu {
                    if !settings.layout.contains(where: { $0.kind == .dpad }) {
                        Button("D-pad") { add(ControlButton(kind: .dpad, key: "", label: "D-pad", x: 0.2, y: 0.7)) }
                    }
                    ForEach(ControlKey.catalog, id: \.key) { key in
                        Button("\(key.label)  (\(key.code))") { add(ControlButton(key: key.key, label: key.label, x: 0.5, y: 0.5)) }
                    }
                } label: { Label("Add", systemImage: "plus.circle") }
                    .accessibilityIdentifier("addControl")
                Menu {
                    Button("Save as default for \(engine.title)") { ControlProfiles.save(settings.layout, for: engine); savedNotice = true }
                    if let profile = ControlProfiles.load(for: engine) {
                        Button("Use the \(engine.title) default") { settings.buttons = profile; selection = nil }
                    }
                    Button("Reset to EverPlay's layout", role: .destructive) { settings.buttons = ControlButton.defaultLayout(); selection = nil }
                } label: { Label("Layout", systemImage: "square.grid.3x3") }
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("finishControlLayout")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .alert("Saved", isPresented: $savedNotice) { Button("OK") {} } message: {
            Text("New \(engine.title) games start with this layout.")
        }
    }

    private func change(_ edit: (inout ControlButton) -> Void) {
        var buttons = settings.layout
        guard let index = buttons.firstIndex(where: { $0.id == selection }) else { return }
        edit(&buttons[index])
        settings.buttons = buttons
    }

    private func add(_ button: ControlButton) {
        settings.buttons = settings.layout + [button]
        selection = button.id
    }

    private func remove() {
        settings.buttons = settings.layout.filter { $0.id != selection }
        selection = nil
    }
}

/// Per-engine default layouts (Save as default), used by games whose layout was never edited.
enum ControlProfiles {
    static func load(for engine: GameEngine) -> [ControlButton]? {
        guard let data = UserDefaults.standard.data(forKey: "controls.profile.\(engine.rawValue)") else { return nil }
        return try? JSONDecoder().decode([ControlButton].self, from: data)
    }

    static func save(_ buttons: [ControlButton], for engine: GameEngine) {
        UserDefaults.standard.set(try? JSONEncoder().encode(buttons), forKey: "controls.profile.\(engine.rawValue)")
    }
}
