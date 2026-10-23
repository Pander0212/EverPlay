import AVFoundation
import UIKit

/// A minimal libretro frontend for software-rendered cores (EasyRPG Player for RPG Maker
/// 2000/2003). The core is a bundled framework, loaded with dlopen and driven from one thread,
/// as libretro requires. Its C callbacks have no context pointer, so one session runs at a time
/// through `LibretroCore.active`.
final class LibretroCore: @unchecked Sendable {
    /// Joypad buttons (RETRO_DEVICE_ID_JOYPAD_*).
    enum Button: Int, CaseIterable {
        case b = 0, y, select, start, up, down, left, right, a, x, l, r
    }

    fileprivate static var active: LibretroCore?

    let gamePath: String
    let saveDirectory: URL
    let systemDirectory: URL
    /// Receives each new frame on the main thread.
    var onFrame: ((CGImage) -> Void)?
    var onEnd: ((String?) -> Void)?

    private var handle: UnsafeMutableRawPointer?
    private var run: (@convention(c) () -> Void)?
    private var serializeSize: (@convention(c) () -> Int)?
    private var serialize: (@convention(c) (UnsafeMutableRawPointer?, Int) -> Bool)?
    private var unserialize: (@convention(c) (UnsafeRawPointer?, Int) -> Bool)?
    private var reset: (@convention(c) () -> Void)?
    private var unload: (@convention(c) () -> Void)?
    private var deinitCore: (@convention(c) () -> Void)?

    fileprivate var pixelFormat: UInt32 = 0  // 0RGB1555 until the core says otherwise
    fileprivate var shutdownRequested = false
    fileprivate var frameTimeCallback: (@convention(c) (Int64) -> Void)?
    fileprivate var audioCallback: (@convention(c) () -> Void)?
    fileprivate let savePath: UnsafeMutablePointer<CChar>
    fileprivate let systemPath: UnsafeMutablePointer<CChar>

    private let inputLock = NSLock()
    private var pressed: UInt32 = 0
    private var thread: Thread?
    private var running = false
    private var paused = false
    private var pendingWork: [() -> Void] = []
    private var fps = 60.0
    fileprivate var sampleRate = 44_100.0
    fileprivate let audio = LibretroAudio()

    init(gamePath: String, saveDirectory: URL, systemDirectory: URL) {
        self.gamePath = gamePath
        self.saveDirectory = saveDirectory
        self.systemDirectory = systemDirectory
        savePath = strdup(saveDirectory.path)
        systemPath = strdup(systemDirectory.path)
    }

    deinit {
        free(savePath)
        free(systemPath)
    }

