import Foundation
import UIKit
import EverPlayCore

/// Godot 4's engine, Godot<NN>.framework (official sources, MIT, built by godot-ios.yml with
/// scripts/godot/everplay_godot.mm as its entry), loaded when a game starts. Every call is made on
/// the main thread. One game per process: Godot's globals are not reset, so EverPlay closes when
/// the game ends.
@MainActor
final class GodotEngine {
    typealias Quit = @convention(c) (Int32) -> Void
    typealias Start = @convention(c) (Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>?, UnsafePointer<CChar>?, Quit?) -> Int32
    typealias ViewController = @convention(c) () -> UnsafeMutableRawPointer?
    typealias AppState = @convention(c) (Int32) -> Void
    typealias Notify = @convention(c) () -> Void
    typealias MouseButton = @convention(c) (Int32, Int32, Float, Float) -> Void
    typealias Key = @convention(c) (Int32, Int32, Int32) -> Void

    let start: Start, viewController: ViewController, appState: AppState, memoryWarning: Notify
    let mouseButton: MouseButton, key: Key

    /// Godot's key codes for the keys EverPlay sends (core/os/keyboard.h).
    enum Keys {
        static let special: Int32 = 1 << 22
        static let escape = special | 0x01, tab = special | 0x02, backspace = special | 0x04, enter = special | 0x05
        static let left = special | 0x0F, up = special | 0x10, right = special | 0x11, down = special | 0x12
        static let space: Int32 = 0x20
    }

    static func binary(_ framework: String) -> URL? {
        let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("\(framework).framework/\(framework)")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// The engine's functions, or nil with the reason.
    static func load(_ framework: String) -> Result<GodotEngine, GodotError> {
        guard let binary = binary(framework) else {
            return .failure(GodotError("This EverPlay build does not include the Godot engine (\(framework))."))
        }
        guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_LOCAL) else {
            return .failure(GodotError("The Godot engine could not be loaded: \(dlerror().map { String(cString: $0) } ?? "?")"))
        }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let start = symbol("everplay_godot_start", Start.self),
              let viewController = symbol("everplay_godot_view_controller", ViewController.self),
              let appState = symbol("everplay_godot_app_state", AppState.self),
              let memoryWarning = symbol("everplay_godot_memory_warning", Notify.self),
              let mouseButton = symbol("everplay_godot_mouse_button", MouseButton.self),
              let key = symbol("everplay_godot_key", Key.self) else {
            return .failure(GodotError("The Godot engine is incomplete."))
        }
        return .success(GodotEngine(start: start, viewController: viewController, appState: appState,
                                    memoryWarning: memoryWarning, mouseButton: mouseButton, key: key))
    }

    private init(start: Start, viewController: ViewController, appState: AppState, memoryWarning: Notify,
                 mouseButton: MouseButton, key: Key) {
        (self.start, self.viewController, self.appState, self.memoryWarning, self.mouseButton, self.key) =
            (start, viewController, appState, memoryWarning, mouseButton, key)
    }

    /// Godot's log for the last game (its --log-file), shown in EverPlay's diagnostics log at the next start.
    static var logFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/godot.log")
    }

    /// Sets Godot up for the game in `pack` (a .pck, or an .exe with its pack embedded) with saves
    /// (user://) in `saves`, and returns the view controller that plays it once it is on screen.
    func run(pack: URL, saves: URL, quit: Quit) throws -> UIViewController {
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Self.logFile)
        let program = Bundle.main.bundleURL.appendingPathComponent("godot").path
        let arguments = [program, "--main-pack", pack.path, "--log-file", Self.logFile.path]
        let copies = arguments.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
        let status = saves.path.withCString { savePath in
            pointers.withUnsafeMutableBufferPointer { list in
                start(Int32(arguments.count), list.baseAddress, savePath, quit)
            }
        }
        guard status == 0 else {
            throw GodotError("Godot could not open the game (\(status)). \(Self.lastLines(4))")
        }
        guard let raw = viewController() else { throw GodotError("Godot did not create its game view.") }
        return Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
    }

    /// The end of Godot's log, for error messages.
    static func lastLines(_ count: Int) -> String {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }

    /// Adds the last game's engine log to the diagnostics log (at app start).
    static func collectPreviousLog() {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8), !text.isEmpty else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60)
        EverPlayLog.write("Godot engine output of the last game:\n" + lines.joined(separator: "\n"))
        try? FileManager.default.removeItem(at: logFile)
    }
}

struct GodotError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
