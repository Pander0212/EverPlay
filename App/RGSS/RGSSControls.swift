import SwiftUI
import UIKit
import EverPlayCore

/// Touch controls over an RPG Maker XP/VX/VX Ace game: the player's layout (the same editor as
/// MV/MZ and 2000/2003 games), drawn over SDL's window and sent to mkxp-z as keyboard keys.
@MainActor
enum RGSSControls {
    typealias SendKey = @convention(c) (Int32, Int32) -> Void
    private static var sendKey: SendKey?
    private static var game: GameRecord?
    static private(set) var settings = ControlSettings()
    private static weak var overlay: RGSSControlOverlay?

    /// Starts looking for SDL's window; false when the framework draws its own controls (older builds).
    @discardableResult
    static func install(game: GameRecord, framework handle: UnsafeMutableRawPointer) -> Bool {
        guard let symbol = dlsym(handle, "everplay_mkxp_key") else { return false }
        sendKey = unsafeBitCast(symbol, to: SendKey.self)
        self.game = game
        settings = load(game)
        // A run loop timer: mkxp-z's game loop runs the main run loop, not the main queue.
        let timer = Timer(timeInterval: 0.3, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard let window = sdlWindow() else { return }
                timer.invalidate()
                let overlay = RGSSControlOverlay(frame: window.bounds)
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                window.addSubview(overlay)
                overlay.apply(settings)
                self.overlay = overlay
                EverPlayLog.write("RPG Maker touch controls attached")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    private static func sdlWindow() -> UIWindow? {
        guard let type = NSClassFromString("SDL_uikitwindow") else { return nil }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKind(of: type) }
    }

    static func send(_ key: String, _ down: Bool) {
        guard let code = scancodes[key] else { return }
        sendKey?(down ? 1 : 0, code)
    }

    /// SDL scancodes of the keys in ControlKey.catalog.
    static let scancodes: [String: Int32] = {
        var codes: [String: Int32] = [
            "ArrowRight": 79, "ArrowLeft": 80, "ArrowDown": 81, "ArrowUp": 82,
            "Enter": 40, "Escape": 41, "Backspace": 42, "Tab": 43, " ": 44,
            "PageUp": 75, "PageDown": 78, "Control": 224, "Shift": 225, "0": 39,
        ]
        for (index, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() { codes[String(letter)] = Int32(4 + index) }
        for digit in 1...9 { codes[String(digit)] = Int32(29 + digit) }
        for number in 1...12 { codes["F\(number)"] = Int32(57 + number) }
        return codes
    }()

    // MARK: Settings

    private static func defaultsKey(_ game: GameRecord) -> String { "rgssControls.\(game.id.uuidString)" }

    /// The game's layout: edited here before, else the XP/VX default saved in the editor, else EverPlay's.
    static func load(_ game: GameRecord) -> ControlSettings {
        if let data = UserDefaults.standard.data(forKey: defaultsKey(game)),
           let settings = try? JSONDecoder().decode(ControlSettings.self, from: data) {
            return settings
        }
        var settings = game.controls
        settings.visible = true
        if settings.buttons == nil { settings.buttons = ControlProfiles.load(for: .rgss) ?? ControlButton.rgssLayout }
        return settings
    }

    static func update(_ change: (inout ControlSettings) -> Void) {
        change(&settings)
        if let game { UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: defaultsKey(game)) }
        overlay?.apply(settings)
    }

    // MARK: Screens over the game

    private static func topController() -> UIViewController? {
        guard var top = sdlWindow()?.rootViewController
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
                .first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func showMenu(from button: UIView) {
        overlay?.releaseAll()
        guard let top = topController() else {
            EverPlayLog.write("RPG Maker menu: no view controller to show it on")
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cheats", style: .default) { _ in showCheats() })
        sheet.addAction(UIAlertAction(title: "Edit controls", style: .default) { _ in editLayout() })
        sheet.addAction(UIAlertAction(title: settings.visible ? "Hide controls" : "Show controls", style: .default) { _ in
            update { $0.visible.toggle() }
        })
        sheet.addAction(UIAlertAction(title: "Control opacity…", style: .default) { _ in showOpacity(from: button) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = button
        sheet.popoverPresentationController?.sourceRect = button.bounds
        top.present(sheet, animated: true)
    }

    private static func showOpacity(from button: UIView) {
        guard let top = topController() else { return }
        let sheet = UIAlertController(title: "Control opacity", message: nil, preferredStyle: .actionSheet)
        for value in [0.25, 0.45, 0.65, 0.85, 1.0] {
            let title = "\(Int((value * 100).rounded())) %" + (abs(settings.opacity - value) < 0.01 ? "  ✓" : "")
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in update { $0.opacity = value } })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = button
        sheet.popoverPresentationController?.sourceRect = button.bounds
        top.present(sheet, animated: true)
    }

    static func showCheats() {
        overlay?.releaseAll()
        guard let top = topController() else { return }
        top.present(RGSSCheatBridge.screen(), animated: true)
    }

    static func editLayout() {
        overlay?.releaseAll()
        guard let top = topController() else { return }
        let box = ControllerBox()
        let editor = RGSSControlEditor(settings: settings) { edited in
            update { $0 = edited }
            box.controller?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: editor)
        controller.modalPresentationStyle = .overFullScreen
        controller.view.backgroundColor = .clear
        box.controller = controller
        top.present(controller, animated: true)
    }

    final class ControllerBox {
        weak var controller: UIViewController?
    }
}

/// Arrange mode over the game, with the shared control layer and editor panel.
private struct RGSSControlEditor: View {
    @State private var settings: ControlSettings
    @State private var selection: UUID?
    let done: (ControlSettings) -> Void

    init(settings: ControlSettings, done: @escaping (ControlSettings) -> Void) {
        _settings = State(initialValue: settings)
        self.done = done
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ControlLayer(settings: $settings, editing: true, selection: $selection) { _, _ in }
                .ignoresSafeArea()
            ControlEditorPanel(settings: $settings, selection: $selection, engine: .rgss) { done(settings) }
                .frame(maxWidth: 620)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
    }
}

/// The controls in play: touches outside them reach the game.
final class RGSSControlOverlay: UIView {
    private var controls: [(view: UIView, button: ControlButton)] = []
    private let toggle = UIButton(configuration: .filled())
    private let menu = UIButton(configuration: .filled())

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        for (button, image, label) in [(toggle, "gamecontroller", "Show or hide controls"), (menu, "line.3.horizontal", "EverPlay menu")] {
            var style = UIButton.Configuration.filled()
            style.image = UIImage(systemName: image)
            style.cornerStyle = .capsule
            style.baseBackgroundColor = UIColor(white: 0, alpha: 0.35)
            style.baseForegroundColor = .white
            button.configuration = style
            button.accessibilityLabel = label
            addSubview(button)
        }
        toggle.addAction(UIAction { _ in RGSSControls.update { $0.visible.toggle() } }, for: .touchUpInside)
        // An action sheet, not a UIMenu: mkxp-z's game loop never runs the run loop mode a menu needs.
        menu.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            RGSSControls.showMenu(from: self.menu)
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func apply(_ settings: ControlSettings) {
        releaseAll()
        controls.forEach { $0.view.removeFromSuperview() }
        controls = settings.visible ? settings.layout.map { button in
            let view: UIView = button.kind == .dpad ? RGSSPad() : RGSSKey(label: button.label, key: button.key, toggles: button.toggles)
            view.alpha = settings.opacity
            insertSubview(view, belowSubview: toggle)
            return (view, button)
        } : []
        toggle.configuration?.image = UIImage(systemName: settings.visible ? "gamecontroller.fill" : "gamecontroller")
        setNeedsLayout()
    }

    func releaseAll() {
        for (view, _) in controls {
            (view as? RGSSPad)?.set(horizontal: 0, vertical: 0)
            (view as? RGSSKey)?.down = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (view, button) in controls {
            let size = (button.kind == .dpad ? 150 : 60) * button.scale
            view.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            view.center = CGPoint(x: bounds.width * button.x, y: bounds.height * button.y)
        }
        let top = safeAreaInsets.top + 10, left = safeAreaInsets.left + 12
        toggle.frame = CGRect(x: left, y: top, width: 44, height: 36)
        menu.frame = CGRect(x: left + 52, y: top, width: 44, height: 36)
    }
}

/// Eight directions of 45° each around a small dead zone, as arrow keys.
private final class RGSSPad: UIView {
    private var horizontal = 0, vertical = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.45)
        layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        layer.borderWidth = 1.5
        for (index, name) in ["chevron.up", "chevron.down", "chevron.left", "chevron.right"].enumerated() {
            let arrow = UIImageView(image: UIImage(systemName: name))
            arrow.tintColor = UIColor(white: 1, alpha: 0.85)
            arrow.tag = index + 1
            addSubview(arrow)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.width, inset = size * 0.18
        layer.cornerRadius = size / 2
        let centers = [CGPoint(x: size / 2, y: inset), CGPoint(x: size / 2, y: size - inset),
                       CGPoint(x: inset, y: size / 2), CGPoint(x: size - inset, y: size / 2)]
        for (index, center) in centers.enumerated() { viewWithTag(index + 1)?.center = center }
    }

    func set(horizontal: Int, vertical: Int) {
        if horizontal != self.horizontal {
            if self.horizontal != 0 { RGSSControls.send(self.horizontal < 0 ? "ArrowLeft" : "ArrowRight", false) }
            if horizontal != 0 { RGSSControls.send(horizontal < 0 ? "ArrowLeft" : "ArrowRight", true) }
            self.horizontal = horizontal
        }
        if vertical != self.vertical {
            if self.vertical != 0 { RGSSControls.send(self.vertical < 0 ? "ArrowUp" : "ArrowDown", false) }
            if vertical != 0 { RGSSControls.send(vertical < 0 ? "ArrowUp" : "ArrowDown", true) }
            self.vertical = vertical
        }
    }

    private func track(_ touches: Set<UITouch>) {
        guard let point = touches.first?.location(in: self) else { return }
        let dx = point.x - bounds.midX, dy = point.y - bounds.midY
        guard hypot(dx, dy) >= bounds.width * 0.12 else { return set(horizontal: 0, vertical: 0) }
        let sector = Int((atan2(dy, dx) * 180 / .pi / 45).rounded()) + 4
        let h = [-1, -1, 0, 1, 1, 1, 0, -1, -1], v = [0, -1, -1, -1, 0, 1, 1, 1, 0]
        set(horizontal: h[sector], vertical: v[sector])
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { track(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { track(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { set(horizontal: 0, vertical: 0) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { set(horizontal: 0, vertical: 0) }
}

/// One key; a hold key stays down from one tap to the next.
private final class RGSSKey: UIView {
    private let key: String
    private let toggles: Bool
    private let label = UILabel()

    var down = false {
        didSet {
            guard down != oldValue else { return }
            RGSSControls.send(key, down)
            backgroundColor = down ? UIColor.systemMint : UIColor(white: 0, alpha: 0.45)
            label.textColor = down ? .black : .white
        }
    }

    init(label text: String, key: String, toggles: Bool) {
        self.key = key
        self.toggles = toggles
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.45)
        layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        layer.borderWidth = 1.5
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: text.count > 3 ? 14 : 18, weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.textAlignment = .center
        addSubview(label)
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        label.frame = bounds.insetBy(dx: 6, dy: 6)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { if !toggles { down = true } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if toggles { down.toggle() } else { down = false } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { if !toggles { down = false } }
}
