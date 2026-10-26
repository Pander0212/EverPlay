import SwiftUI
import UIKit
import AVFoundation
import EverPlayCore

/// Plays a Godot game. Godot turns taps into mouse clicks itself; a two-finger tap is a right
/// click, and the ☰ button sends Escape, Enter and the arrow keys and leaves the game.
struct GodotPlayerView: UIViewControllerRepresentable {
    let game: GameRecord
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GodotGameViewController {
        let pack = store.directory(for: game).appendingPathComponent(game.entryPoint)
        let close = dismiss
        return GodotGameViewController(title: game.title, pack: pack, saves: SaveFolders.libretro(game), close: { close() })
    }

    func updateUIViewController(_ controller: GodotGameViewController, context: Context) {}
}

final class GodotGameViewController: UIViewController {
    private let gameTitle: String
    private let pack: URL
    private let saves: URL
    private let close: () -> Void
    private var engine: GodotEngine?
    private var game: UIViewController?
    private let menuButton = UIButton(configuration: .filled())

    init(title: String, pack: URL, saves: URL, close: @escaping () -> Void) {
        gameTitle = title
        self.pack = pack
        self.saves = saves
        self.close = close
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        var style = UIButton.Configuration.filled()
        style.image = UIImage(systemName: "line.3.horizontal")
        style.cornerStyle = .capsule
        style.baseBackgroundColor = UIColor(white: 0, alpha: 0.35)
        style.baseForegroundColor = .white
        menuButton.configuration = style
        menuButton.accessibilityLabel = "EverPlay menu"
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = makeMenu()
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(resignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        // Start once the scene has turned to landscape: Godot sizes its window from the view.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.startIfNeeded() }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let framework: String
        do {
            guard let header = GodotPack.read(pack) else { throw GodotError("The game's Godot pack was not found in \(pack.lastPathComponent).") }
            framework = try GodotRuntime.framework(for: header)
            EverPlayLog.write("Starting \(gameTitle) (Godot \(header.version)) with \(framework)")
        } catch {
            fail(error.localizedDescription)
            return
        }
        switch GodotEngine.load(framework) {
        case .failure(let error): fail(error.message)
        case .success(let engine):
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let controller: UIViewController
            do {
                controller = try engine.run(pack: pack, saves: saves) { code in
                    // Called by Godot (main thread) when the game quits.
                    EverPlayLog.write("Godot game ended (\(code))")
                    exit(0)
                }
            } catch {
                EverPlayLog.write("Godot: \(error.localizedDescription)")
                fail(error.localizedDescription)
                return
            }
            self.engine = engine
            game = controller
            addChild(controller)
            controller.view.frame = view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(controller.view, belowSubview: menuButton)
            controller.didMove(toParent: self)
            let rightClick = UITapGestureRecognizer(target: self, action: #selector(rightClick(_:)))
            rightClick.numberOfTouchesRequired = 2
            rightClick.cancelsTouchesInView = false
            controller.view.addGestureRecognizer(rightClick)
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    @objc private func resignActive() { engine?.appState(0) }
    @objc private func becomeActive() { engine?.appState(1) }
    @objc private func enterBackground() { engine?.appState(2) }
    @objc private func enterForeground() { engine?.appState(3) }
    @objc private func memoryWarning() { engine?.memoryWarning() }

    private func fail(_ message: String) {
        let alert = UIAlertController(title: "Cannot start this game", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in self?.close() })
        present(alert, animated: true)
    }

    // MARK: Menu

    private func makeMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Escape (menu or back)", image: UIImage(systemName: "escape")) { [weak self] _ in
                self?.press(GodotEngine.Keys.escape)
            },
            UIAction(title: "Right click", image: UIImage(systemName: "contextualmenu.and.cursorarrow")) { [weak self] _ in
                guard let self else { return }
                self.click(button: 2, at: CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY))
            },
            UIMenu(title: "Keys", image: UIImage(systemName: "keyboard"), children: [
                ("Enter", GodotEngine.Keys.enter), ("Space", GodotEngine.Keys.space), ("Tab", GodotEngine.Keys.tab),
                ("Up", GodotEngine.Keys.up), ("Down", GodotEngine.Keys.down),
                ("Left", GodotEngine.Keys.left), ("Right", GodotEngine.Keys.right),
            ].map { name, code in
                UIAction(title: name) { [weak self] _ in self?.press(code) }
            }),
            UIAction(title: "Quit game", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                self?.confirmQuit()
            },
        ])
    }

    private func confirmQuit() {
        let alert = UIAlertController(title: "Quit \(gameTitle)?", message: "Save in the game first. EverPlay closes with the game.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Quit", style: .destructive) { [weak self] _ in
            EverPlayLog.write("\(self?.gameTitle ?? "Godot game") quit from EverPlay's menu")
            exit(0)
        })
        present(alert, animated: true)
    }

    // MARK: Input

    private func press(_ key: Int32) {
        let character: Int32 = key == GodotEngine.Keys.space ? 0x20 : 0
        engine?.key(key, character, 1)
        engine?.key(key, 0, 0)
    }

    private func click(button: Int32, at point: CGPoint) {
        guard let engine, let target = game?.view else { return }
        let local = view.convert(point, to: target)
        engine.mouseButton(button, 1, Float(local.x), Float(local.y))
        engine.mouseButton(button, 0, Float(local.x), Float(local.y))
    }

    @objc private func rightClick(_ gesture: UITapGestureRecognizer) {
        click(button: 2, at: gesture.location(in: view))
    }
}
