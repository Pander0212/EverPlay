import SwiftUI
import UIKit
import Metal
import QuartzCore
import AVFoundation
import CShioriKrkr
import EverPlayCore

/// Plays a KiriKiri game. A tap is a click, a two-finger tap a right click (the game's menu or
/// back); the ☰ button has the backlog, skip, auto mode and leaving.
struct KiriKiriPlayerView: UIViewControllerRepresentable {
    let game: GameRecord
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> KiriKiriGameViewController {
        let root = store.directory(for: game).appendingPathComponent(game.entryPoint).deletingLastPathComponent()
        let close = dismiss
        return KiriKiriGameViewController(title: game.title, gameRoot: root, saves: SaveFolders.libretro(game),
                                          close: { close() })
    }

    func updateUIViewController(_ controller: KiriKiriGameViewController, context: Context) {}
}

final class KiriKiriGameViewController: UIViewController {
    private let gameTitle: String
    private let gameRoot: URL
    private let saves: URL
    private let close: () -> Void
    private var engine: KiriKiriEngine?
    private var presenter: KiriKiriPresenter?
    private var displayLink: CADisplayLink?
    private var ticking = false
    private var frameSize = CGSize(width: 1280, height: 720)
    private var pointerTouch: UITouch?
    private var skipping = false
    private let menuButton = UIButton(configuration: .filled())

