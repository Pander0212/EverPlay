import Foundation
import ZIPFoundation
import Crypto

public struct ImportLimits: Sendable {
    // Real desktop games are large: Twine/HTML games ship tens of thousands of images, Ren'Py
    // games several gigabytes. The compression-ratio check below still stops ZIP bombs.
    public var maximumEntries = 250_000
    public var maximumArchiveBytes: UInt64 = 8 * 1_073_741_824
    public var maximumFileBytes: UInt64 = 4 * 1_073_741_824
    public var maximumExpandedBytes: UInt64 = 16 * 1_073_741_824
    public var maximumCompressionRatio: UInt64 = 500
    public init() {}
}

public struct PreparedGame: Sendable {
    public let directory: URL
    public let validation: GameValidationResult
    public let fingerprint: String
}

/// How far the running extraction is, for the import indicator (one import runs at a time).
public final class ImportProgress: @unchecked Sendable {
    public static let shared = ImportProgress()
    private let lock = NSLock()
    private var done: UInt64 = 0
    private var total: UInt64 = 0

    /// 0...1 while files are extracted, nil otherwise.
    public var fraction: Double? {
        lock.lock(); defer { lock.unlock() }
        return total > 0 ? min(1, Double(done) / Double(total)) : nil
    }

    func start(total: UInt64) { lock.lock(); done = 0; self.total = total; lock.unlock() }
    func advance(by bytes: UInt64) { lock.lock(); done += bytes; lock.unlock() }
    func finish() { lock.lock(); done = 0; total = 0; lock.unlock() }
}

public struct GameImporter: Sendable {
    public var limits: ImportLimits
    public init(limits: ImportLimits = .init()) { self.limits = limits }