    static var bundledCore: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("easyrpg_libretro.framework/easyrpg_libretro")
    }

    static var isAvailable: Bool {
        bundledCore.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: - Lifecycle (main thread)

    func start() throws {
        guard LibretroCore.active == nil else { throw LibretroError.busy }
        guard let core = Self.bundledCore, let handle = dlopen(core.path, RTLD_NOW | RTLD_LOCAL) else {
            throw LibretroError.missingCore(dlerror().map { String(cString: $0) } ?? "not in this build")
        }
        self.handle = handle
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw LibretroError.missingSymbol(name) }
            return unsafeBitCast(pointer, to: type)
        }
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)
        LibretroCore.active = self

        try symbol("retro_set_environment", (@convention(c) (EnvironmentCallback) -> Void).self)(retroEnvironment)
        try symbol("retro_set_video_refresh", (@convention(c) (VideoCallback) -> Void).self)(retroVideo)
        try symbol("retro_set_audio_sample", (@convention(c) (AudioSampleCallback) -> Void).self)(retroAudioSample)
        try symbol("retro_set_audio_sample_batch", (@convention(c) (AudioBatchCallback) -> Void).self)(retroAudioBatch)
        try symbol("retro_set_input_poll", (@convention(c) (InputPollCallback) -> Void).self)(retroInputPoll)
        try symbol("retro_set_input_state", (@convention(c) (InputStateCallback) -> Void).self)(retroInputState)
        run = try symbol("retro_run", (@convention(c) () -> Void).self)
        reset = try symbol("retro_reset", (@convention(c) () -> Void).self)
        unload = try symbol("retro_unload_game", (@convention(c) () -> Void).self)
        deinitCore = try symbol("retro_deinit", (@convention(c) () -> Void).self)
        serializeSize = try? symbol("retro_serialize_size", (@convention(c) () -> Int).self)
        serialize = try? symbol("retro_serialize", (@convention(c) (UnsafeMutableRawPointer?, Int) -> Bool).self)
        unserialize = try? symbol("retro_unserialize", (@convention(c) (UnsafeRawPointer?, Int) -> Bool).self)

        try symbol("retro_init", (@convention(c) () -> Void).self)()
        let loaded = gamePath.withCString { path -> Bool in
            // struct retro_game_info { const char *path; const void *data; size_t size; const char *meta; }
            var info: (UnsafePointer<CChar>?, UnsafeRawPointer?, Int, UnsafePointer<CChar>?) = (path, nil, 0, nil)
            return (try? symbol("retro_load_game", (@convention(c) (UnsafeRawPointer?) -> Bool).self))
                .map { load in withUnsafePointer(to: &info) { load(UnsafeRawPointer($0)) } } ?? false
        }
        guard loaded else { stopCore(); throw LibretroError.gameNotLoaded }

        // struct retro_system_av_info { geometry (4 unsigned, float), timing (double fps, double sample_rate) }
        let avInfo = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { avInfo.deallocate() }
        avInfo.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        try symbol("retro_get_system_av_info", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)(avInfo)
        let reportedFPS = avInfo.load(fromByteOffset: 24, as: Double.self)
        let reportedRate = avInfo.load(fromByteOffset: 32, as: Double.self)
        fps = reportedFPS > 1 ? reportedFPS : 60
        sampleRate = reportedRate > 1000 ? reportedRate : 44_100
        audio.start(sampleRate: sampleRate)

        running = true
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "app.everplay.libretro"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        perform { [weak self] in self?.running = false }
    }

    func setPaused(_ value: Bool) { perform { [weak self] in self?.paused = value } }

    func set(_ button: Button, pressed down: Bool) {
        inputLock.lock()
        if down { pressed |= 1 << UInt32(button.rawValue) } else { pressed &= ~(1 << UInt32(button.rawValue)) }
        inputLock.unlock()
    }

    fileprivate func isPressed(_ id: UInt32) -> Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        return id < 32 && pressed & (1 << id) != 0
    }

    func resetGame() { perform { [weak self] in self?.reset?() } }

    /// Saves the whole game state (quick save); completion on the main thread.
    func saveState(to file: URL, completion: @escaping (Bool) -> Void) {
        perform { [weak self] in
            guard let self, let size = self.serializeSize?(), size > 0, let serialize = self.serialize else {
                DispatchQueue.main.async { completion(false) }; return
            }
            var data = Data(count: size)
            let ok = data.withUnsafeMutableBytes { serialize($0.baseAddress, size) }
            let written = ok && (try? data.write(to: file, options: .atomic)) != nil
            DispatchQueue.main.async { completion(written) }
        }
    }

    func loadState(from file: URL, completion: @escaping (Bool) -> Void) {
        perform { [weak self] in
            guard let self, let unserialize = self.unserialize, let data = try? Data(contentsOf: file) else {
                DispatchQueue.main.async { completion(false) }; return
            }
            let ok = data.withUnsafeBytes { unserialize($0.baseAddress, data.count) }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: - Core thread

    private func perform(_ work: @escaping () -> Void) {
        inputLock.lock(); pendingWork.append(work); inputLock.unlock()
    }

    private func loop() {
        let frame = 1.0 / fps
        var next = CACurrentMediaTime()
        var last = next
        while running && !shutdownRequested {
            inputLock.lock(); let work = pendingWork; pendingWork.removeAll(); inputLock.unlock()
            work.forEach { $0() }
            guard running else { break }
            if paused {
                Thread.sleep(forTimeInterval: 0.05)
                next = CACurrentMediaTime(); last = next
                continue
            }
            let now = CACurrentMediaTime()
            frameTimeCallback?(Int64((now - last) * 1_000_000))
            last = now
            run?()
            audioCallback?()
            next += frame
            let wait = next - CACurrentMediaTime()
            if wait > 0 { Thread.sleep(forTimeInterval: wait) } else if wait < -0.25 { next = CACurrentMediaTime() }
        }
        stopCore()
        DispatchQueue.main.async { [onEnd] in onEnd?(nil) }
    }

    private func stopCore() {
        unload?()
        deinitCore?()
        unload = nil
        deinitCore = nil
        audio.stop()
        // The core keeps global state; it stays loaded for the rest of the app run.
        LibretroCore.active = nil
    }

    // MARK: - Video

    fileprivate func present(_ data: UnsafeRawPointer, width: Int, height: Int, pitch: Int) {
        guard width > 0, height > 0 else { return }
        let image: CGImage?
        switch pixelFormat {
        case 1:  // XRGB8888
            let bytes = Data(bytes: data, count: pitch * height)
            image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pitch,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                            provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        case 2:  // RGB565 has no CoreGraphics layout
            image = Self.convert565(data, width: width, height: height, pitch: pitch)
        default:  // 0RGB1555
            let bytes = Data(bytes: data, count: pitch * height)
            image = CGImage(width: width, height: height, bitsPerComponent: 5, bitsPerPixel: 16, bytesPerRow: pitch,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                            provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard let image else { return }
        DispatchQueue.main.async { [weak self] in self?.onFrame?(image) }
    }

    /// RGB565 has no direct CGImage layout; expand it to 32-bit.
    private static func convert565(_ data: UnsafeRawPointer, width: Int, height: Int, pitch: Int) -> CGImage? {
        var out = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = data.advanced(by: y * pitch).assumingMemoryBound(to: UInt16.self)
            for x in 0..<width {
                let pixel = UInt32(row[x])
                let r = (pixel >> 11) & 0x1F, g = (pixel >> 5) & 0x3F, b = pixel & 0x1F
                out[y * width + x] = 0xFF00_0000 | ((r << 3 | r >> 2) << 16) | ((g << 2 | g >> 4) << 8) | (b << 3 | b >> 2)
            }
        }
        let bytes = out.withUnsafeBytes { Data($0) }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                       provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum LibretroError: LocalizedError {
    case busy, missingCore(String), missingSymbol(String), gameNotLoaded

    var errorDescription: String? {
        switch self {
        case .busy: return "Another game is still running."
        case .missingCore(let reason): return "The RPG Maker 2000/2003 player is not available: \(reason)"
        case .missingSymbol(let name): return "The bundled player is incomplete (\(name))."
        case .gameNotLoaded: return "The game could not be started. Check that the folder contains the whole game (RPG_RT.ldb, RPG_RT.lmt and the map files)."
        }
    }
}

// MARK: - C callbacks

typealias EnvironmentCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool
typealias VideoCallback = @convention(c) (UnsafeRawPointer?, UInt32, UInt32, Int) -> Void
typealias AudioSampleCallback = @convention(c) (Int16, Int16) -> Void
typealias AudioBatchCallback = @convention(c) (UnsafePointer<Int16>?, Int) -> Int
typealias InputPollCallback = @convention(c) () -> Void
typealias InputStateCallback = @convention(c) (UInt32, UInt32, UInt32, UInt32) -> Int16

private let retroEnvironment: EnvironmentCallback = { command, data in
    guard let core = LibretroCore.active else { return false }
    switch command & 0xFFFF {
    case 3:  // GET_CAN_DUPE
        data?.storeBytes(of: true, as: Bool.self); return true
    case 7:  // SHUTDOWN
        core.shutdownRequested = true; return true
    case 9:  // GET_SYSTEM_DIRECTORY
        data?.storeBytes(of: UnsafePointer(core.systemPath), as: UnsafePointer<CChar>.self); return true
    case 10:  // SET_PIXEL_FORMAT
        guard let format = data?.load(as: UInt32.self), format <= 2 else { return false }
        core.pixelFormat = format; return true
    case 21:  // SET_FRAME_TIME_CALLBACK { callback, reference }
        core.frameTimeCallback = data?.load(as: (@convention(c) (Int64) -> Void)?.self); return true
    case 22:  // SET_AUDIO_CALLBACK { callback, set_state }
        core.audioCallback = data?.load(as: (@convention(c) () -> Void)?.self)
        if let setState = data?.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: (@convention(c) (Bool) -> Void)?.self) {
            setState(true)
        }
        return true
    case 31:  // GET_SAVE_DIRECTORY
        data?.storeBytes(of: UnsafePointer(core.savePath), as: UnsafePointer<CChar>.self); return true
    case 32:  // SET_SYSTEM_AV_INFO
        if let rate = data?.load(fromByteOffset: 32, as: Double.self), rate > 1000 { core.sampleRate = rate }
        return true
    case 8, 11, 16, 35, 37:
        return true  // performance level, input descriptors, variables, controller info, geometry
    case 47:  // GET_AUDIO_VIDEO_ENABLE: both
        data?.storeBytes(of: Int32(3), as: Int32.self); return true
    default:
        return false
    }
}

private let retroVideo: VideoCallback = { data, width, height, pitch in
    guard let data else { return }  // a repeated frame
    LibretroCore.active?.present(data, width: Int(width), height: Int(height), pitch: pitch)
}

private let retroAudioSample: AudioSampleCallback = { left, right in
    var frame = [left, right]
    LibretroCore.active?.audio.push(&frame, frames: 1)
}

private let retroAudioBatch: AudioBatchCallback = { data, frames in
    guard let data else { return frames }
    LibretroCore.active?.audio.push(data, frames: frames)
    return frames
}

private let retroInputPoll: InputPollCallback = {}

private let retroInputState: InputStateCallback = { port, device, _, id in
    guard port == 0, device == 1, let core = LibretroCore.active else { return 0 }  // RETRO_DEVICE_JOYPAD
    return core.isPressed(id) ? 1 : 0
}

/// Plays interleaved 16-bit stereo from the core through a ring buffer.
final class LibretroAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let lock = NSLock()
    private var buffer = [Int16](repeating: 0, count: 2 * 48_000)  // one second of stereo
    private var readIndex = 0
    private var writeIndex = 0
    private var available = 0

    func start(sampleRate: Double) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, list -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.lock.lock()
            for frame in 0..<Int(frameCount) {
                if self.available >= 2 {
                    left[frame] = Float(self.buffer[self.readIndex]) / 32_768
                    right[frame] = Float(self.buffer[self.readIndex + 1]) / 32_768
                    self.readIndex = (self.readIndex + 2) % self.buffer.count
                    self.available -= 2
                } else {
                    left[frame] = 0; right[frame] = 0
                }
            }
            self.lock.unlock()
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    func push(_ samples: UnsafePointer<Int16>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        let count = frames * 2
        for index in 0..<count {
            if available == buffer.count {  // full: drop the oldest sample
                readIndex = (readIndex + 1) % buffer.count; available -= 1
            }
            buffer[writeIndex] = samples[index]
            writeIndex = (writeIndex + 1) % buffer.count
            available += 1
        }
    }

    func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
    }
}
