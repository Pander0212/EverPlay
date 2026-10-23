import Foundation
import ZIPFoundation
import Crypto

public struct ImportLimits: Sendable {
    public var maximumEntries = 20_000
    public var maximumArchiveBytes: UInt64 = 1_073_741_824
    public var maximumFileBytes: UInt64 = 268_435_456
    public var maximumExpandedBytes: UInt64 = 2_147_483_648
    public var maximumCompressionRatio: UInt64 = 500
    public init() {}
}

public struct PreparedGame: Sendable {
    public let directory: URL
    public let validation: GameValidationResult
    public let fingerprint: String
}

public struct GameImporter: Sendable {
    public var limits: ImportLimits
    public init(limits: ImportLimits = .init()) { self.limits = limits }

    /// Caller owns a private staging parent. No application state is changed until validation succeeds.
    public func prepare(zip: URL, stagingParent: URL) throws -> PreparedGame {
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
            guard entry.type != .symlink else { throw EverPlayError.unsupportedEntry(entry.path) }
            let components = try SafePath.components(entry.path, directory: entry.type == .directory)
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
        let staging = stagingParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
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
                }
                guard actual == entry.uncompressedSize, checksum == entry.checksum else { throw EverPlayError.invalidArchive }
            }
            let validation = try GameDetector.detect(at: staging)
            // Hash extracted files and their paths, not ZIP metadata. Repacked duplicates are rejected too.
            var hash = SHA256()
            for (entry, path) in entries.sorted(by: { $0.1 < $1.1 }) where entry.type == .file {
                let descriptor = Data("\(path.utf8.count):\(path):\(entry.uncompressedSize):".utf8)
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
}

extension GameImporter {
    /// Packs a picked game folder into a ZIP so it passes exactly the same checks as a ZIP import.
    public static func packFolder(_ folder: URL, to zip: URL) throws {
        try FileManager.default.zipItem(at: folder, to: zip, shouldKeepParent: false)
    }
}
