import Foundation
import ZIPFoundation

/// Keys for encrypted KiriKiri games, from GARbro's game database (Formats.dat, MIT licence,
/// github.com/crskycode/GARbro). The app downloads the database, the player picks the game's
/// title once, and EverPlay writes that title's scheme in the engine's SHCX layout
/// (ShioriKrkr's cx_decrypt.cpp and shiori_hx.cpp read it). The game files stay as they are:
/// the engine decrypts in memory.
///
/// Formats.dat is a 12-byte header and a zlib stream of .NET BinaryFormatter records (MS-NRBF).
/// Each title is a dictionary pair whose value is a CxEncryption (CxDec) or an HxCrypt
/// (KiriKiri Z's Hx, a CxDec part plus index keys per archive).
public enum KiriKiriSchemes {
    public static let database = URL(string: "https://raw.githubusercontent.com/crskycode/GARbro/master/ArcFormats/Resources/Formats.dat")!

    struct Scheme: Sendable {
        var hx = false
        var mask: UInt32 = 0, offset: UInt32 = 0
        var orders: [UInt8] = []
        var controlBlock: [UInt32] = []
        var randomType: UInt32 = 0, filterKey: UInt64 = 0
        var defaultKey: [UInt8]?
        var archiveKeys: [(name: String, key: [UInt8])] = []
    }

    public struct Catalog: Sendable {
        let schemes: [String: Scheme]
        /// The titles the engine can play, sorted.
        public let titles: [String]

        init(schemes: [String: Scheme]) {
            self.schemes = schemes
            titles = schemes.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        /// The SHCX file for a title: "SHCX", version (1 CxDec, 2 Hx), mask, offset, the three
        /// branch orders padded to 20 bytes, the 1024-word control block, and for Hx the "HXv4"
        /// section (random type, filter key, default key, keys per archive, two empty name tables).
        public func schemeFile(title: String) -> Data? {
            guard let scheme = schemes[title] else { return nil }
            var out = Data("SHCX".utf8)
            func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
            put32(scheme.hx ? 2 : 1)
            put32(scheme.mask)
            put32(scheme.offset)
            out.append(contentsOf: scheme.orders)
            scheme.controlBlock.forEach(put32)
            guard scheme.hx else { return out }
            out.append(contentsOf: Array("HXv4".utf8))
            put32(scheme.randomType)
            withUnsafeBytes(of: scheme.filterKey.littleEndian) { out.append(contentsOf: $0) }
            out.append(scheme.defaultKey == nil ? 0 : 1)
            out.append(contentsOf: scheme.defaultKey ?? [UInt8](repeating: 0, count: 48))
            put32(UInt32(scheme.archiveKeys.count))
            for (name, key) in scheme.archiveKeys {
                let utf8 = Array(name.utf8.prefix(0xFFFF))
                withUnsafeBytes(of: UInt16(utf8.count).littleEndian) { out.append(contentsOf: $0) }
                out.append(contentsOf: utf8)
                out.append(contentsOf: key)
            }
            put32(0)  // directory names
            put32(0)  // file names
            return out
        }

        /// Titles that resemble the game's name or executable, best first.
        public func suggestions(for names: [String], limit: Int = 6) -> [String] {
            let wanted = names.map(Self.normalized).filter { $0.count >= 3 }
            guard !wanted.isEmpty else { return [] }
            let scored: [(String, Int)] = titles.compactMap { title in
                let candidate = Self.normalized(title)
                guard candidate.count >= 3 else { return nil }
                let score = wanted.map { name -> Int in
                    if candidate == name { return 100 }
                    if candidate.hasPrefix(name) || name.hasPrefix(candidate) { return 60 }
                    if candidate.contains(name) || name.contains(candidate) { return 40 }
                    return 0
                }.max() ?? 0
                return score > 0 ? (title, score - candidate.count / 8) : nil
            }
            return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        }

        static func normalized(_ text: String) -> String {
            let base = text.lowercased().replacingOccurrences(of: ".exe", with: "")
            return String(base.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        }
    }

    /// Reads the titles with a scheme the engine supports (CxEncryption and HxCrypt with an
    /// embedded control block).
    public static func catalog(from database: Data) throws -> Catalog {
        guard database.count > 14, database.starts(with: Array("GARbroDB".utf8)) else { throw EverPlayError.invalidArchive }
        let records = try XP3Archive.inflate(database.dropFirst(12), limit: 128 << 20)
        var reader = NRBF(bytes: [UInt8](records))
        try reader.readAll()
        var schemes: [String: Scheme] = [:]
        for case let .object(_, members) in reader.objects.values {
            guard let keyValue = members["key"], let entry = members["value"],
                  case let .string(title) = reader.resolve(keyValue),
                  case let .object(className, fields) = reader.resolve(entry),
                  className.hasSuffix(".CxEncryption") || className.hasSuffix(".HxCrypt"),
                  let scheme = scheme(fields, hx: className.hasSuffix(".HxCrypt"), reader: reader) else { continue }
            schemes[title] = scheme
        }
        return Catalog(schemes: schemes)
    }

    private static func scheme(_ fields: [String: NRBF.Value], hx: Bool, reader: NRBF) -> Scheme? {
        func numbers(_ name: String) -> [Int64]? { fields[name].flatMap(reader.numbers) }
        func number(_ name: String) -> Int64 { fields[name].flatMap { reader.resolve($0).number } ?? 0 }
        guard let control = numbers("ControlBlock"), control.count == 1024 else { return nil }
        var scheme = Scheme(hx: hx)
        scheme.mask = UInt32(truncatingIfNeeded: number("m_mask"))
        scheme.offset = UInt32(truncatingIfNeeded: number("m_offset"))
        let orders = [("PrologOrder", 3), ("OddBranchOrder", 6), ("EvenBranchOrder", 8)].flatMap { name, count in
            (numbers(name) ?? []).map { UInt8(truncatingIfNeeded: $0) }.padded(to: count)
        }
        scheme.orders = orders + [0, 0, 0]
        scheme.controlBlock = control.map { UInt32(truncatingIfNeeded: $0) }
        guard hx else { return scheme }

        func key(_ first: NRBF.Value?, _ second: NRBF.Value?) -> [UInt8]? {
            guard let one = first.flatMap(reader.numbers), one.count == 32,
                  let two = second.flatMap(reader.numbers), two.count == 16 else { return nil }
            return (one + two).map { UInt8(truncatingIfNeeded: $0) }
        }
        scheme.randomType = UInt32(truncatingIfNeeded: number("RandomType"))
        scheme.filterKey = UInt64(bitPattern: number("FilterKey"))
        scheme.defaultKey = key(fields["IndexKey1"], fields["IndexKey2"])
        if let dictionary = fields["IndexKeyDict"], case let .object(_, members) = reader.resolve(dictionary),
           let pairs = members["KeyValuePairs"], case let .array(items) = reader.resolve(pairs) {
            for item in items {
                guard case let .object(_, pair) = reader.resolve(item), let name = pair["key"], let value = pair["value"],
                      case let .string(archive) = reader.resolve(name),
                      case let .object(_, keys) = reader.resolve(value),
                      let archiveKey = key(keys["Key1"], keys["Key2"]) else { continue }
                scheme.archiveKeys.append((archive, archiveKey))
            }
        }
        return scheme
    }
}

private extension Array where Element == UInt8 {
    func padded(to count: Int) -> [UInt8] { Array((self + [UInt8](repeating: 0, count: count)).prefix(count)) }
}

/// A reader for the parts of MS-NRBF (.NET BinaryFormatter) that GARbro's database uses.
struct NRBF {
    indirect enum Value {
        case null, nulls(Int)
        case number(Int64), real(Double), string(String), bytes([UInt8])
        case array([Value])
        case object(String, [String: Value])
        case reference(Int32)
        case end

        var number: Int64? {
            if case let .number(value) = self { return value }
            return nil
        }
    }