    init(title: String, gameRoot: URL, saves: URL, close: @escaping () -> Void) {
        gameTitle = title
        self.gameRoot = gameRoot
        self.saves = saves
        self.close = close
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func loadView() {
        let presenter = KiriKiriPresenter()
        self.presenter = presenter
        view = presenter.view
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let rightClick = UITapGestureRecognizer(target: self, action: #selector(rightClick(_:)))
        rightClick.numberOfTouchesRequired = 2
        rightClick.cancelsTouchesInView = false
        view.addGestureRecognizer(rightClick)

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
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        // Start once the scene has turned to landscape.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.startIfNeeded() }
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        switch KiriKiriEngine.load() {
        case .failure(let error): fail(error.message)
        case .success(let engine):
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            KiriKiriEngine.ask = { [weak self] text, title, buttons in
                MainActor.assumeIsolated { self?.ask(text, title: title, buttons: buttons) ?? 0 }
            }
            EverPlayLog.write("Starting \(gameTitle) with KiriKiri")
            do {
                try engine.run(gameRoot: gameRoot, saves: saves)
            } catch {
                EverPlayLog.write("KiriKiri: \(error.localizedDescription)")
                fail(error.localizedDescription)
                return
            }
            self.engine = engine
            UIApplication.shared.isIdleTimerDisabled = true
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func tick() {
        // A message box runs a nested run loop inside the engine, where the link keeps firing.
        guard let engine, !ticking else { return }
        ticking = true
        defer { ticking = false }
        if engine.tick() == 0 {
            quit()
            return
        }
        var frame = shiorikrkr_frame_t()
        guard engine.frame(&frame) != 0 else { return }
        frameSize = CGSize(width: Int(frame.width), height: Int(frame.height))
        presenter?.present(frame)
    }

    @objc private func pause() { displayLink?.isPaused = true }
    @objc private func resume() { displayLink?.isPaused = false }

    /// The engine ends with the game; EverPlay closes with it (one game per process).
    private func quit() {
        displayLink?.invalidate()
        displayLink = nil
        engine?.stop()
        EverPlayLog.write("\(gameTitle) ended")
        exit(0)
    }

    private func fail(_ message: String) {
        let alert = UIAlertController(title: "Cannot start this game", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.close() })
        present(alert, animated: true)
    }

    /// A question from the game, answered before the engine continues (a nested run loop).
    private func ask(_ text: String, title: String, buttons: [String]) -> Int32 {
        var answer: Int32?
        let alert = UIAlertController(title: title.isEmpty ? nil : title, message: text, preferredStyle: .alert)
        for (index, name) in buttons.enumerated() {
            alert.addAction(UIAlertAction(title: name, style: .default) { _ in answer = Int32(index) })
        }
        present(alert, animated: true)
        while answer == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return answer ?? 0
    }

    // MARK: Menu

    private func makeMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Menu (right click)", image: UIImage(systemName: "contextualmenu.and.cursorarrow")) { [weak self] _ in
                self?.rightClickMiddle()
            },
            UIAction(title: "Backlog", image: UIImage(systemName: "text.bubble")) { [weak self] _ in self?.wheelUp() },
            UIAction(title: "Skip on/off", image: UIImage(systemName: "forward.fill")) { [weak self] _ in self?.toggleSkip() },
            UIAction(title: "Auto mode on/off", image: UIImage(systemName: "play.circle")) { [weak self] _ in self?.toggleAuto() },
            UIAction(title: "Quit game", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                self?.confirmQuit()
            },
        ])
    }

    private func confirmQuit() {
        let alert = UIAlertController(title: "Quit \(gameTitle)?", message: "Save in the game first. EverPlay closes with the game.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Quit", style: .destructive) { [weak self] _ in self?.quit() })
        present(alert, animated: true)
    }

    /// Ctrl held down: KAG skips text while it is.
    private func toggleSkip() {
        skipping.toggle()
        engine?.key(0x11, skipping ? 1 : 0)
    }

    private func toggleAuto() {
        _ = engine?.evaluate("""
            (function() {
                if (typeof global.kag != "Object" || !isvalid kag || typeof kag.enterAutoMode != "Object") return "none";
                if (kag.autoMode) { kag.cancelAutoMode(); return "off"; }
                kag.enterAutoMode();
                return "on";
            })()
            """)
    }

    // MARK: Input

    /// The game picture inside the view (letterboxed, as the presenter draws it).
    private var gameRect: CGRect {
        let bounds = view.bounds
        guard frameSize.width > 0, frameSize.height > 0 else { return bounds }
        let scale = min(bounds.width / frameSize.width, bounds.height / frameSize.height)
        let size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func send(_ phase: Int32, _ point: CGPoint, button: Int32 = Int32(SHIORIKRKR_BUTTON_LEFT)) {
        let rect = gameRect
        guard let engine, rect.width > 0, rect.height > 0 else { return }
        let x = Float(min(max((point.x - rect.minX) / rect.width, 0), 1))
        let y = Float(min(max((point.y - rect.minY) / rect.height, 0), 1))
        engine.pointer(phase, x, y, button)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if skipping { toggleSkip(); return }  // a tap ends skipping
        guard pointerTouch == nil, event?.allTouches?.count ?? 1 == 1, let touch = touches.first else {
            cancelPointer()
            return
        }
        pointerTouch = touch
        send(Int32(SHIORIKRKR_POINTER_DOWN), touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = pointerTouch, touches.contains(touch) else { return }
        send(Int32(SHIORIKRKR_POINTER_MOVED), touch.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = pointerTouch, touches.contains(touch) else { return }
        pointerTouch = nil
        send(Int32(SHIORIKRKR_POINTER_UP), touch.location(in: view))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = pointerTouch, touches.contains(touch) else { return }
        cancelPointer()
    }

    private func cancelPointer() {
        guard let touch = pointerTouch else { return }
        pointerTouch = nil
        send(Int32(SHIORIKRKR_POINTER_CANCEL), touch.location(in: view))
    }

    @objc private func rightClick(_ gesture: UITapGestureRecognizer) {
        cancelPointer()
        let point = gesture.location(in: view)
        send(Int32(SHIORIKRKR_POINTER_DOWN), point, button: Int32(SHIORIKRKR_BUTTON_RIGHT))
        send(Int32(SHIORIKRKR_POINTER_UP), point, button: Int32(SHIORIKRKR_BUTTON_RIGHT))
    }

    private func rightClickMiddle() {
        let point = CGPoint(x: gameRect.midX, y: gameRect.midY)
        send(Int32(SHIORIKRKR_POINTER_DOWN), point, button: Int32(SHIORIKRKR_BUTTON_RIGHT))
        send(Int32(SHIORIKRKR_POINTER_UP), point, button: Int32(SHIORIKRKR_BUTTON_RIGHT))
    }

    /// The mouse wheel turned up in the middle: KAG's backlog.
    private func wheelUp() {
        engine?.wheel(1, 0.5, 0.5)
    }
}

/// Draws the engine's frames letterboxed into a CAMetalLayer: its own texture when it composes
/// on the GPU (after its event), otherwise the frame's pixels copied into a texture.
@MainActor
final class KiriKiriPresenter {
    let view: UIView
    private let layer: CAMetalLayer
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState?
    private var upload: MTLTexture?
    private var lastSerial: UInt64 = .max

    private final class LayerView: UIView {
        override class var layerClass: AnyClass { CAMetalLayer.self }
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    private static let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Out { float4 position [[position]]; float2 uv; };
        vertex Out everplayKrkrVertex(uint id [[vertex_id]], constant float4 &rect [[buffer(0)]],
                                      constant float2 &extent [[buffer(1)]]) {
            float2 corner = float2(id & 1, id >> 1);
            Out out;
            out.position = float4(mix(rect.x, rect.z, corner.x), mix(rect.y, rect.w, corner.y), 0, 1);
            out.uv = float2(corner.x, 1 - corner.y) * extent;
            return out;
        }
        fragment float4 everplayKrkrFragment(Out in [[stage_in]], texture2d<float> frame [[texture(0)]],
                                             sampler linear [[sampler(0)]]) {
            return float4(frame.sample(linear, in.uv).rgb, 1);
        }
        """

    init() {
        let view = LayerView()
        self.view = view
        layer = view.layer as! CAMetalLayer
        device = MTLCreateSystemDefaultDevice()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        queue = device?.makeCommandQueue()
        let library = try? device?.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library?.makeFunction(name: "everplayKrkrVertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "everplayKrkrFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device?.makeRenderPipelineState(descriptor: descriptor)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device?.makeSamplerState(descriptor: samplerDescriptor)
        view.onLayout = { [weak self] in self?.resize() }
    }

    private func resize() {
        let scale = view.window?.screen.scale ?? view.traitCollection.displayScale
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        lastSerial = .max  // draw the next frame even if unchanged
    }

    func present(_ frame: shiorikrkr_frame_t) {
        guard frame.serial != lastSerial, let device, let queue, let pipeline, let sampler,
              frame.width > 0, frame.height > 0 else { return }
        let texture: MTLTexture
        var event: MTLSharedEvent?
        if let engineTexture = frame.texture {
            texture = Unmanaged<AnyObject>.fromOpaque(engineTexture).takeUnretainedValue() as! MTLTexture
            event = frame.event.flatMap { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as? MTLSharedEvent }
        } else if let pixels = frame.pixels {
            let format: MTLPixelFormat = frame.format == Int32(SHIORIKRKR_FRAME_BGRA) ? .bgra8Unorm : .rgba8Unorm
            if upload?.width != Int(frame.width) || upload?.height != Int(frame.height) || upload?.pixelFormat != format {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: Int(frame.width),
                                                                          height: Int(frame.height), mipmapped: false)
                descriptor.usage = .shaderRead
                upload = device.makeTexture(descriptor: descriptor)
            }
            guard let upload else { return }
            upload.replace(region: MTLRegionMake2D(0, 0, Int(frame.width), Int(frame.height)), mipmapLevel: 0,
                           withBytes: pixels, bytesPerRow: Int(frame.pitch))
            texture = upload
        } else {
            return
        }
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        lastSerial = frame.serial
        if let event { buffer.encodeWaitForEvent(event, value: frame.event_value) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // The frame's top-left width x height, letterboxed into the drawable (clip space).
        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let scale = min(target.width / CGFloat(frame.width), target.height / CGFloat(frame.height))
        let w = Float(CGFloat(frame.width) * scale / target.width), h = Float(CGFloat(frame.height) * scale / target.height)
        var rect = SIMD4<Float>(-w, -h, w, h)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        // The frame may be the top-left part of a larger texture.
        var extent = SIMD2<Float>(Float(frame.width) / Float(texture.width), Float(frame.height) / Float(texture.height))
        encoder.setVertexBytes(&extent, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
