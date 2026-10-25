import Foundation
import ZIPFoundation

/// What EverPlay prepares before a KiriKiri game starts: its saves visible in Files, and the
/// name of its PC executable, which KiriKiri games read (System.exeName) but never run.
public enum KiriKiriGame {
    /// KiriKiri writes saves to `savedata/` in the game's folder. It becomes a link to the
    /// visible Saves folder; saves already in the game (from the ZIP or an earlier start) move there.
    public static func linkSaves(gameRoot: URL, saveFolder: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let link = gameRoot.appendingPathComponent("savedata")
        let values = try? link.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true {
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == saveFolder.path { return }
            try fileManager.removeItem(at: link)
        } else if values?.isDirectory == true {
            for name in try fileManager.contentsOfDirectory(atPath: link.path) {
                let target = saveFolder.appendingPathComponent(name)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.moveItem(at: link.appendingPathComponent(name), to: target)
                }
            }
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: saveFolder)
    }

    /// The game's own executable (not an installer, uninstaller or config tool); "game.exe" if none.
    public static func executableName(in gameRoot: URL) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: gameRoot.path)) ?? []).sorted()
        return names.first { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".exe") && !["unins", "setup", "config", "steam", "crash"].contains(where: lower.contains)
        } ?? "game.exe"
    }
}

/// Whether a KiriKiri game's archives can be read without a key. KiriKiri's XP3 archives keep
/// an index (zlib or stored) of files, each with segments of plain or zlib data; CxDec titles
/// encrypt the files' contents (the index stays readable) and KiriKiri Z's Hx titles also hide
/// the index behind hashes. EverPlay looks at the game's startup script in data.xp3.
public enum KiriKiriArchiveState: Equatable, Sendable {
    case plain, encrypted, unknown
}

extension KiriKiriGame {
    public static func archiveState(gameRoot: URL) -> KiriKiriArchiveState {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: gameRoot.appendingPathComponent("startup.tjs").path) { return .plain }
        let names = (try? fileManager.contentsOfDirectory(atPath: gameRoot.path)) ?? []
        guard let archive = names.first(where: { $0.lowercased() == "data.xp3" }) else { return .unknown }
        return XP3Archive.startupState(gameRoot.appendingPathComponent(archive))
    }
}

enum XP3Archive {
    static let magic: [UInt8] = [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x20, 0x0A, 0x1A, 0x8B, 0x67, 0x01]

    struct Entry {
        var name: String
        var segments: [(compressed: Bool, offset: UInt64, size: UInt64, packed: UInt64)]
    }

