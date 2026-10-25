// See WolfData.hpp. The decryption of protected (Pro) data files is WolfTL's WolfCrypt.
#include "WolfData.hpp"

#include <cstring>
#include <iconv.h>
#include <mutex>

#include "../../third_party/lz4/lz4.h"
#include "../../third_party/wolfcrypt/WolfCrypt/WolfDataDecrypt.hpp"

namespace wolf {

namespace {

thread_local bool g_utf8 = false;
// The key that decrypts .project files, taken from the protected .dat files (-1: none).
thread_local int g_projectKey = -1;
// v3.5 files carry extra bytes after every command.
thread_local bool g_v35 = false;

std::string decodeString(const uint8_t* p, size_t n, bool utf8) {
    while (n > 0 && p[n - 1] == 0) n--;
    if (utf8) return std::string(reinterpret_cast<const char*>(p), n);
    bool ascii = true;
    for (size_t i = 0; i < n; i++)
        if (p[i] >= 0x80) { ascii = false; break; }
    if (ascii) return std::string(reinterpret_cast<const char*>(p), n);
    return sjisToUtf8(p, n);
}

Bytes lz4Unpack(const Bytes& data, size_t start, size_t keepHeader) {
    Reader r(data);
    r.seek(start);
    uint32_t decSize = uint32_t(r.i32());
    uint32_t encSize = uint32_t(r.i32());
    if (encSize > r.remaining() || decSize > 512u * 1024 * 1024) throw DataError("bad LZ4 block");
    Bytes out(keepHeader + decSize);
    std::memcpy(out.data(), data.data(), keepHeader);
    int n = LZ4_decompress_safe(reinterpret_cast<const char*>(data.data() + r.offset()),
                                reinterpret_cast<char*>(out.data() + keepHeader), int(encSize), int(decSize));
    if (n < 0) throw DataError("LZ4 decompression failed");
    out.resize(keepHeader + size_t(n));
    return out;
}

// The magic of a data file, with the byte that turns into 0x55 ('U') in UTF-8 (v3) files.
struct Magic {
    std::vector<uint8_t> bytes;
    int utf8Index;
};
const Magic kDatMagic{{0x57, 0x00, 0x00, 0x4F, 0x4C, 0x00, 0x46, 0x4D, 0x00}, 5};
const Magic kGameDatMagic{{0x57, 0x00, 0x00, 0x4F, 0x4C, 0x00, 0x46, 0x4D, 0x00}, 8};
const Magic kCommonMagic{{0x57, 0x00, 0x00, 0x4F, 0x4C, 0x00, 0x46, 0x43, 0x00}, 5};

bool checkMagic(Reader& r, const Magic& m) {
    for (size_t i = 0; i < m.bytes.size(); i++) {
        uint8_t b = r.u8();
        if (b == m.bytes[i]) continue;
        if (int(i) == m.utf8Index && b == 0x55) { g_utf8 = true; r.setUtf8(true); continue; }
        return false;
    }
    return true;
}

// Opens the envelope of a data file (the leading indicator byte, encryption, compression) the
// way WolfTL's FileCoder::load does. Returns a reader positioned at the magic, or after the
// encryption header for encrypted files (`encrypted` is then true and the magic is absent).
Reader openEnvelope(Bytes data, WolfFileType type, SeedIncides seeds, bool& encrypted) {
    encrypted = false;
    if (data.size() < 12) throw DataError("file too small");
    if (data[1] == 0x50) {  // 'P': protected by WOLF RPG Editor Pro
        uint8_t cryptVersion = data[5];
        if (cryptVersion < 0x55) {
            // v3.1: the v2 scheme plus a project key.
            SeedIncides s{};
            for (size_t i = 0; i < 3; i++) s[i] = data[seeds[i]];
            Bytes rest(data.begin() + 10, data.end());
            wolf::crypt::datadecrypt::v2_0::decryptData(rest, s);
            Reader r(std::move(rest), true);
            g_utf8 = true;
            encrypted = true;
            r.skip(5);
            uint32_t keySize = uint32_t(r.i32());
            if (type == WolfFileType::GameDat) {
                r.skip(keySize);
            } else {
                int8_t key = int8_t(r.u8());
                if (g_projectKey == -1) g_projectKey = uint8_t(key);
                r.skip(keySize - 1);
            }
            return r;
        }
        if (cryptVersion < 0x57) {
            auto cd = wolf::crypt::datadecrypt::v3_3::decryptData(data, seeds);
            Bytes dec(cd.gameDatBytes.begin(), cd.gameDatBytes.end());
            g_projectKey = dec.size() > 0x14 ? dec[0x14] : 0;
            Reader r(std::move(dec), true);
            g_utf8 = true;
            encrypted = true;
            r.skip(143);
            return r;
        }
        if (!wolf::crypt::datadecrypt::v3_5::decryptData(data, type)) throw DataError("Pro v3.5 decryption failed");
        g_utf8 = true;
        g_projectKey = 0;
        // The decryption restored the plain header; fall through to the normal path.
    }
    if (type == WolfFileType::Map) {
        Reader r(std::move(data), g_utf8);
        if (r.at(20) >= 0x65) r = Reader(lz4Unpack(r.data(), 25, 25), g_utf8);
        return r;
    }
    if (data[0] != 0 && type != WolfFileType::DataBase) {
        // v2 encryption: a 10-byte header whose bytes seed three XOR passes.
        SeedIncides s{};
        for (size_t i = 0; i < 3; i++) s[i] = data[seeds[i]];
        Bytes rest(data.begin() + 10, data.end());
        wolf::crypt::datadecrypt::v2_0::decryptData(rest, s);
        encrypted = true;
        return Reader(std::move(rest), g_utf8);
    }
    if (type == WolfFileType::DataBase && data.size() > 11 && data[10] == 0xC4) {
        data = lz4Unpack(data, 11, 11);
    }
    Reader r(std::move(data), g_utf8);
    r.skip(1);  // the indicator byte
    return r;
}

std::shared_ptr<MoveRoute> readMoveRoute(Reader& r) {
    auto route = std::make_shared<MoveRoute>();
    for (auto& b : route->target) b = r.u8();
    route->flags = r.u8();
    uint32_t n = r.count(2);
    route->commands.resize(n);
    for (auto& c : route->commands) {
        c.id = r.u8();
        uint8_t argc = r.u8();
        c.args.resize(argc);
        for (auto& a : c.args) a = r.i32();
        if (r.u8() != 0x01 || r.u8() != 0x00) throw DataError("bad move route terminator");
    }
    return route;
}

std::vector<RouteCommand> readRouteCommands(Reader& r) {
    uint32_t n = r.count(2);
    std::vector<RouteCommand> out(n);
    for (auto& c : out) {
        c.id = r.u8();
        uint8_t argc = r.u8();
        c.args.resize(argc);
        for (auto& a : c.args) a = r.i32();
        if (r.u8() != 0x01 || r.u8() != 0x00) throw DataError("bad route terminator");
    }
    return out;
}

Command readCommand(Reader& r) {
    Command c;
    uint8_t argc = r.u8();
    if (argc == 0) throw DataError("bad command");
    c.code = r.i32();
    c.args.resize(argc - 1);
    for (auto& a : c.args) a = r.i32();
    c.indent = r.u8();
    uint8_t strc = r.u8();
    c.strings.resize(strc);
    for (auto& s : c.strings) s = r.str();
    uint8_t term = r.u8();
    if (term == 0x01) {
        c.route = readMoveRoute(r);
    } else if (term != 0x00) {
        throw DataError("bad command terminator " + std::to_string(term) + " at " + std::to_string(r.offset()));
    }
    if (g_v35) {
        uint8_t extra = r.u8();
        if (extra) r.skip(extra);
    }
    return c;
}

CommandList readCommands(Reader& r) {
    uint32_t n = r.count(6);
    CommandList list;
    list.reserve(n);
    for (uint32_t i = 0; i < n; i++) list.push_back(readCommand(r));
    return list;
}

}  // namespace

// ---------------------------------------------------------------------------------------------

std::string Reader::str() {
    uint32_t n = uint32_t(i32());
    if (n > remaining()) throw DataError("bad string length " + std::to_string(n) + " at " + std::to_string(pos_ - 4));
    std::string s = decodeString(data_.data() + pos_, n, utf8_);
    pos_ += n;
    return s;
}

void Reader::expect(std::initializer_list<uint8_t> magic, const char* what) {
    for (uint8_t b : magic)
        if (u8() != b) throw DataError(std::string("bad ") + what + " at " + std::to_string(pos_ - 1));
}

std::string sjisToUtf8(const uint8_t* data, size_t size) {
    static std::mutex lock;
    std::lock_guard<std::mutex> guard(lock);
    static iconv_t cd = iconv_open("UTF-8", "CP932");
    std::string out;
    if (cd == (iconv_t)-1) {
        out.assign(reinterpret_cast<const char*>(data), size);
        return out;
    }
    iconv(cd, nullptr, nullptr, nullptr, nullptr);
    out.resize(size * 3 + 4);
    char* in = const_cast<char*>(reinterpret_cast<const char*>(data));
    size_t inLeft = size;
    char* o = out.data();
    size_t outLeft = out.size();
    while (inLeft > 0) {
        size_t res = iconv(cd, &in, &inLeft, &o, &outLeft);
        if (res != (size_t)-1) break;
        if (errno == E2BIG) break;
        // Skip one invalid byte and emit U+FFFD.
        in++;
        inLeft--;
        if (outLeft >= 3) {
            *o++ = char(0xEF); *o++ = char(0xBF); *o++ = char(0xBD);
            outLeft -= 3;
        }
        iconv(cd, nullptr, nullptr, nullptr, nullptr);
    }
    out.resize(out.size() - outLeft);
    return out;
}

bool lastFileWasUtf8() { return g_utf8; }

// ---------------------------------------------------------------------------------------------

GameDat parseGameDat(Bytes data) {
    g_utf8 = false;
    g_projectKey = -1;
    bool encrypted = false;
    Reader r = openEnvelope(std::move(data), WolfFileType::GameDat, {0, 8, 6}, encrypted);
    if (!encrypted && !checkMagic(r, kGameDatMagic)) throw DataError("Game.dat: bad magic");
    GameDat g;
    g.utf8 = g_utf8;
    r.setUtf8(g_utf8);
    Bytes settings = r.byteArray();
    g.u8.assign(settings.begin(), settings.end());
    uint32_t stringCount = r.count(4);
    for (uint32_t i = 0; i < stringCount; i++) {
        if (i == 2) {  // the decryption key of the archives, raw bytes
            r.byteArray();
            g.strings.emplace_back();
            continue;
        }
        g.strings.push_back(r.str());
    }
    if (g.strings.size() > 1 && g.strings[1] != "0000-0000") throw DataError("Game.dat: bad magic string");
    r.i32();  // file size
    r.i32();
    uint32_t words = r.count(2);
    for (uint32_t i = 0; i < words; i++) g.u16.push_back(r.u16());
    return g;
}

Database parseDatabase(Bytes projectData, Bytes datData) {
    // The .dat first: protected games carry the .project key there.
    bool encrypted = false;
    Reader dat = openEnvelope(std::move(datData), WolfFileType::DataBase, {0, 3, 9}, encrypted);
    if (!encrypted && !checkMagic(dat, kDatMagic)) throw DataError("database .dat: bad magic");
    dat.setUtf8(g_utf8);
    uint8_t version = dat.u8();
    (void)version;

    if (g_projectKey != -1) {
        wolf::crypt::rng::msvc_srand(uint32_t(g_projectKey));
        for (auto& b : projectData) b ^= uint8_t(wolf::crypt::rng::msvc_rand());
    }
    Reader pr(std::move(projectData), g_utf8);
    Database db;
    uint32_t typeCount = pr.count(4);
    db.types.resize(typeCount);
    for (auto& t : db.types) {
        t.name = pr.str();
        uint32_t fieldCount = pr.count(4);
        t.fields.resize(fieldCount);
        for (auto& f : t.fields) f.name = pr.str();
        uint32_t dataCount = pr.count(4);
        t.records.resize(dataCount);
        for (auto& d : t.records) d.name = pr.str();
        t.description = pr.str();
        uint32_t typeListSize = pr.count(1);
        for (uint32_t i = 0; i < typeListSize; i++) {
            uint8_t b = pr.u8();
            if (i < fieldCount) t.fields[i].type = b;
        }
        uint32_t n = pr.count(4);
        for (uint32_t i = 0; i < n; i++) {
            pr.str();  // per-field memo
        }
        n = pr.count(4);
        for (uint32_t i = 0; i < n; i++) {
            auto strs = pr.strArray();
            if (i < fieldCount) t.fields[i].stringArgs = std::move(strs);
        }
        n = pr.count(4);
        for (uint32_t i = 0; i < n; i++) {
            auto ints = pr.intArray();
            if (i < fieldCount) t.fields[i].args = std::move(ints);
        }
        n = pr.count(4);
        for (uint32_t i = 0; i < n; i++) {
            int32_t v = pr.i32();
            if (i < fieldCount) t.fields[i].defaultValue = v;
        }
    }

    uint32_t datTypes = dat.count(4);
    if (datTypes != db.types.size()) throw DataError("database: .project and .dat type counts differ");
    for (auto& t : db.types) {
        dat.expect({0xFE, 0xFF, 0xFF, 0xFF}, "database type separator");
        t.idMode = dat.i32();
        uint32_t fieldsSize = dat.count(4);
        if (t.idMode == 0x1D4C0) dat.str();
        if (fieldsSize > t.fields.size()) t.fields.resize(fieldsSize);
        uint32_t ints = 0, strs = 0;
        for (uint32_t i = 0; i < fieldsSize; i++) {
            int32_t info = dat.i32();
            auto& f = t.fields[i];
            f.isString = info >= 2000;
            f.index = f.isString ? info - 2000 : info - 1000;
            if (f.isString) strs++; else ints++;
        }
        t.fields.resize(fieldsSize);
        uint32_t dataSize = dat.count(1);
        if (t.records.size() > dataSize) t.records.resize(dataSize);
        if (t.records.size() < dataSize) t.records.resize(dataSize);
        for (auto& d : t.records) {
            d.ints.resize(ints);
            for (auto& v : d.ints) v = dat.i32();
            d.strings.resize(strs);
            for (auto& s : d.strings) s = dat.str();
        }
    }
    return db;
}

std::vector<CommonEvent> parseCommonEvents(Bytes data) {
    bool encrypted = false;
    g_v35 = false;
    Reader r = openEnvelope(std::move(data), WolfFileType::CommonEvent, {0, 3, 9}, encrypted);
    if (!encrypted && !checkMagic(r, kCommonMagic)) throw DataError("CommonEvent.dat: bad magic");
    r.setUtf8(g_utf8);
    uint8_t version = r.u8();
    if (version == 0x93 || version == 0xCC) {
        g_v35 = true;
        size_t start = r.offset();
        r = Reader(lz4Unpack(r.data(), start, start), g_utf8);
        r.seek(start);
    }
    uint32_t count = r.count(8);
    std::vector<CommonEvent> events(count);
    for (uint32_t i = 0; i < count; i++) {
        CommonEvent& e = events[i];
        if (r.u8() != 0x8E) throw DataError("CommonEvent: bad header");
        e.id = r.i32();
        uint8_t cond = r.u8();
        e.op = cond & 0xF0;
        e.trigger = cond & 0x0F;
        e.left = r.i32();
        e.right = r.i32();
        e.numArgs = r.u8();
        e.strArgs = r.u8();
        e.name = r.str();
        e.commands = readCommands(r);
        r.str();  // description shown before the memo
        r.str();  // memo
        if (r.u8() != 0x8F) throw DataError("CommonEvent: bad argument header");
        uint32_t n = r.count(4);
        for (uint32_t j = 0; j < n; j++) r.str();  // argument names
        n = r.count(1);
        r.skip(n);                                  // argument types
        n = r.count(4);
        for (uint32_t j = 0; j < n; j++) r.strArray();
        n = r.count(4);
        for (uint32_t j = 0; j < n; j++) r.intArray();
        e.argDefaults = r.intArray();
        if (r.u8() != 0x90) throw DataError("CommonEvent: bad label color header");
        r.i32();  // label color
        e.selfVarNames.resize(100);
        for (auto& s : e.selfVarNames) s = r.str();
        if (r.u8() != 0x91) throw DataError("CommonEvent: bad self variable footer");
        r.str();  // footer string
        uint8_t b = r.u8();
        if (b == 0x92) {
            r.str();  // return value description
            e.returnVar = r.i32();
            if (r.u8() != 0x92) throw DataError("CommonEvent: bad footer");
        } else if (b != 0x91) {
            throw DataError("CommonEvent: bad footer");
        }
        e.valid = true;
    }
    g_v35 = false;
    return events;
}

std::vector<TileSet> parseTileSets(Bytes data) {
    bool encrypted = false;
    Reader r = openEnvelope(std::move(data), WolfFileType::TileSetData, {0, 3, 9}, encrypted);
    if (!encrypted && !checkMagic(r, kDatMagic)) throw DataError("TileSetData.dat: bad magic");
    r.setUtf8(g_utf8);
    r.u8();  // version
    uint32_t count = r.count(4);
    std::vector<TileSet> sets(count);
    for (auto& t : sets) {
        t.name = r.str();
        t.baseFile = r.str();
        // 15 autotiles in v2, 31 in v3; the list ends at the 0xFF separator.
        while (!r.eof() && r.at(r.offset()) != 0xFF) t.autotileFiles.push_back(r.str());
        if (r.u8() != 0xFF) throw DataError("TileSetData: bad separator");
        uint32_t n = r.count(1);
        t.tags = r.bytes(n);
        if (r.u8() != 0xFF) throw DataError("TileSetData: bad separator");
        n = r.count(4);
        t.passage.resize(n);
        for (auto& p : t.passage) p = r.i32();
    }
    return sets;
}

Map parseMap(Bytes data) {
    bool encrypted = false;
    g_v35 = false;
    Reader r = openEnvelope(std::move(data), WolfFileType::Map, {0, 0, 0}, encrypted);
    // 10 zero bytes, "WOLFM", 0, then a 4-byte field.
    for (int i = 0; i < 10; i++)
        if (r.u8() != 0) throw DataError("map: bad magic");
    r.expect({'W', 'O', 'L', 'F', 'M', 0}, "map magic");
    r.skip(4);
    Map m;
    m.version = r.i32();
    r.u8();
    if (r.at(r.size() - 1) != 0x66) throw DataError("map: bad terminator");
    r.str();  // memo
    m.tileset = r.i32();
    m.width = r.i32();
    m.height = r.i32();
    uint32_t eventCount = uint32_t(r.i32());
    if (m.version >= 0x67) {
        r.i32();
        m.layers = r.i32();
        g_v35 = true;
    }
    if (m.width <= 0 || m.height <= 0 || m.width > 10000 || m.height > 10000 || m.layers < 1 || m.layers > 16)
        throw DataError("map: bad size");
    size_t tileCount = size_t(m.width) * m.height * m.layers;
    if (r.offset() != r.size() - 1) {
        bool readTiles = true;
        if (r.utf8()) {
            int32_t v = r.i32();
            if (v == -1) readTiles = false;
            else r.seek(r.offset() - 4);
        }
        if (readTiles) {
            if (tileCount * 4 > r.remaining()) throw DataError("map: truncated tiles");
            m.tiles.resize(tileCount);
            for (auto& t : m.tiles) t = r.i32();
        } else {
            m.tiles.assign(tileCount, 0);
        }
        uint8_t indicator;
        while ((indicator = r.u8()) == 0x6F) {
            MapEvent e;
            r.expect({0x39, 0x30, 0x00, 0x00}, "map event header");
            e.id = r.i32();
            e.name = r.str();
            e.x = r.i32();
            e.y = r.i32();
            uint32_t pageCount = uint32_t(r.i32());
            r.expect({0, 0, 0, 0}, "map event padding");
            uint8_t ind;
            while ((ind = r.u8()) == 0x79) {
                EventPage p;
                p.tileId = r.i32();
                p.graphic = r.str();
                p.direction = r.u8();
                p.frame = r.u8();
                p.opacity = r.u8();
                p.blend = r.u8();
                p.trigger = r.u8();
                for (auto& c : p.conditions) {
                    uint8_t b = r.u8();
                    c.op = b & 0xF0;
                    c.used = (b & 0x0F) != 0;
                }
                for (auto& c : p.conditions) c.left = r.i32();
                for (auto& c : p.conditions) c.right = r.i32();
                p.animSpeed = r.u8();
                p.moveSpeed = r.u8();
                p.moveFrequency = r.u8();
                p.moveType = r.u8();
                p.options = r.u8();
                p.routeFlags = r.u8();
                p.route = readRouteCommands(r);
                p.commands = readCommands(r);
                int32_t features = r.i32();
                p.shadow = r.u8();
                p.rangeX = r.u8();
                p.rangeY = r.u8();
                if (features > 3) r.u8();
                if (r.u8() != 0x7A) throw DataError("map: bad page terminator");
                e.pages.push_back(std::move(p));
            }
            if (ind != 0x70) throw DataError("map: bad event terminator");
            if (e.pages.size() != pageCount) throw DataError("map: page count mismatch");
            m.events.push_back(std::move(e));
        }
        if (indicator != 0x66) throw DataError("map: bad terminator");
    } else {
        m.tiles.assign(tileCount, 0);
    }
    if (m.events.size() != eventCount) throw DataError("map: event count mismatch");
    g_v35 = false;
    return m;
}

}  // namespace wolf
