import Foundation

/// Electron's app.asar (TyranoScript 5 and other Electron desktop builds keep the game in it):
/// a JSON table of contents followed by the files, stored uncompressed.
///
/// Layout: UInt32 4, UInt32 header size, then the header pickle (UInt32 payload size, UInt32
/// JSON length, JSON) and the file data, which starts right after the header. Each file entry
/// has "size" and "offset" (a decimal string, relative to the file data); "unpacked" files live
/// next to the archive in app.asar.unpacked/, and "link" entries are symlinks.
public enum AsarArchive {
    /// Extracts the archive into a new directory with the same checks as a ZIP import: safe and
    /// unique paths, size limits, every file inside the archive. Links are skipped; unpacked files
    /// are copied from the sibling .unpacked folder when it is there.
    @discardableResult
    public static func extract(_ asar: URL, into target: URL, limits: ImportLimits = .init()) throws -> [(path: String, size: UInt64)] {
        let attributes = try FileManager.default.attributesOfItem(atPath: asar.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let archiveSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            throw EverPlayError.unsupportedEntry(asar.lastPathComponent)
        }
        guard archiveSize <= limits.maximumArchiveBytes else { throw EverPlayError.limitExceeded("archive size") }
        let handle = try FileHandle(forReadingFrom: asar)
        defer { try? handle.close() }
        func read(_ count: Int, at offset: UInt64) throws -> Data {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { throw EverPlayError.invalidArchive }
            return data
        }
        func uint32(_ data: Data, _ at: Int) -> UInt64 {
            data.subdata(in: at..<(at + 4)).withUnsafeBytes { UInt64(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        }
        let prefix = try read(16, at: 0)
        let headerSize = uint32(prefix, 4)
        let jsonLength = uint32(prefix, 12)
        guard uint32(prefix, 0) == 4, jsonLength > 0, jsonLength <= 64 * 1_048_576,
              16 + jsonLength <= 8 + headerSize, 8 + headerSize <= archiveSize else {
            throw EverPlayError.invalidArchive
        }
        let dataStart = 8 + headerSize
        guard let header = try JSONSerialization.jsonObject(with: read(Int(jsonLength), at: 16)) as? [String: Any],
              let root = header["files"] as? [String: Any] else {
            throw EverPlayError.invalidArchive
        }

        // Collect and check every entry before writing anything.
        var files: [(path: String, offset: UInt64, size: UInt64, unpacked: Bool)] = []
        var directories: [String] = []
        var seen: Set<String> = []
        var total: UInt64 = 0
        func walk(_ node: [String: Any], _ parent: [String]) throws {
            for (name, value) in node {
                guard let entry = value as? [String: Any] else { throw EverPlayError.invalidArchive }
                let parts = try SafePath.components((parent + [name]).joined(separator: "/"))
                let path = parts.joined(separator: "/")
                guard seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw EverPlayError.unsafePath("duplicate: \(path)")
                }
                guard files.count + directories.count < limits.maximumEntries else { throw EverPlayError.limitExceeded("file count") }
                if let children = entry["files"] as? [String: Any] {
                    directories.append(path)
                    try walk(children, parts)
                } else if entry["link"] != nil {
                    continue
                } else {
                    guard let size = (entry["size"] as? NSNumber)?.uint64Value else { throw EverPlayError.invalidArchive }
                    let unpacked = (entry["unpacked"] as? Bool) ?? false
                    var offset: UInt64 = 0
                    if !unpacked {
                        guard let text = entry["offset"] as? String, let value = UInt64(text),
                              value <= archiveSize, size <= archiveSize - value,
                              dataStart + value + size <= archiveSize else { throw EverPlayError.invalidArchive }
                        offset = value
                    }
                    guard size <= limits.maximumFileBytes,
                          size <= limits.maximumExpandedBytes - min(total, limits.maximumExpandedBytes) else {
                        throw EverPlayError.limitExceeded("expanded size")
                    }
                    total += size
                    files.append((path, offset, size, unpacked))
                }
            }
        }
        try walk(root, [])
        guard !files.isEmpty else { throw EverPlayError.invalidArchive }

        let unpackedRoot = asar.deletingLastPathComponent().appendingPathComponent(asar.lastPathComponent + ".unpacked")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for directory in directories {
            try FileManager.default.createDirectory(at: try SafePath.destination(directory, in: target), withIntermediateDirectories: true)
        }
        ImportProgress.shared.start(total: total)
        defer { ImportProgress.shared.finish() }
        var written: [(path: String, size: UInt64)] = []
        for file in files {
            try Task.checkCancellation()
            let destination = try SafePath.destination(file.path, in: target)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if file.unpacked {
                let source = try SafePath.destination(file.path, in: unpackedRoot)
                guard let size = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.size] as? NSNumber,
                      size.uint64Value == file.size else { continue }
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw EverPlayError.invalidArchive }
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var remaining = file.size
                try handle.seek(toOffset: dataStart + file.offset)
                while remaining > 0 {
                    let count = Int(min(remaining, 1_048_576))
                    guard let data = try handle.read(upToCount: count), data.count == count else { throw EverPlayError.invalidArchive }
                    try output.write(contentsOf: data)
                    remaining -= UInt64(count)
                    ImportProgress.shared.advance(by: UInt64(count))
                }
            }
            written.append((file.path, file.size))
        }
        return written
    }
}