    static func startupState(_ archive: URL) -> KiriKiriArchiveState {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return .unknown }
        defer { try? handle.close() }
        guard let index = try? index(handle) else { return .encrypted }
        // An Hx title's index names no files.
        guard let startup = entries(in: index).first(where: { $0.name.lowercased() == "startup.tjs" }),
              let segment = startup.segments.first, segment.size > 0 else { return .encrypted }
        guard let packed = try? read(handle, Int(min(segment.packed, 1 << 20)), at: segment.offset) else { return .unknown }
        let head: Data
        if segment.compressed {
            guard let inflated = try? inflate(packed, limit: 4096) else { return .encrypted }
            head = inflated
        } else {
            head = packed.prefix(4096)
        }
        return looksLikeScript(head) ? .plain : .encrypted
    }

    static func read(_ handle: FileHandle, _ count: Int, at offset: UInt64) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else { throw EverPlayError.invalidArchive }
        return data
    }

    static func integer(_ data: Data, _ at: Int, _ size: Int) -> UInt64? {
        guard at >= 0, at + size <= data.count else { return nil }
        let start = data.startIndex + at
        return (0 ..< size).reduce(UInt64(0)) { $0 | UInt64(data[start + $1]) << (8 * UInt64($1)) }
    }

    /// The archive's (last) index.
    static func index(_ handle: FileHandle) throws -> Data {
        let header = try read(handle, 19, at: 0)
        guard Array(header.prefix(11)) == magic, var offset = integer(header, 11, 8) else { throw EverPlayError.invalidArchive }
        if offset == 0x17 {
            // KiriKiri 2.3's cushion: a continued index header pointing at the real one.
            let cushion = try read(handle, 17, at: 0x17)
            guard let real = integer(cushion, 9, 8) else { throw EverPlayError.invalidArchive }
            offset = real
        }
        while true {
            let flags = try read(handle, 1, at: offset)[0]
            let index: Data
            if flags & 0x07 == 1 {
                let sizes = try read(handle, 16, at: offset + 1)
                guard let packed = integer(sizes, 0, 8), let size = integer(sizes, 8, 8),
                      packed < 64 << 20, size < 256 << 20 else { throw EverPlayError.invalidArchive }
                index = try inflate(read(handle, Int(packed), at: offset + 17), limit: Int(size))
                offset += 17 + packed
            } else if flags & 0x07 == 0 {
                guard let size = integer(try read(handle, 8, at: offset + 1), 0, 8), size < 256 << 20 else {
                    throw EverPlayError.invalidArchive
                }
                index = try read(handle, Int(size), at: offset + 9)
                offset += 9 + size
            } else {
                throw EverPlayError.invalidArchive
            }
            if flags & 0x80 == 0 { return index }
        }
    }

    /// The index's "File" chunks with their "info" names and "segm" segments.
    static func entries(in index: Data) -> [Entry] {
        var entries: [Entry] = []
        for (name, body) in chunks(index) where name == "File" {
            var entry = Entry(name: "", segments: [])
            for (part, data) in chunks(body) {
                if part == "info", let length = integer(data, 20, 2), 22 + Int(length) * 2 <= data.count {
                    let units = (0 ..< Int(length)).compactMap { integer(data, 22 + $0 * 2, 2).map(UInt16.init) }
                    entry.name = String(decoding: units, as: UTF16.self)
                } else if part == "segm" {
                    for at in stride(from: 0, to: data.count - 27, by: 28) {
                        guard let flags = integer(data, at, 4), let offset = integer(data, at + 4, 8),
                              let size = integer(data, at + 12, 8), let packed = integer(data, at + 20, 8) else { break }
                        entry.segments.append((flags & 7 == 1, offset, size, packed))
                    }
                }
            }
            entries.append(entry)
        }
        return entries
    }

    static func chunks(_ data: Data) -> [(String, Data)] {
        var out: [(String, Data)] = []
        var at = 0
        while at + 12 <= data.count, let size = integer(data, at + 4, 8), UInt64(at + 12) + size <= UInt64(data.count) {
            let start = data.startIndex + at
            out.append((String(decoding: data[start ..< start + 4], as: UTF8.self), data[start + 12 ..< start + 12 + Int(size)]))
            at += 12 + Int(size)
        }
        return out
    }

    /// TJS source: UTF-16 or UTF-8 with a byte order mark, or text without control bytes.
    static func looksLikeScript(_ head: Data) -> Bool {
        let bytes = [UInt8](head)
        guard !bytes.isEmpty else { return false }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return true }
        let control = bytes.filter { $0 < 0x20 && ![0x09, 0x0A, 0x0D].contains($0) }.count
        return control * 50 <= bytes.count
    }

    /// A zlib stream (2-byte header, deflate, Adler-32), up to `limit` bytes of output.
    static func inflate(_ zlib: Data, limit: Int) throws -> Data {
        guard zlib.count > 2 else { throw EverPlayError.invalidArchive }
        let deflate = zlib.dropFirst(2)
        var out = Data()
        struct Enough: Error {}
        do {
            _ = try Data.decompress(size: Int64(deflate.count), bufferSize: 64 * 1024, skipCRC32: true,
                                    provider: { position, size in
                                        let start = deflate.startIndex + Int(position)
                                        return deflate[start ..< min(start + size, deflate.endIndex)]
                                    },
                                    consumer: { chunk in
                                        out.append(chunk)
                                        if out.count >= limit { throw Enough() }
                                    })
        } catch is Enough {}
        guard !out.isEmpty else { throw EverPlayError.invalidArchive }
        return out.prefix(limit)
    }
}
