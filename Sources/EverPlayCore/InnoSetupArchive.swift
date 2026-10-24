import Foundation
import CLzma
import Crypto
import ZIPFoundation

/// Reads the files out of an Inno Setup 5.1–5.5 installer, the format of the official RPG Maker
/// RTP installers, without running it. Only what an RTP needs is supported: unencrypted LZMA or
/// stored data on one disk. The layout follows innoextract (https://constexpr.org/innoextract/).
public struct InnoSetupArchive {
    public struct File: Sendable {
        /// Below the installation folder ({app}), with "/" separators.
        public let path: String
        let entry: Int
    }

    struct DataEntry {
        var slice = 0, chunkOffset: UInt64 = 0, fileOffset: UInt64 = 0, size: UInt64 = 0, chunkSize: UInt64 = 0
        var checksum = Data(), filtered = false, encrypted = false, compressed = false
    }

    enum Compression: UInt8 { case stored, zlib, bzip2, lzma1, lzma2 }

    public let version: String
    public let files: [File]
    let entries: [DataEntry]
    let compression: Compression
    let setup: URL
    let dataOffset: UInt64
    let sha1: Bool

    private static let loaderMagic: [UInt8] = Array("rDlPtS".utf8) + [0xcd, 0xe6, 0xd7, 0x7b, 0x0b, 0x2a]

