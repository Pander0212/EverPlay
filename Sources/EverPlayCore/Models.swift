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
    public init() {}
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
        case .missingEntryPoint: return "No index.html was found in this game."
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