    struct ClassInfo {
        var name: String
        var members: [String]
        var primitives: [UInt8?]  // the primitive type of each member, nil for a record
    }

    let bytes: [UInt8]
    var position = 0
    var objects: [Int32: Value] = [:]
    var classes: [Int32: ClassInfo] = [:]

    init(bytes: [UInt8]) { self.bytes = bytes }

    func resolve(_ value: Value) -> Value {
        if case let .reference(id) = value { return objects[id] ?? .null }
        return value
    }

    func numbers(_ value: Value) -> [Int64]? {
        switch resolve(value) {
        case let .bytes(bytes): return bytes.map(Int64.init)
        case let .array(items): return items.compactMap { resolve($0).number }
        default: return nil
        }
    }

    mutating func readAll() throws {
        while position < bytes.count {
            if case .end = try record() { return }
        }
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, position + count <= bytes.count else { throw EverPlayError.invalidArchive }
        defer { position += count }
        return bytes[position ..< position + count]
    }

    private mutating func byte() throws -> UInt8 { try take(1).first! }

    private mutating func little(_ count: Int) throws -> UInt64 {
        try take(count).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    private mutating func int32() throws -> Int32 { Int32(truncatingIfNeeded: try little(4)) }

    private mutating func count() throws -> Int {
        let value = try int32()
        guard value >= 0, Int(value) <= bytes.count else { throw EverPlayError.invalidArchive }
        return Int(value)
    }

    private mutating func string() throws -> String {
        var length = 0
        for shift in stride(from: 0, through: 28, by: 7) {
            let part = try byte()
            length |= Int(part & 0x7F) << shift
            if part & 0x80 == 0 { break }
        }
        return String(decoding: try take(length), as: UTF8.self)
    }

    private mutating func primitive(_ type: UInt8) throws -> Value {
        switch type {
        case 1: return .number(try byte() == 0 ? 0 : 1)
        case 2: return .number(Int64(try byte()))
        case 3: return .string(String(UnicodeScalar(try byte())))
        case 5, 18: return .string(try string())
        case 6: return .real(Double(bitPattern: try little(8)))
        case 7: return .number(Int64(Int16(truncatingIfNeeded: try little(2))))
        case 8: return .number(Int64(try int32()))
        case 9, 12, 13, 16: return .number(Int64(bitPattern: try little(8)))
        case 10: return .number(Int64(Int8(bitPattern: try byte())))
        case 11: return .real(Double(Float(bitPattern: UInt32(try little(4)))))
        case 14: return .number(Int64(try little(2)))
        case 15: return .number(Int64(try little(4)))
        default: throw EverPlayError.invalidArchive
        }
    }

    /// A member type's additional information; returns the primitive type for primitives.
    private mutating func additionalInfo(_ binaryType: UInt8) throws -> UInt8? {
        switch binaryType {
        case 0, 7: return try byte()
        case 3: _ = try string()
        case 4: _ = try string(); _ = try int32()
        default: break
        }
        return nil
    }

    private mutating func classInfo(withTypes: Bool) throws -> (Int32, ClassInfo) {
        let id = try int32(), name = try string(), memberCount = try count()
        var members: [String] = []
        for _ in 0 ..< memberCount { members.append(try string()) }
        var primitives = [UInt8?](repeating: nil, count: memberCount)
        if withTypes {
            let types = try (0 ..< memberCount).map { _ in try byte() }
            for (index, type) in types.enumerated() {
                let info = try additionalInfo(type)
                if type == 0 { primitives[index] = info }
            }
        }
        return (id, ClassInfo(name: name, members: members, primitives: primitives))
    }

    private mutating func members(of info: ClassInfo) throws -> [String: Value] {
        var values: [String: Value] = [:]
        for (index, member) in info.members.enumerated() {
            if let type = info.primitives[index] {
                values[member] = try primitive(type)
            } else {
                values[member] = try record()
            }
        }
        return values
    }

    private mutating func elements(_ total: Int, primitive type: UInt8?) throws -> [Value] {
        var items: [Value] = []
        while items.count < total {
            if let type {
                items.append(try primitive(type))
                continue
            }
            let item = try record()
            if case let .nulls(count) = item {
                items.append(contentsOf: repeatElement(.null, count: count))
            } else {
                items.append(item)
            }
        }
        return items
    }

    private mutating func record() throws -> Value {
        switch try byte() {
        case 0:  // SerializationHeader
            _ = try take(16)
            return .null
        case 1:  // ClassWithId
            let id = try int32(), metadata = try int32()
            guard let info = classes[metadata] else { throw EverPlayError.invalidArchive }
            objects[id] = .object(info.name, try members(of: info))
            return .reference(id)
        case let kind where (2 ... 5).contains(kind):  // (System)ClassWithMembers(AndTypes)
            let (id, info) = try classInfo(withTypes: kind >= 4)
            if kind == 3 || kind == 5 { _ = try int32() }  // library
            classes[id] = info
            objects[id] = .object(info.name, try members(of: info))
            return .reference(id)
        case 6:  // BinaryObjectString
            let id = try int32()
            objects[id] = .string(try string())
            return .reference(id)
        case 7:  // BinaryArray
            let id = try int32(), arrayType = try byte(), rank = try count()
            var total = 1
            for _ in 0 ..< rank { total *= try count() }
            if (3 ... 5).contains(arrayType) { _ = try take(4 * rank) }
            let elementType = try byte()
            let type = try additionalInfo(elementType)
            guard total <= bytes.count else { throw EverPlayError.invalidArchive }
            objects[id] = .array(try elements(total, primitive: elementType == 0 ? type : nil))
            return .reference(id)
        case 8:  // MemberPrimitiveTyped
            return try primitive(try byte())
        case 9:  // MemberReference
            return .reference(try int32())
        case 10:  // ObjectNull
            return .null
        case 11:  // MessageEnd
            return .end
        case 12:  // BinaryLibrary
            _ = try int32()
            _ = try string()
            return try record()
        case 13:  // ObjectNullMultiple256
            return .nulls(Int(try byte()))
        case 14:  // ObjectNullMultiple
            return .nulls(try count())
        case 15:  // ArraySinglePrimitive
            let id = try int32(), total = try count(), type = try byte()
            objects[id] = type == 2 ? .bytes(Array(try take(total))) : .array(try elements(total, primitive: type))
            return .reference(id)
        case 16, 17:  // ArraySingleObject, ArraySingleString
            let id = try int32(), total = try count()
            objects[id] = .array(try elements(total, primitive: nil))
            return .reference(id)
        default:
            throw EverPlayError.invalidArchive
        }
    }
}
