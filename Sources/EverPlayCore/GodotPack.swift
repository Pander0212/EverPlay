import Foundation

/// A Godot pack's header: a standalone .pck, or one appended to the game's .exe (Godot's
/// "embed pck" export, which ends the file with the pack's size and "GDPC"). Only the header is
/// read; nothing of the game is run.
public struct GodotPack: Equatable, Sendable {
    public let formatVersion: UInt32
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32
    /// The pack's file list is encrypted with a key compiled into the game's .exe.
    public let encryptedDirectory: Bool
    /// Where the pack starts in the file (0 for a standalone .pck).
    public let offset: UInt64

    public var version: String { "\(major).\(minor).\(patch)" }

    static let magic: UInt32 = 0x4350_4447  // "GDPC"
    static let directoryEncrypted: UInt32 = 1

    /// The pack in `url`, or nil when the file holds none.
    public static func read(_ url: URL) -> GodotPack? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 24 else { return nil }
        if let head = try? read(handle, 4, at: 0), le32(head, 0) == magic {
            return header(handle, at: 0)
        }
        // Embedded: ... pack ... | pack size (UInt64) | "GDPC"
        guard let tail = try? read(handle, 12, at: size - 12), le32(tail, 8) == magic else { return nil }
        let length = le64(tail, 0)
        guard length > 0, length <= size - 12 else { return nil }
        let start = size - 12 - length
        guard let head = try? read(handle, 4, at: start), le32(head, 0) == magic else { return nil }
        return header(handle, at: start)
    }

    private static func header(_ handle: FileHandle, at offset: UInt64) -> GodotPack? {
        guard let data = try? read(handle, 24, at: offset), data.count == 24 else { return nil }
        let format = le32(data, 4)
        // Godot 3 packs (format 1) have no flags.
        let flags = format >= 2 ? le32(data, 20) : 0
        return GodotPack(formatVersion: format, major: le32(data, 8), minor: le32(data, 12), patch: le32(data, 16),
                         encryptedDirectory: flags & directoryEncrypted != 0, offset: offset)
    }

    private static func read(_ handle: FileHandle, _ count: Int, at offset: UInt64) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func le32(_ data: Data, _ at: Int) -> UInt32 {
        data.subdata(in: data.startIndex + at ..< data.startIndex + at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private static func le64(_ data: Data, _ at: Int) -> UInt64 {
        data.subdata(in: data.startIndex + at ..< data.startIndex + at + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
    }
}

/// The Godot runtimes inside EverPlay and which one plays a pack.
public enum GodotRuntime {
    /// Major.minor of each bundled Godot framework (Godot<major><minor>.framework).
    public static let bundled: [(major: UInt32, minor: UInt32)] = [(4, 4), (4, 7)]

    /// The framework name for a pack: the oldest bundled 4.x runtime at least as new as the game. Godot 4
    /// reads packs of older 4.x versions, but compiled scripts (.gdc) only of its own format: 4.4 writes
    /// format 100, 4.5–4.7 write 101, so a 4.4 game needs the 4.4 runtime. Throws `recognizedEngine` saying why
    /// none fits.
    public static func framework(for pack: GodotPack) throws -> String {
        if pack.encryptedDirectory {
            throw report(pack, "Its files are encrypted with a key built into its .exe; EverPlay cannot open it yet.")
        }
        guard pack.major == 4 else {
            throw report(pack, "EverPlay plays Godot 4 games so far.")
        }
        guard let runtime = bundled.filter({ $0.major == pack.major && $0.minor >= pack.minor }).min(by: { $0.minor < $1.minor }) else {
            throw report(pack, "It needs a newer Godot than the one inside EverPlay.")
        }
        return "Godot\(runtime.major)\(runtime.minor)"
    }

    private static func report(_ pack: GodotPack, _ outlook: String) -> EverPlayError {
        .recognizedEngine(EngineReport(engine: "Godot \(pack.version)", playable: false, outlook: outlook, evidence: []))
    }
}