    /// True for an .exe that carries an Inno Setup installer.
    public static func isInstaller(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return false }
        return data.range(of: Data(loaderMagic)) != nil
    }

    public init(setup: URL) throws {
        let data = try Data(contentsOf: setup, options: .alwaysMapped)
        guard let magic = data.range(of: Data(Self.loaderMagic)) else { throw EverPlayError.unsupportedInstaller("no Inno Setup data") }
        var loader = Reader(data, at: magic.upperBound)
        _ = try loader.u32()  // revision
        _ = try loader.u32()  // total size
        _ = try loader.u32()  // embedded setup program offset
        _ = try loader.u32()  // its size
        _ = try loader.u32()  // its CRC
        let headerOffset = Int(try loader.u32())
        dataOffset = UInt64(try loader.u32())
        self.setup = setup

        guard headerOffset + 64 <= data.count else { throw EverPlayError.invalidArchive }
        let label = String(decoding: data[headerOffset..<headerOffset + 64].prefix { $0 != 0 }, as: UTF8.self)
        guard let open = label.firstIndex(of: "("), let close = label[open...].firstIndex(of: ")") else {
            throw EverPlayError.unsupportedInstaller(label)
        }
        let numbers = label[label.index(after: open)..<close].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { throw EverPlayError.unsupportedInstaller(label) }
        let v = Self.version(numbers[0], numbers[1], numbers[2])
        guard v >= Self.version(5, 1, 0), v < Self.version(5, 6, 0) else { throw EverPlayError.unsupportedInstaller(label) }
        let unicode = label.contains("(u)")
        version = label
        sha1 = v >= Self.version(5, 3, 9)

        let (header, next) = try Self.block(data, at: headerOffset + 64)
        var r = Reader(header)
        try Self.skipSetupHeader(&r, v: v, unicode: unicode)
        let counts = try (0..<16).map { _ in try r.u32() }
        let method = try Self.skipHeaderTail(&r, v: v, unicode: unicode)
        guard let compression = Compression(rawValue: method) else { throw EverPlayError.unsupportedInstaller("compression \(method)") }
        self.compression = compression
        let (languages, messages, permissions, types, components, tasks, directories, fileCount, dataCount) =
            (counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8])
        for _ in 0..<languages {
            try r.strings(10)
            _ = try r.u32()
            if !unicode || v < Self.version(5, 3, 0) { _ = try r.u32() }
            try r.skip(16)
            if v >= Self.version(5, 2, 3) { try r.skip(1) }
        }
        for _ in 0..<messages { try r.strings(2); try r.skip(4) }
        for _ in 0..<permissions { try r.strings(1) }
        for _ in 0..<types { try r.strings(4); try r.skip(Self.windowsRange); try r.flags(1); try r.skip(1 + 8) }
        for _ in 0..<components {
            try r.strings(5); try r.skip(8 + 4 + 1 + Self.windowsRange); try r.flags(5); try r.skip(8)
        }
        for _ in 0..<tasks { try r.strings(6); try r.skip(4 + 1 + Self.windowsRange); try r.flags(5) }
        for _ in 0..<directories {
            try r.strings(7); try r.skip(4 + Self.windowsRange + 2); try r.flags(v >= Self.version(5, 2, 0) ? 5 : 3)
        }
        var files: [File] = []
        for _ in 0..<fileCount {
            _ = try r.string()
            let destination = try r.string()
            try r.strings(v >= Self.version(5, 2, 5) ? 2 : 1)
            try r.strings(6)
            try r.skip(Self.windowsRange)
            let location = try r.u32()
            try r.skip(4 + 8 + 2)
            try r.flags(25 + (v >= Self.version(5, 2, 0) ? 3 : 0) + (v >= Self.version(5, 2, 5) ? 1 : 0))
            try r.skip(1)
            let name = unicode ? String(decoding: Self.utf16(destination), as: UTF16.self)
                               : String(decoding: destination, as: UTF8.self)
            guard location < dataCount, name.lowercased().hasPrefix("{app}\\") else { continue }
            let path = name.dropFirst(6).split(separator: "\\").joined(separator: "/")
            files.append(File(path: path, entry: Int(location)))
        }

        let (second, _) = try Self.block(data, at: next)
        var d = Reader(second)
        var entries: [DataEntry] = []
        for _ in 0..<dataCount {
            var entry = DataEntry()
            let first = try d.u32(), last = try d.u32()
            guard first == last else { throw EverPlayError.unsupportedInstaller("spans several disks") }
            entry.slice = Int(first)
            entry.chunkOffset = UInt64(try d.u32())
            entry.fileOffset = try d.u64()
            entry.size = try d.u64()
            entry.chunkSize = try d.u64()
            entry.checksum = try d.bytes(sha1 ? 20 : 16)
            try d.skip(8 + 8)
            let count = 8 + (v >= Self.version(5, 1, 13) ? 1 : 0) + (v >= Self.version(5, 5, 7) ? 2 : 0)
            let bits = try d.flagBits(count)
            entry.filtered = bits & (1 << 4) != 0
            entry.encrypted = bits & (1 << 6) != 0
            entry.compressed = bits & (1 << 7) != 0
            entries.append(entry)
        }
        self.entries = entries
        // Later entries for the same path win, as when the installer runs.
        var last: [String: Int] = [:]
        for (index, file) in files.enumerated() { last[file.path.lowercased()] = index }
        self.files = files.enumerated().filter { last[$0.element.path.lowercased()] == $0.offset }.map(\.element)
    }

    /// Writes the files below `folder`. Returns how many were written. Program files (stored with
    /// Inno's x86 call filter) are left out.
    @discardableResult
    public func extract(into folder: URL, include: (String) -> Bool = { _ in true }) throws -> Int {
        var targets: [Int: [URL]] = [:]
        for file in files where include(file.path) && !entries[file.entry].filtered {
            let components = try SafePath.components(file.path, directory: false)
            targets[file.entry, default: []].append(try SafePath.destination(components.joined(separator: "/"), in: folder))
        }
        if entries.contains(where: { $0.encrypted }) && targets.keys.contains(where: { entries[$0].encrypted }) {
            throw EverPlayError.unsupportedInstaller("encrypted")
        }
        let chunks = Dictionary(grouping: targets.keys, by: { ChunkKey(slice: entries[$0].slice, offset: entries[$0].chunkOffset) })
        ImportProgress.shared.start(total: targets.keys.reduce(0) { $0 + entries[$1].size })
        defer { ImportProgress.shared.finish() }
        var written = 0
        for (key, members) in chunks.sorted(by: { ($0.key.slice, $0.key.offset) < ($1.key.slice, $1.key.offset) }) {
            let first = entries[members[0]]
            let source = try sliceData(key.slice)
            let start = Int(key.offset + (dataOffset > 0 ? dataOffset : 0))
            guard start + 4 <= source.count, source[start..<start + 4] == Data("zlb\u{1a}".utf8) else {
                throw EverPlayError.invalidArchive
            }
            let end = min(source.count, start + 4 + Int(first.chunkSize))
            var stream = try ChunkStream(source[(start + 4)..<end], compression: first.compressed ? compression : .stored)
            var position: UInt64 = 0
            for index in members.sorted(by: { entries[$0].fileOffset < entries[$1].fileOffset }) {
                try Task.checkCancellation()
                let entry = entries[index]
                guard entry.fileOffset >= position else { continue }
                try stream.skip(entry.fileOffset - position)
                let outputs = try targets[index, default: []].map { url -> FileHandle in
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw EverPlayError.invalidArchive }
                    return try FileHandle(forWritingTo: url)
                }
                defer { outputs.forEach { try? $0.close() } }
                var md5 = Insecure.MD5(), sha = Insecure.SHA1()
                var remaining = entry.size
                while remaining > 0 {
                    let piece = try stream.read(Int(min(remaining, 1 << 20)))
                    if sha1 { sha.update(data: piece) } else { md5.update(data: piece) }
                    for output in outputs { try output.write(contentsOf: piece) }
                    remaining -= UInt64(piece.count)
                    ImportProgress.shared.advance(by: UInt64(piece.count))
                }
                position = entry.fileOffset + entry.size
                let digest = sha1 ? Data(sha.finalize()) : Data(md5.finalize())
                guard digest == entry.checksum else { throw EverPlayError.invalidArchive }
                written += outputs.count
            }
        }
        return written
    }

    // MARK: - Layout

    private struct ChunkKey: Hashable { let slice: Int; let offset: UInt64 }

    private static let windowsRange = 2 * (4 + 4 + 2)

    private static func version(_ a: Int, _ b: Int, _ c: Int) -> Int { (a << 24) | (b << 16) | (c << 8) }

    private static func utf16(_ data: Data) -> [UInt16] {
        stride(from: 0, to: data.count - 1, by: 2).map { UInt16(data[data.startIndex + $0]) | UInt16(data[data.startIndex + $0 + 1]) << 8 }
    }

    /// The installer's data, or the Setup-N.bin next to it.
    private func sliceData(_ slice: Int) throws -> Data {
        if dataOffset > 0 { return try Data(contentsOf: setup, options: .alwaysMapped) }
        let folder = setup.deletingLastPathComponent()
        let base = setup.deletingPathExtension().lastPathComponent.lowercased()
        let wanted = ["\(base)-\(slice + 1).bin", "setup-\(slice + 1).bin"]
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let name = names.first(where: { wanted.contains($0.lowercased()) }) else {
            throw EverPlayError.unsupportedInstaller("Setup-\(slice + 1).bin is missing")
        }
        let data = try Data(contentsOf: folder.appendingPathComponent(name), options: .alwaysMapped)
        guard data.count >= 12, data.prefix(4) == Data("idsk".utf8) else { throw EverPlayError.invalidArchive }
        return data
    }

    /// A header block: CRC-checked 4 KiB pieces of one LZMA stream. Returns the data and where the next block starts.
    private static func block(_ data: Data, at offset: Int) throws -> (Data, Int) {
        var r = Reader(data, at: offset)
        let crc = try r.u32()
        let stored = Int(try r.u32())
        let compressed = try r.u8() != 0
        guard data[(offset + 4)..<(offset + 9)].crc32(checksum: 0) == crc else { throw EverPlayError.invalidArchive }
        let end = offset + 9 + stored
        guard end <= data.count else { throw EverPlayError.invalidArchive }
        var payload = Data()
        var position = offset + 9
        while position < end {
            let pieceCRC = UInt32(littleEndian: data[position..<position + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            let piece = data[(position + 4)..<min(position + 4 + 4096, end)]
            guard piece.crc32(checksum: 0) == pieceCRC else { throw EverPlayError.invalidArchive }
            payload.append(piece)
            position += 4 + piece.count
        }
        guard compressed else { return (payload, end) }
        var stream = try ChunkStream(payload, compression: .lzma1)
        var output = Data()
        while true {
            let piece = try stream.read(1 << 20, allowShort: true)
            if piece.isEmpty { break }
            output.append(piece)
        }
        return (output, end)
    }

    private static func skipSetupHeader(_ r: inout Reader, v: Int, unicode: Bool) throws {
        try r.strings(6)                                      // app name … publisher URL
        if v >= version(5, 1, 13) { try r.strings(1) }        // support phone
        try r.strings(3 + 2 + 1)                              // URLs and version, dir and group, base name
        if v < version(5, 2, 5) { try r.strings(3) }          // license, info before/after
        try r.strings(1 + 2 + 1 + 2 + 1)                      // uninstall dir, name, icon, mutex, user, serial
        if v < version(5, 2, 5) { try r.strings(1) }          // compiled code
        try r.strings(4)                                      // readme, contact, comments, modify path
        if v >= version(5, 3, 8) { try r.strings(1) }
        if v >= version(5, 3, 10) { try r.strings(1) }
        if v >= version(5, 5, 0) { try r.strings(1) }
        if v >= version(5, 5, 6) { try r.strings(1) }
        if v >= version(5, 2, 5) { try r.strings(3) }         // license, info before/after
        if v >= version(5, 2, 1) && v < version(5, 3, 10) { try r.strings(1) }
        if v >= version(5, 2, 5) { try r.strings(1) }         // compiled code
        if !unicode { try r.skip(32) }                        // lead bytes
    }

    /// Skips the rest of the setup header; returns the compression method.
    private static func skipHeaderTail(_ r: inout Reader, v: Int, unicode: Bool) throws -> UInt8 {
        try r.skip(windowsRange + 4 + 4)                      // Windows versions, background colors
        try r.skip(v < version(5, 5, 7) ? 4 : 1)              // image background or alpha format
        try r.skip(v >= version(5, 3, 9) ? 20 : 16)           // password hash
        try r.skip(8 + 8 + 4)                                 // salt, extra disk space, slices per disk
        try r.skip(1 + 1 + 1 + 1 + 1)                         // log mode, dir warning, privileges, language dialog and detection
        let compression = try r.u8()
        try r.skip(2)                                         // architectures
        if v >= version(5, 2, 1) && v < version(5, 3, 10) { try r.skip(8) }
        if v >= version(5, 3, 3) { try r.skip(2) }
        if v >= version(5, 5, 0) { try r.skip(8) } else if v >= version(5, 3, 6) { try r.skip(4) }
        // Setup options (see innoextract's header::load_flags for the list).
        var flags = 13 + (v < version(5, 3, 10) ? 1 : 0) + (v < version(5, 3, 3) ? 2 : 0)
        flags += 1 + (v < version(5, 3, 8) ? 1 : 0) + 5 + 19 + 1
        flags += (!unicode && v >= version(5, 1, 7) ? 1 : 0) + (v >= version(5, 1, 13) ? 1 : 0)
        flags += (v >= version(5, 2, 1) ? 1 : 0) + (v >= version(5, 3, 8) ? 1 : 0) + (v >= version(5, 3, 9) ? 1 : 0)
        flags += (v >= version(5, 5, 0) ? 3 : 0) + (v >= version(5, 5, 7) ? 1 : 0)
        try r.flags(flags)
        return compression
    }
}

/// Little-endian reads with bounds checks.
struct Reader {
    let data: Data
    var position: Int

    init(_ data: Data, at position: Int = 0) {
        self.data = data
        self.position = data.startIndex + position
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, position + count <= data.endIndex else { throw EverPlayError.invalidArchive }
        defer { position += count }
        return data[position..<position + count]
    }
    mutating func skip(_ count: Int) throws { _ = try bytes(count) }
    mutating func u8() throws -> UInt8 { try bytes(1).first! }
    mutating func u32() throws -> UInt32 { try bytes(4).reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    mutating func u64() throws -> UInt64 { try bytes(8).reversed().reduce(0) { $0 << 8 | UInt64($1) } }
    mutating func string() throws -> Data { try bytes(Int(try u32())) }
    mutating func strings(_ count: Int) throws { for _ in 0..<count { _ = try string() } }
    /// A Delphi set: one bit per flag, three bytes padded to four.
    mutating func flagBits(_ count: Int) throws -> UInt64 {
        let length = (count + 7) / 8
        let value = try bytes(length).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        if length == 3 { try skip(1) }
        return value
    }
    mutating func flags(_ count: Int) throws { _ = try flagBits(count) }
}

/// Inno's chunk data, decompressed as it is read.
struct ChunkStream {
    private let input: Data
    private var position: Int
    private let compression: InnoSetupArchive.Compression
    private var finished = false
    private final class Box { var pointer: OpaquePointer?; deinit { everplay_lzma_close(pointer) } }
    private let box = Box()

    init(_ input: Data, compression: InnoSetupArchive.Compression) throws {
        self.input = input
        self.compression = compression
        position = input.startIndex
        switch compression {
        case .stored: break
        case .lzma1:
            guard input.count >= 5 else { throw EverPlayError.invalidArchive }
            let properties = [UInt8](input.prefix(5))
            box.pointer = properties.withUnsafeBufferPointer { everplay_lzma1_open($0.baseAddress) }
            position += 5
        case .lzma2:
            guard let property = input.first else { throw EverPlayError.invalidArchive }
            box.pointer = everplay_lzma2_open(property)
            position += 1
        case .zlib, .bzip2:
            throw EverPlayError.unsupportedInstaller("zlib/bzip2 data")
        }
        if compression != .stored && box.pointer == nil { throw EverPlayError.invalidArchive }
    }

    /// Up to `count` bytes; exactly `count` unless `allowShort` (then empty at the end).
    mutating func read(_ count: Int, allowShort: Bool = false) throws -> Data {
        var output = Data(count: count)
        var filled = 0
        if compression == .stored {
            filled = min(count, input.endIndex - position)
            output.replaceSubrange(0..<filled, with: input[position..<position + filled])
            position += filled
        } else {
            while filled < count && !finished {
                var used = input.endIndex - position
                var produced = count - filled
                let status = input.withUnsafeBytes { raw -> Int32 in
                    output.withUnsafeMutableBytes { out in
                        everplay_lzma_decode(box.pointer, raw.baseAddress!.assumingMemoryBound(to: UInt8.self) + (position - input.startIndex),
                                             &used, out.baseAddress!.assumingMemoryBound(to: UInt8.self) + filled, &produced)
                    }
                }
                guard status >= 0 else { throw EverPlayError.invalidArchive }
                position += used
                filled += produced
                if status == 1 || (used == 0 && produced == 0) { finished = true }
            }
        }
        guard filled == count || allowShort else { throw EverPlayError.invalidArchive }
        return output.prefix(filled)
    }

    mutating func skip(_ count: UInt64) throws {
        var remaining = count
        while remaining > 0 {
            remaining -= UInt64(try read(Int(min(remaining, 1 << 20))).count)
        }
    }
}
