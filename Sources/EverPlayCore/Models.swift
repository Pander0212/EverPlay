import Foundation

public enum GameEngine: String, Codable, Sendable, CaseIterable {
    case html5, rpgMakerMV, rpgMakerMZ

    public var title: String {
        switch self {
        case .html5: return "HTML5"
        case .rpgMakerMV: return "RPG Maker MV"
        case .rpgMakerMZ: return "RPG Maker MZ"
        }
    }

    public var compatibility: String {
        self == .html5 ? "Web player" : "Experimental · web exports only"
    }
}

public struct EngineCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let touch = Self(rawValue: 1 << 0)
    public static let keyboard = Self(rawValue: 1 << 1)
    public static let browserStorage = Self(rawValue: 1 << 2)
}

public struct GameValidationResult: Equatable, Sendable {
    public let engine: GameEngine
    public let entryPoint: String
    public let warnings: [String]
}

/// The core validates packages; platform adapters own presentation and lifecycle.
public protocol GameEngineAdapter: Sendable {
    var engineIdentifier: GameEngine { get }
    var capabilities: EngineCapabilities { get }
    func validateGame(at root: URL) throws -> GameValidationResult
}

public struct GameRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let engine: GameEngine
    public let entryPoint: String
    public let fingerprint: String
    public let importedAt: Date
    /// Stable origin: changing this port would disconnect the game's browser saves.
    public let port: UInt16
    public let resourceToken: String
    public var playSeconds: Double
    public var lastPlayedAt: Date?
    public var controls: ControlSettings
}

public struct ControlSettings: Codable, Equatable, Sendable {
    public var visible = false
    public var opacity = 0.65
    public var leftX = 0.18
    public var leftY = 0.74
    public var rightX = 0.82
    public var rightY = 0.74
    /// The edited layout; nil until the player changes it (older saves have none).
    public var buttons: [ControlButton]?
    public init() {}

    /// The buttons to show: the edited layout, else the default one built around the D-pad position.
    public var layout: [ControlButton] {
        buttons ?? ControlButton.defaultLayout(dpadX: leftX, dpadY: leftY)
    }
}

/// One on-screen control: the D-pad or a key. Positions are the centre, relative to the game view.
public struct ControlButton: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case dpad, key }
    public var id: UUID
    public var kind: Kind
    /// A key from ControlKey.catalog (KeyboardEvent.key); unused for the D-pad.
    public var key: String
    public var label: String
    public var x: Double
    public var y: Double
    public var scale: Double
    /// Tap to hold down, tap again to release (dash, run, auto-skip).
    public var toggles: Bool

    public init(id: UUID = UUID(), kind: Kind = .key, key: String, label: String, x: Double, y: Double,
                scale: Double = 1, toggles: Bool = false) {
        self.id = id; self.kind = kind; self.key = key; self.label = label
        self.x = x; self.y = y; self.scale = scale; self.toggles = toggles
    }

    /// Fixed identities, so the default layout is the same set of controls every time it is built.
    public static func defaultLayout(dpadX: Double = 0.18, dpadY: Double = 0.74) -> [ControlButton] {
        func id(_ number: Int) -> UUID { UUID(uuidString: "E7E7E7E7-0000-4000-8000-00000000000\(number)")! }
        return [ControlButton(id: id(1), kind: .dpad, key: "", label: "D-pad", x: dpadX, y: dpadY),
                ControlButton(id: id(2), key: "z", label: "A", x: 0.88, y: 0.70),
                ControlButton(id: id(3), key: "x", label: "B", x: 0.73, y: 0.76),
                ControlButton(id: id(4), key: "Enter", label: "↵", x: 0.88, y: 0.84),
                ControlButton(id: id(5), key: "Escape", label: "Esc", x: 0.73, y: 0.90)]
    }
}

/// Keys the virtual controls may send: KeyboardEvent key, code and the legacy keyCode RPG Maker reads.
public struct ControlKey: Equatable, Sendable {
    public let key: String
    public let code: String
    public let keyCode: Int
    public let label: String

    public static let catalog: [ControlKey] = {
        var keys = [
            ControlKey(key: "ArrowUp", code: "ArrowUp", keyCode: 38, label: "↑"),
            ControlKey(key: "ArrowDown", code: "ArrowDown", keyCode: 40, label: "↓"),
            ControlKey(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37, label: "←"),
            ControlKey(key: "ArrowRight", code: "ArrowRight", keyCode: 39, label: "→"),
            ControlKey(key: "Enter", code: "Enter", keyCode: 13, label: "↵"),
            ControlKey(key: "Escape", code: "Escape", keyCode: 27, label: "Esc"),
            ControlKey(key: " ", code: "Space", keyCode: 32, label: "Space"),
            ControlKey(key: "Shift", code: "ShiftLeft", keyCode: 16, label: "Shift"),
            ControlKey(key: "Control", code: "ControlLeft", keyCode: 17, label: "Ctrl"),
            ControlKey(key: "Tab", code: "Tab", keyCode: 9, label: "Tab"),
            ControlKey(key: "PageUp", code: "PageUp", keyCode: 33, label: "PgUp"),
            ControlKey(key: "PageDown", code: "PageDown", keyCode: 34, label: "PgDn"),
            ControlKey(key: "Backspace", code: "Backspace", keyCode: 8, label: "⌫"),
        ]
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let letter = String(UnicodeScalar(scalar)!)
            keys.append(ControlKey(key: letter, code: "Key" + letter.uppercased(), keyCode: Int(scalar) - 32, label: letter.uppercased()))
        }
        for digit in 0...9 {
            keys.append(ControlKey(key: String(digit), code: "Digit\(digit)", keyCode: 48 + digit, label: String(digit)))
        }
        for number in 1...12 {
            keys.append(ControlKey(key: "F\(number)", code: "F\(number)", keyCode: 111 + number, label: "F\(number)"))
        }
        return keys
    }()

    public static func named(_ key: String) -> ControlKey? { catalog.first { $0.key == key } }
}

public enum EverPlayError: Error, LocalizedError, Equatable {
    case unsafePath(String), invalidArchive, unsupportedEntry(String), limitExceeded(String)
    case missingEntryPoint, ambiguousEntryPoints, incompleteEngine(String), unsupportedGame
    case duplicateGame, invalidLibrary, unsupportedSchema(Int), noAvailablePort
    case resourceNotFound, invalidRequest, invalidRange

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path): return "Unsafe package path: \(path)"
        case .invalidArchive: return "The ZIP is damaged, encrypted, or not a supported ZIP archive."
        case .unsupportedEntry(let path): return "Links and special files are not supported: \(path)"
        case .limitExceeded(let reason): return "Import limit exceeded: \(reason)"
        case .missingEntryPoint: return "No game page (index.html or another .html file) was found in this game."
        case .ambiguousEntryPoints: return "Several game entry points were found. Import a ZIP containing one game."
        case .incompleteEngine(let engine): return "The \(engine) export is missing data/System.json."
        case .unsupportedGame: return "This game requires an engine that EverPlay does not support yet."
        case .duplicateGame: return "This exact game package is already in your library."
        case .invalidLibrary: return "The library metadata is invalid. Existing game files have been preserved."
        case .unsupportedSchema(let version): return "Library version \(version) requires a newer EverPlay."
        case .noAvailablePort: return "No game storage origins are available."
        case .resourceNotFound: return "Game resource not found."
        case .invalidRequest: return "Invalid resource request."
        case .invalidRange: return "Invalid resource byte range."
        }
    }
}