    /// Caller owns a private staging parent. No application state is changed until validation succeeds.
    public func prepare(zip: URL, stagingParent: URL) throws -> PreparedGame {
        let staging = stagingParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try Self.rejectUnplayableEngine(zip)
        do {
            var entries = try extractArchive(zip: zip, into: staging)
            // NW.js desktop builds (TyranoBuilder, many DLsite HTML games) keep the game in a
            // package.nw ZIP next to Game.exe; it passes the same checks as the outer archive.
            let name = { (path: String) in (path as NSString).lastPathComponent.lowercased() }
            if !entries.contains(where: { name($0.path) == "index.html" }),
               let packed = entries.first(where: { name($0.path) == "package.nw" }) {
                let packedURL = staging.appendingPathComponent(packed.path)
                let parent = (packed.path as NSString).deletingLastPathComponent
                let folder = (parent.isEmpty ? "" : parent + "/") + "package_nw"
                guard !FileManager.default.fileExists(atPath: staging.appendingPathComponent(folder).path) else {
                    throw EverPlayError.unsafePath(folder)
                }
                let unpacked = try extractArchive(zip: packedURL, into: staging.appendingPathComponent(folder, isDirectory: true))
                try FileManager.default.removeItem(at: packedURL)
                entries = entries.filter { $0.path != packed.path } + unpacked.map { (path: folder + "/" + $0.path, size: $0.size) }
            }
            // Electron desktop builds (TyranoScript 5 and others) keep it in resources/app.asar.
            if !entries.contains(where: { name($0.path) == "index.html" }),
               let packed = entries.first(where: { name($0.path) == "app.asar" }) {
                let packedURL = staging.appendingPathComponent(packed.path)
                let parent = (packed.path as NSString).deletingLastPathComponent
                let folder = (parent.isEmpty ? "" : parent + "/") + "app_asar"
                guard !FileManager.default.fileExists(atPath: staging.appendingPathComponent(folder).path) else {
                    throw EverPlayError.unsafePath(folder)
                }
                let unpacked = try AsarArchive.extract(packedURL, into: staging.appendingPathComponent(folder, isDirectory: true),
                                                       limits: limits)
                try FileManager.default.removeItem(at: packedURL)
                entries = entries.filter { $0.path != packed.path } + unpacked.map { (path: folder + "/" + $0.path, size: $0.size) }
            }
            let validation = try GameDetector.detect(at: staging)
            // Hash extracted files and their paths, not ZIP metadata. Repacked duplicates are rejected too.
            var hash = SHA256()
            for (path, size) in entries.sorted(by: { $0.path < $1.path }) {
                let descriptor = Data("\(path.utf8.count):\(path):\(size):".utf8)
                hash.update(data: descriptor)
                let file = try FileHandle(forReadingFrom: staging.appendingPathComponent(path))
                defer { try? file.close() }
                while let data = try file.read(upToCount: 65_536), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
            }
            return PreparedGame(directory: staging, validation: validation,
                                fingerprint: hash.finalize().map { String(format: "%02x", $0) }.joined())
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Safely extracts an archive (no symlinks, no escaping or colliding paths, size and ratio
    /// limits, CRC-checked) into a new directory. Returns the extracted files and their sizes.
    @discardableResult
    public func extractArchive(zip: URL, into staging: URL) throws -> [(path: String, size: UInt64)] {
        let attributes = try FileManager.default.attributesOfItem(atPath: zip.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw EverPlayError.unsupportedEntry(zip.lastPathComponent)
        }
        let size = attributes[.size] as? NSNumber
        guard let size, size.uint64Value <= limits.maximumArchiveBytes else {
            throw EverPlayError.limitExceeded("archive size")
        }
        let archive: Archive
        do { archive = try Archive(url: zip, accessMode: .read) }
        catch { throw EverPlayError.invalidArchive }
        var entries: [(Entry, String)] = []
        var seen: Set<String> = []
        var filePaths: Set<String> = []
        var total: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            guard entries.count < limits.maximumEntries else { throw EverPlayError.limitExceeded("file count") }
            let name = Self.decodedPath(of: entry)
            guard entry.type != .symlink else { throw EverPlayError.unsupportedEntry(name) }
            let components = try SafePath.components(name, directory: entry.type == .directory)
            let path = components.joined(separator: "/")
            let canonical = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(canonical).inserted else { throw EverPlayError.unsafePath("duplicate: \(path)") }
            if entry.type == .file { filePaths.insert(canonical) }
            guard entry.uncompressedSize <= limits.maximumFileBytes,
                  entry.uncompressedSize <= limits.maximumExpandedBytes - min(total, limits.maximumExpandedBytes) else {
                throw EverPlayError.limitExceeded("expanded size")
            }
            if entry.uncompressedSize > 1_048_576 && entry.uncompressedSize / max(entry.compressedSize, 1) > limits.maximumCompressionRatio {
                throw EverPlayError.limitExceeded("compression ratio")
            }
            total += entry.uncompressedSize
            entries.append((entry, path))
        }
        guard !entries.isEmpty else { throw EverPlayError.invalidArchive }
        for (_, path) in entries {
            let parts = path.precomposedStringWithCanonicalMapping.lowercased().split(separator: "/")
            for length in 1..<parts.count where filePaths.contains(parts.prefix(length).joined(separator: "/")) {
                throw EverPlayError.unsafePath(path)
            }
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        ImportProgress.shared.start(total: total)
        defer { ImportProgress.shared.finish() }
        var files: [(path: String, size: UInt64)] = []
        var actualTotal: UInt64 = 0
        for (entry, path) in entries {
            try Task.checkCancellation()
            let target = try SafePath.destination(path, in: staging)
            if entry.type == .directory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw EverPlayError.invalidArchive }
            let file = try FileHandle(forWritingTo: target)
            defer { try? file.close() }
            var actual: UInt64 = 0
            let checksum = try archive.extract(entry, bufferSize: 65_536, skipCRC32: false) { data in
                try Task.checkCancellation()
                actual += UInt64(data.count)
                actualTotal += UInt64(data.count)
                guard actual <= entry.uncompressedSize, actual <= limits.maximumFileBytes,
                      actualTotal <= limits.maximumExpandedBytes else { throw EverPlayError.limitExceeded("decompressed bytes") }
                try file.write(contentsOf: data)
                ImportProgress.shared.advance(by: UInt64(data.count))
            }
            guard actual == entry.uncompressedSize, checksum == entry.checksum else { throw EverPlayError.invalidArchive }
            files.append((path, entry.uncompressedSize))
        }
        return files
    }

    /// An entry's path. Archives made on Japanese Windows store Shift-JIS names without the UTF-8
    /// flag, which ZIP readers otherwise show as DOS code page 437 (and games then miss their files):
    /// valid UTF-8 stays UTF-8, other names are read as Shift-JIS when they decode, else as CP437.
    static func decodedPath(of entry: Entry) -> String {
        let utf8 = entry.path(using: .utf8)
        if !utf8.isEmpty { return utf8 }
        let japanese = entry.path(using: .shiftJIS)
        return japanese.isEmpty ? entry.path : japanese
    }

    /// Reads only the archive's file list: a desktop Ren'Py game has game/ with scripts or
    /// archives, or ships the engine (renpy/__init__.py).
    /// Names the engine of a ZIP EverPlay cannot play from its table of contents, before gigabytes of
    /// Unity or Unreal files are extracted. Archives with a web page are left to the detector: Godot
    /// and Flash games also come as browser exports.
    static func rejectUnplayableEngine(_ zip: URL) throws {
        guard let archive = try? Archive(url: zip, accessMode: .read) else { return }
        let paths = archive.prefix(50_000).map(\.path)
        let web = paths.contains { path in
            let name = (path as NSString).lastPathComponent.lowercased()
            return name.hasSuffix(".html") || name.hasSuffix(".htm") || name == "package.nw" || name == "app.asar"
        }
        if !web, let report = EngineFingerprint.identify(paths: paths), !report.playable {
            throw EverPlayError.recognizedEngine(report)
        }
    }

    public static func archiveContainsRenPyGame(_ zip: URL) -> Bool {
        guard let archive = try? Archive(url: zip, accessMode: .read) else { return false }
        for entry in archive {
            let parts = entry.path.lowercased().split(separator: "/")
            if parts.count >= 2, parts[parts.count - 2] == "renpy", parts.last == "__init__.py" { return true }
            if let index = parts.firstIndex(of: "game"), index < parts.count - 1,
               let name = parts.last, name.hasSuffix(".rpa") || name.hasSuffix(".rpyc") || name.hasSuffix(".rpy") {
                return true
            }
        }
        return false
    }
}

extension GameImporter {
    /// Packs a picked game folder into a ZIP so it passes exactly the same checks as a ZIP import.
    public static func packFolder(_ folder: URL, to zip: URL) throws {
        try FileManager.default.zipItem(at: folder, to: zip, shouldKeepParent: false)
    }
}
