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
    typealias Variables = @convention(c) (UnsafeMutablePointer<CChar>?, Int32) -> Int32
    typealias SetVariable = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias SetSpeed = @convention(c) (Double) -> Void

    let start: Start, viewController: ViewController, appState: AppState, memoryWarning: Notify
    let mouseButton: MouseButton, key: Key
    /// Cheats (frameworks built before them lack these).
    private(set) var variables: Variables?, setVariable: SetVariable?, setSpeed: SetSpeed?

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
        let engine = GodotEngine(start: start, viewController: viewController, appState: appState,
                                 memoryWarning: memoryWarning, mouseButton: mouseButton, key: key)
        engine.variables = symbol("everplay_godot_variables", Variables.self)
        engine.setVariable = symbol("everplay_godot_set_variable", SetVariable.self)
        engine.setSpeed = symbol("everplay_godot_set_speed", SetSpeed.self)
        return .success(engine)
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
        // OS.get_executable_path(): games that save next to their .exe save into their Saves folder.
        let executable = pack.pathExtension.lowercased() == "exe" ? pack.lastPathComponent
            : pack.deletingPathExtension().lastPathComponent + ".exe"
        setenv("EVERPLAY_GODOT_EXECUTABLE", saves.appendingPathComponent(executable).path, 1)
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

    /// The game's variables: script variables of its global scripts (autoloads) and current scene.
    func gameVariables() -> [GodotVariable] {
        guard let variables else { return [] }
        let size = variables(nil, 0)
        guard size > 1 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(size))
        _ = variables(&buffer, size)
        let data = Data(buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) })
        return (try? JSONDecoder().decode([GodotVariable].self, from: data)) ?? []
    }

    /// Sets a variable to `text`, read as its current type. False when the game no longer has it.
    func set(_ variable: GodotVariable, to text: String) -> Bool {
        setVariable?(variable.node, variable.path, text) == 1
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

/// A variable of the running game, as everplay_godot_variables lists it.
struct GodotVariable: Decodable, Identifiable, Hashable {
    let node: String
    let path: String
    let type: String
    let value: Value
    var id: String { node + "|" + path }
    /// "GameState.money": the global script's name and the variable.
    var name: String { (node.split(separator: "/").last.map(String.init) ?? node) + "." + path }

    enum Value: Decodable, Hashable {
        case flag(Bool), number(Double), text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) { self = .flag(flag) }
            else if let number = try? container.decode(Double.self) { self = .number(number) }
            else { self = .text((try? container.decode(String.self)) ?? "") }
        }

        var text: String {
            switch self {
            case .flag(let flag): return flag ? "true" : "false"
            case .number(let number):
                return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
            case .text(let text): return text
            }
        }
    }
}

struct GodotError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
