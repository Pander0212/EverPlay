import Foundation
import CShioriKrkr
import EverPlayCore

/// KiriKiri's engine, ShioriKrkr.framework (KiriKit, MPL-2.0: krkr2's core with a Metal
/// compositor), loaded when a game starts. Every call is made on the main thread. One game per
/// process: the engine's globals are not reset, so EverPlay closes when the game ends.
@MainActor
final class KiriKiriEngine {
    typealias Start = @convention(c) (UnsafePointer<shiorikrkr_config_t>?) -> Int32
    typealias Tick = @convention(c) () -> Int32
    typealias Frame = @convention(c) (UnsafeMutablePointer<shiorikrkr_frame_t>?) -> Int32
    typealias Pointer = @convention(c) (Int32, Float, Float, Int32) -> Void
    typealias Wheel = @convention(c) (Float, Float, Float) -> Void
    typealias Key = @convention(c) (Int32, Int32) -> Void
    typealias Eval = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, UInt32) -> Int32
    typealias Stop = @convention(c) () -> Void

    let start: Start, tick: Tick, frame: Frame, pointer: Pointer, wheel: Wheel, key: Key, eval: Eval, stop: Stop

    static var binary: URL? {
        let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("ShioriKrkr.framework/ShioriKrkr")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// The engine's functions, or nil with the reason.
    static func load() -> Result<KiriKiriEngine, KiriKiriError> {
        guard let binary else { return .failure(KiriKiriError("This EverPlay build does not include the KiriKiri engine.")) }
        guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_LOCAL) else {
            return .failure(KiriKiriError("The KiriKiri engine could not be loaded: \(dlerror().map { String(cString: $0) } ?? "?")"))
        }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let start = symbol("shiorikrkr_start", Start.self), let tick = symbol("shiorikrkr_tick", Tick.self),
              let frame = symbol("shiorikrkr_frame", Frame.self), let pointer = symbol("shiorikrkr_pointer", Pointer.self),
              let wheel = symbol("shiorikrkr_wheel", Wheel.self), let key = symbol("shiorikrkr_key", Key.self),
              let eval = symbol("shiorikrkr_eval", Eval.self), let stop = symbol("shiorikrkr_stop", Stop.self) else {
            return .failure(KiriKiriError("The KiriKiri engine is incomplete."))
        }
        return .success(KiriKiriEngine(start: start, tick: tick, frame: frame, pointer: pointer, wheel: wheel,
                                       key: key, eval: eval, stop: stop))
    }

    private init(start: Start, tick: Tick, frame: Frame, pointer: Pointer, wheel: Wheel, key: Key, eval: Eval, stop: Stop) {
        (self.start, self.tick, self.frame, self.pointer, self.wheel, self.key, self.eval, self.stop) =
            (start, tick, frame, pointer, wheel, key, eval, stop)
    }

    /// The engine's log for the last game, shown in EverPlay's diagnostics log at the next start.
    static var logFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/kirikiri.log")
    }
    nonisolated(unsafe) static var log: FileHandle?

    /// Asks the player (System.inform and the game's questions); set by the game screen.
    nonisolated(unsafe) static var ask: ((String, String, [String]) -> Int32)?

    /// Starts the game in `gameRoot` (the folder with data.xp3 or startup.tjs).
    func run(gameRoot: URL, saves: URL, scheme: URL?) throws {
        try KiriKiriGame.linkSaves(gameRoot: gameRoot, saveFolder: saves)
        try? FileManager.default.createDirectory(at: Self.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logFile.path, contents: nil)
        Self.log = try? FileHandle(forWritingTo: Self.logFile)
        var arguments: [String] = []
        if let font = Bundle.main.url(forResource: "BIZUDGothic-Regular", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "BIZUDGothic-Regular", withExtension: "ttf", subdirectory: "Fonts") {
            arguments.append("-default_font=\(font.path)")
        }
        let exe = KiriKiriGame.executableName(in: gameRoot)
        let copies = arguments.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
        let schemePath: UnsafeMutablePointer<CChar>? = scheme.flatMap { strdup($0.path) }
        defer { free(schemePath) }
        let status = gameRoot.path.withCString { root in
            exe.withCString { exeName in
                pointers.withUnsafeMutableBufferPointer { list in
                    var config = shiorikrkr_config_t()
                    config.struct_size = UInt32(MemoryLayout<shiorikrkr_config_t>.size)
                    config.game_root = root
                    config.exe_name = exeName
                    config.cx_scheme_path = UnsafePointer(schemePath)
                    config.arguments = UnsafePointer(list.baseAddress)
                    config.argument_count = UInt32(list.count)
                    config.log = { _, line in
                        guard let line else { return }
                        KiriKiriEngine.log?.write(Data((String(cString: line) + "\n").utf8))
                    }
                    config.message = { _, text, caption, buttons, count in
                        let names = (0 ..< Int(count)).map { buttons?[$0].map { String(cString: $0) } ?? "OK" }
                        let message = text.map { String(cString: $0) } ?? ""
                        let title = caption.map { String(cString: $0) } ?? ""
                        return KiriKiriEngine.ask?(message, title, names.isEmpty ? ["OK"] : names) ?? 0
                    }
                    config.host_presents = 1
                    return start(&config)
                }
            }
        }
        guard status == Int32(SHIORIKRKR_OK) else {
            let detail = switch Int(status) {
            case Int(SHIORIKRKR_ERROR_START) where scheme != nil:
                "The game did not start. The key chosen from GARbro's list may belong to another game."
            case Int(SHIORIKRKR_ERROR_START):
                "The game did not start. Its archives may be encrypted with a key EverPlay does not know."
            case Int(SHIORIKRKR_ERROR_SCHEME):
                "The game's key could not be read. Choose it again."
            default:
                "The KiriKiri engine refused to start (\(status))."
            }
            throw KiriKiriError(detail)
        }
    }

    /// Runs TJS in the game (between ticks) and returns its result as text.
    func evaluate(_ tjs: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 2048)
        guard eval(tjs, &buffer, UInt32(buffer.count)) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Adds the last game's engine log to the diagnostics log (at app start).
    static func collectPreviousLog() {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8), !text.isEmpty else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60)
        EverPlayLog.write("KiriKiri engine output of the last game:\n" + lines.joined(separator: "\n"))
        try? FileManager.default.removeItem(at: logFile)
    }
}

struct KiriKiriError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
