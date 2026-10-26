// DXArchive (.wolf) reader, written for EverPlay from the format as DxLib's archiver writes it
// (versions 5, 6 and 8) and as WOLF RPG Editor 3 encrypts it on top. The WOLF 3 key schedules,
// AES and ChaCha20 are WolfTL's WolfCrypt (MIT); the per-version keys are the ones UberWolf
// (MIT) lists. Entries are read from the file when asked for, so large archives stay on disk.
#include "Archive.hpp"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <functional>

#include "../../third_party/wolfcrypt/WolfCrypt/WolfCrypt.hpp"

namespace wolf {

namespace {

constexpr uint64_t kNone64 = ~uint64_t(0);
constexpr uint32_t kDirectoryAttribute = 0x10;
constexpr uint64_t kMaxSize = uint64_t(1) << 31;  // no single entry or header beyond 2 GB

uint16_t le16(const uint8_t* p) { return uint16_t(p[0] | (p[1] << 8)); }
uint32_t le32(const uint8_t* p) { return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24); }
uint64_t le64(const uint8_t* p) { return uint64_t(le32(p)) | (uint64_t(le32(p + 4)) << 32); }

uint32_t crc32(const uint8_t* data, size_t size) {
    static const auto table = [] {
        std::array<uint32_t, 256> t{};
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) ? (c >> 1) ^ 0xEDB88320u : c >> 1;
            t[i] = c;
        }
        return t;
    }();
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < size; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

// ---- DxLib's LZ compression: [dest size u32][src size u32][key byte] then literals and matches.
bool lzDecode(const Bytes& src, Bytes& out) {
    if (src.size() < 9) return false;
    uint32_t destSize = le32(src.data()), srcSize = le32(src.data() + 4);
    if (destSize > kMaxSize || srcSize < 9 || srcSize > src.size()) return false;
    uint8_t key = src[8];
    out.assign(destSize, 0);
    size_t sp = 9, end = srcSize, dp = 0;
    while (sp < end) {
        uint8_t b = src[sp];
        if (b != key) {
            if (dp >= destSize) return false;
            out[dp++] = b;
            sp++;
            continue;
        }
        if (sp + 1 >= end) return false;
        if (src[sp + 1] == key) {
            if (dp >= destSize) return false;
            out[dp++] = key;
            sp += 2;
            continue;
        }
        uint32_t code = src[sp + 1];
        if (code > key) code--;
        sp += 2;
        uint32_t length = code >> 3;
        if (code & 0x04) {
            if (sp >= end) return false;
            length |= uint32_t(src[sp++]) << 5;
        }
        length += 4;
        uint32_t distance = 0;
        switch (code & 0x03) {
            case 0:
                if (sp + 1 > end) return false;
                distance = src[sp];
                sp += 1;
                break;
            case 1:
                if (sp + 2 > end) return false;
                distance = le16(&src[sp]);
                sp += 2;
                break;
            case 2:
                if (sp + 3 > end) return false;
                distance = le16(&src[sp]) | (uint32_t(src[sp + 2]) << 16);
                sp += 3;
                break;
            default: return false;
        }
        distance++;
        if (distance > dp || dp + length > destSize) return false;
        // Byte by byte: an overlapping copy repeats the last `distance` bytes.
        for (uint32_t i = 0; i < length; i++, dp++) out[dp] = out[dp - distance];
    }
    return dp == destSize;
}

// ---- DxLib's Huffman coding: a bit-packed header with the 256 symbol weights, then the codes.
struct BitReader {
    const uint8_t* data;
    size_t size, byte = 0;
    int bit = 0;
    bool overrun = false;
    uint64_t readMsb(int count) {  // header fields: most significant bit first
        uint64_t v = 0;
        for (int i = 0; i < count; i++) {
            if (byte >= size) { overrun = true; return 0; }
            v = (v << 1) | ((data[byte] >> (7 - bit)) & 1);
            if (++bit == 8) { bit = 0; byte++; }
        }
        return v;
    }
};

bool huffmanDecode(const Bytes& src, Bytes& out, uint64_t limit) {
    BitReader r{src.data(), src.size()};
    uint64_t originalSize = r.readMsb(int(r.readMsb(6) + 1));
    r.readMsb(int(r.readMsb(6) + 1));  // compressed size
    uint16_t weight[256];
    for (int i = 0; i < 256; i++) {
        int bits = int(r.readMsb(3) + 1) * 2;
        bool minus = r.readMsb(1) != 0;
        uint16_t delta = uint16_t(r.readMsb(bits));
        weight[i] = i == 0 ? delta : uint16_t(minus ? weight[i - 1] - delta : weight[i - 1] + delta);
    }
    if (r.overrun || originalSize > limit) return false;
    size_t headBytes = r.byte + (r.bit ? 1 : 0);
    // The tree as the encoder builds it: join the two lightest free nodes (first found wins ties).
    struct Node { uint64_t weight; int parent; int child[2]; };
    std::vector<Node> nodes(511);
    for (int i = 0; i < 511; i++) nodes[size_t(i)] = {uint64_t(i < 256 ? weight[i] : 0), -1, {-1, -1}};
    int count = 256, next = 256;
    while (count > 1) {
        int min1 = -1, min2 = -1;
        for (int index = 0, seen = 0; seen < count; index++) {
            if (nodes[size_t(index)].parent != -1) continue;
            seen++;
            if (min1 == -1 || nodes[size_t(min1)].weight > nodes[size_t(index)].weight) {
                min2 = min1;
                min1 = index;
            } else if (min2 == -1 || nodes[size_t(min2)].weight > nodes[size_t(index)].weight) {
                min2 = index;
            }
        }
        nodes[size_t(next)] = {nodes[size_t(min1)].weight + nodes[size_t(min2)].weight, -1, {min1, min2}};
        nodes[size_t(min1)].parent = next;
        nodes[size_t(min2)].parent = next;
        next++;
        count--;
    }
    // Codes: least significant bit first, from the root (node 510) down.
    out.assign(size_t(originalSize), 0);
    const uint8_t* data = src.data() + headBytes;
    size_t size = src.size() - std::min(src.size(), headBytes), byte = 0;
    int bit = 0;
    for (uint64_t i = 0; i < originalSize; i++) {
        int node = 510;
        while (node > 255) {
            if (byte >= size) return false;
            int b = (data[byte] >> bit) & 1;
            if (++bit == 8) { bit = 0; byte++; }
            node = nodes[size_t(node)].child[b];
        }
        out[size_t(i)] = uint8_t(node);
    }
    return true;
}

// ---- Keys

// DxLib 5/6: a 12-byte key from the key string, scrambled.
std::array<uint8_t, 12> keyV6(const std::vector<uint8_t>& source) {
    std::array<uint8_t, 12> k{};
    if (source.empty()) {
        k.fill(0xAA);
    } else {
        for (size_t i = 0; i < 12; i++) k[i] = source[i % source.size()];
    }
    auto rot = [](uint8_t v, int r) { return uint8_t((v >> r) | (v << (8 - r))); };
    k[0] = uint8_t(~k[0]);
    k[1] = rot(k[1], 4);
    k[2] ^= 0x8A;
    k[3] = uint8_t(~rot(k[3], 4));
    k[4] = uint8_t(~k[4]);
    k[5] ^= 0xAC;
    k[6] = uint8_t(~k[6]);
    k[7] = uint8_t(~rot(k[7], 3));
    k[8] = rot(k[8], 5);
    k[9] ^= 0x7F;
    k[10] = uint8_t(rot(k[10], 4) ^ 0xD6);
    k[11] ^= 0xCC;
    return k;
}

// DxLib 8: a 7-byte key from the CRC-32 of the even and the odd bytes of the key string.
std::array<uint8_t, 7> keyV8(std::string source) {
    if (source.size() < 4) source += "DXBDXARC";  // DxLib's default key string
    std::string even, odd;
    for (size_t i = 0; i < source.size(); i++) (i % 2 ? odd : even) += source[i];
    uint32_t a = crc32(reinterpret_cast<const uint8_t*>(even.data()), even.size());
    uint32_t b = crc32(reinterpret_cast<const uint8_t*>(odd.data()), odd.size());
    return {uint8_t(a), uint8_t(a >> 8), uint8_t(a >> 16), uint8_t(a >> 24), uint8_t(b), uint8_t(b >> 8), uint8_t(b >> 16)};
}

struct KnownKey {
    const char* name;
    int version;            // DXArchive version (5, 6 or 8)
    uint16_t cryptVersion;  // WOLF's encryption version in the version 8 header (0: plain DxLib)
    std::vector<uint8_t> key;
};

std::vector<uint8_t> bytesOf(const char* s) { return std::vector<uint8_t>(s, s + std::strlen(s)); }

const std::vector<KnownKey>& knownKeys() {
    static const std::vector<KnownKey> keys = {
        {"WOLF RPG Editor 2.01", 5, 0, {0x0f, 0x53, 0xe1, 0x3e, 0x04, 0x37, 0x12, 0x17, 0x60, 0x0f, 0x53, 0xe1}},
        {"WOLF RPG Editor 2.10", 5, 0, {0x4c, 0xd9, 0x2a, 0xb7, 0x28, 0x9b, 0xac, 0x07, 0x3e, 0x77, 0xec, 0x4c}},
        {"WOLF RPG Editor 2.20", 6, 0, {0x38, 0x50, 0x40, 0x28, 0x72, 0x4f, 0x21, 0x70, 0x3b, 0x73, 0x35, 0x38}},
        {"WOLF RPG Editor 2.225", 8, 0, bytesOf("WLFRPrO!p(;s5((8P@((UFWlu$#5(=")},
        {"One Way Heroics", 8, 0, bytesOf("nGui9('&1=@3#a")},
        {"One Way Heroics Plus", 8, 0, bytesOf("Ph=X3^]o2A(,1=@3#a")},
        {"WOLF RPG Editor 3.00", 8, 0x12C,
         {0x0F, 0x53, 0xE1, 0x3E, 0x8E, 0xB5, 0x41, 0x91, 0x52, 0x16, 0x55, 0xAE, 0x34, 0xC9, 0x8F, 0x79, 0x59, 0x2F, 0x59, 0x6B,
          0x95, 0x19, 0x9B, 0x1B, 0x35, 0x9A, 0x2F, 0xDE, 0xC9, 0x7C, 0x12, 0x96, 0xC3, 0x14, 0xB5, 0x0F, 0x53, 0xE1, 0x3E, 0x8E}},
        {"WOLF RPG Editor 3.14", 8, 0x13A,
         {0x31, 0xF9, 0x01, 0x36, 0xA3, 0xE3, 0x8D, 0x3C, 0x7B, 0xC3, 0x7D, 0x25, 0xAD, 0x63, 0x28, 0x19, 0x1B, 0xF7, 0x8E, 0x6C,
          0xC4, 0xE5, 0xE2, 0x76, 0x82, 0xEA, 0x4F, 0xED, 0x61, 0xDA, 0xE0, 0x44, 0x5B, 0xB6, 0x46, 0x3B, 0x06, 0xD5, 0xCE, 0xB6,
          0x78, 0x58, 0xD0, 0x7C, 0x82}},
        {"WOLF RPG Editor 3.31", 8, 0x14B,
         {0xCA, 0x08, 0x4C, 0x5D, 0x17, 0x0D, 0xDA, 0xA1, 0xD7, 0x27, 0xC8, 0x41, 0x54, 0x38, 0x82, 0x32, 0x54, 0xB7, 0xF9, 0x46,
          0x8E, 0x13, 0x6B, 0xCA, 0xD0, 0x5C, 0x95, 0x95, 0xE2, 0xDC, 0x03, 0x53, 0x60, 0x9B, 0x4A, 0x38, 0x17, 0xF3, 0x69, 0x59,
          0xA4, 0xC7, 0x9A, 0x43, 0x63, 0xE6, 0x54, 0xAF, 0xDB, 0xBB, 0x43, 0x58}},
        {"WOLF RPG Editor 3.50", 8, 0x15E,
         {0xD2, 0x84, 0xCE, 0x28, 0xCE, 0x88, 0x82, 0xE4, 0x2A, 0x18, 0x2E, 0x4C, 0x06, 0xB4, 0xEA, 0x84, 0x06, 0xB8, 0xC6, 0x88,
          0x5A, 0xA0, 0x9E, 0x7C, 0x56, 0x40, 0xBA, 0x34, 0x52, 0xCC, 0xC6, 0x7C, 0x2E, 0x14, 0x12, 0x68, 0xFE, 0x5C, 0x76, 0x94,
          0x86, 0x78, 0x8E, 0x4C, 0xBE, 0x88, 0x66, 0x9C, 0x1E, 0xE0, 0x8E, 0x6C}},
        // ChaCha20 (WOLF 3 "CC2"): the key and nonce are fixed.
        {"WOLF RPG Editor ChaCha20", 8, 0x64,
         {0xC9, 0x82, 0xF8, 0xB4, 0x2C, 0x93, 0x9E, 0x83, 0x0E, 0xBC, 0xBC, 0x92, 0x68, 0x8D, 0x59, 0xA1, 0x4A, 0x9E, 0x7F, 0xB0,
          0xAC, 0xAF, 0x1D, 0x8F, 0x8E, 0xB8, 0x3B, 0x9E, 0xE8, 0x89, 0xD9, 0xAD, 0xFF, 0xBC, 0x2D, 0xAB, 0x9D, 0x8B, 0x0F, 0xB4,
          0xBB, 0x9A, 0x69, 0x85}},
    };
    return keys;
}

// The first bytes of protected files that WOLF puts before the real data.
const char kAntiUnpack[] = "Extracting data from encrypted files violates the guidelines.";

class DxArchive : public Archive {
public:
    ~DxArchive() override {
        if (file_) std::fclose(file_);
    }

    bool load(const std::string& path, std::string& error) {
        file_ = std::fopen(path.c_str(), "rb");
        if (!file_) { error = "cannot open"; return false; }
        std::fseek(file_, 0, SEEK_END);
        fileSize_ = uint64_t(std::ftell(file_));
        uint8_t head[64] = {};
        if (fileSize_ < 64 || !rawRead(0, head, 64)) { error = "too small"; return false; }
        if (head[0] == 'D' && head[1] == 'X' && le16(head + 2) == 8) return loadV8(head, error);
        // Versions 5 and 6 encrypt the whole header, signature included.
        for (const KnownKey& k : knownKeys()) {
            if (k.version == 8) continue;
            auto key = keyV6(k.key);
            uint8_t h[64];
            std::memcpy(h, head, 64);
            for (int i = 0; i < 64; i++) h[i] ^= key[size_t(i % 12)];
            if (h[0] != 'D' || h[1] != 'X' || le16(h + 2) != uint16_t(k.version)) continue;
            if (loadV56(h, key, k.version)) { keyName_ = k.name; return true; }
        }
        error = "unknown archive format or key";
        return false;
    }

    Bytes read(size_t index) const override {
        const Entry& e = entries_.at(index);
        const Meta& m = meta_.at(index);
        if (e.size == 0) return {};
        uint64_t stored = m.huffSize != kNone64 ? m.huffSize : m.pressSize != kNone64 ? m.pressSize : e.size;
        Bytes raw(static_cast<size_t>(stored));
        if (!dataRead(e.offset, raw.data(), raw.size(), e.size, m)) return {};
        Bytes data;
        uint64_t afterHuffman = m.pressSize != kNone64 ? m.pressSize : e.size;
        if (m.huffSize != kNone64) {
            if (!huffmanDecode(raw, data, afterHuffman)) return {};
            uint64_t part = uint64_t(huffmanKB_) * 1024;
            if (huffmanKB_ != 0xFF && afterHuffman > part * 2) {
                // Only the first and last `part` bytes were Huffman-coded; the middle follows as is.
                Bytes whole(static_cast<size_t>(afterHuffman));
                if (data.size() < part * 2) return {};
                std::memcpy(whole.data(), data.data(), size_t(part));
                std::memcpy(whole.data() + afterHuffman - part, data.data() + part, size_t(part));
                uint64_t middle = afterHuffman - part * 2;
                if (!dataRead(e.offset + m.huffSize, whole.data() + part, size_t(middle), e.size + m.huffSize, m)) return {};
                data = std::move(whole);
            }
        } else {
            data = std::move(raw);
        }
        if (m.pressSize != kNone64) {
            Bytes out;
            if (!lzDecode(data, out)) return {};
            data = std::move(out);
        }
        if (data.size() != e.size) return {};
        if (data.size() >= sizeof kAntiUnpack && std::memcmp(data.data(), kAntiUnpack, sizeof kAntiUnpack) == 0)
            data.erase(data.begin(), data.begin() + sizeof kAntiUnpack);
        return data;
    }

    const std::string& keyName() const { return keyName_; }

private:
    struct Meta {
        uint64_t pressSize = kNone64, huffSize = kNone64;
        std::array<uint8_t, 7> fileKey{};  // DxLib 8 without WOLF's encryption
    };
    enum class Crypt { V6, V8, V8NoKey, Wolf, ChaCha };

    bool rawRead(uint64_t offset, uint8_t* out, size_t size) const {
        if (offset + size > fileSize_) return false;
        if (std::fseek(file_, long(offset), SEEK_SET) != 0) return false;
        return std::fread(out, 1, size, file_) == size;
    }

    // Undoes WOLF 3's whole-file layers (the salted XOR and the AES regions) for physical bytes.
    void unwrapWolf(uint64_t offset, uint8_t* data, size_t size) const {
        uint64_t saltEnd = fileSize_ >= 64 ? fileSize_ - 64 : 0;
        for (size_t i = 0; i < size; i++) {
            uint64_t p = offset + i;
            if (p >= 64 && p < saltEnd) {
                uint8_t& b = data[i];
                if (wolf::crypt::utils::isV35(cryptVersion_)) {
                    uint32_t v1 = uint32_t(p % 256), v2 = uint32_t(p / 256 % 256);
                    b ^= uint8_t(salted_[v1] ^ (7 * v1)) ^ uint8_t(salted_[v2] ^ (7 * (v2 + 256)));
                } else {
                    uint32_t v1 = uint32_t(p % 256), v2 = uint32_t(p / 256 % 256), v3 = uint32_t(p / 0x10000 % 256);
                    b ^= salted_[v1] ^ salted_[v2 + 256] ^ salted_[v3 + 512];
                }
            }
            if (p >= 64 && p < 64 + aesBody_.size()) data[i] ^= aesBody_[size_t(p - 64)];
            if (p >= tableStart_ && p - tableStart_ < aesTables_.size()) data[i] ^= aesTables_[size_t(p - tableStart_)];
        }
    }

    // The archive's own XOR (DxLib key, WOLF key or ChaCha20) at a logical key position.
    void keyConv(uint8_t* data, size_t size, uint64_t position, const std::array<uint8_t, 7>* fileKey) const {
        switch (crypt_) {
            case Crypt::V6:
                for (size_t i = 0; i < size; i++) data[i] ^= key6_[size_t((position + i) % 12)];
                break;
            case Crypt::V8:
                if (fileKey)
                    for (size_t i = 0; i < size; i++) data[i] ^= (*fileKey)[size_t((position + i) % 7)];
                break;
            case Crypt::V8NoKey: break;
            case Crypt::Wolf:
                wolf::crypt::wolfCrypt(special_.data(), data, int64_t(position), int64_t(position + size), false, cryptVersion_);
                break;
            case Crypt::ChaCha: {
                uint32_t state[16] = {}, stream[16] = {};
                wolf::crypt::chacha20::initBlock(state, chachaKey_.data(), chachaNonce_.data());
                wolf::crypt::chacha20::execute(state, stream, uint32_t(position), data, size);
                break;
            }
        }
    }

    bool dataRead(uint64_t offset, uint8_t* out, size_t size, uint64_t keyPosition, const Meta& m) const {
        if (!rawRead(offset, out, size)) return false;
        if (crypt_ == Crypt::Wolf) unwrapWolf(offset, out, size);
        keyConv(out, size, keyPosition, &m.fileKey);
        return true;
    }

    // ---- Versions 5 and 6 (WOLF RPG Editor 2.0x-2.2x)
    bool loadV56(const uint8_t* h, const std::array<uint8_t, 12>& key, int version) {
        crypt_ = Crypt::V6;
        key6_ = key;
        uint64_t headSize = le32(h + 4), dataStart, nameTable, fileTable, dirTable;
        if (version == 5) {
            dataStart = le32(h + 8); nameTable = le32(h + 12); fileTable = le32(h + 16); dirTable = le32(h + 20);
            codePage_ = le32(h + 24);
        } else {
            dataStart = le64(h + 8); nameTable = le64(h + 16); fileTable = le64(h + 24); dirTable = le64(h + 32);
            codePage_ = uint32_t(le64(h + 40));
        }
        if (headSize > kMaxSize || nameTable + headSize > fileSize_) return false;
        Bytes table(static_cast<size_t>(headSize));
        if (!rawRead(nameTable, table.data(), table.size())) return false;
        keyConv(table.data(), table.size(), 0, nullptr);
        Layout l;
        l.wide = version == 6;
        l.fileHeadSize = version == 5 ? 44 : 64;
        l.dirSize = version == 5 ? 16 : 32;
        return buildEntries(table, fileTable, dirTable, dataStart, l, std::string());
    }

    // ---- Version 8 (WOLF RPG Editor 2.225 and 3.x)
    bool loadV8(const uint8_t* plainHead, std::string& error) {
        uint32_t flags = le32(plainHead + 44);
        cryptVersion_ = uint16_t(flags >> 16);
        if (cryptVersion_ >= 1000) {
            error = "WOLF RPG Editor Pro archive (needs the game's own key, not supported yet)";
            return false;
        }
        for (const KnownKey& k : knownKeys()) {
            if (k.version != 8 || k.cryptVersion != cryptVersion_) continue;
            if (loadV8With(plainHead, k)) { keyName_ = k.name; return true; }
        }
        // An unknown key string on plain DxLib: the default one.
        if (cryptVersion_ == 0 && loadV8With(plainHead, {"DxLib default", 8, 0, bytesOf("DXBDXARC")})) {
            keyName_ = "DxLib default";
            return true;
        }
        error = "unknown archive key (encryption version " + std::to_string(cryptVersion_) + ")";
        return false;
    }

    bool loadV8With(const uint8_t* plainHead, const KnownKey& k) {
        uint8_t h[64];
        std::memcpy(h, plainHead, 64);
        std::string keyString(k.key.begin(), k.key.end());
        if (keyString.size() > 63) keyString.resize(63);
        bool newCrypt = (cryptVersion_ >= 331 && cryptVersion_ < 1000) || cryptVersion_ >= 1010;
        aesBody_.clear();
        aesTables_.clear();
        if (newCrypt) {
            crypt_ = Crypt::Wolf;
            const uint8_t* password = plainHead + 49;  // the header's reserved bytes
            uint8_t pw[15];
            std::memcpy(pw, password, 15);
            wolf::crypt::cryptAddresses(h, pw, cryptVersion_);
            // The salted key of the whole-file XOR (initWolfCrypt's "other" pass), without applying it.
            salted_.assign(768, 0);
            {
                std::vector<uint8_t> scratch(1, 0);
                wolf::crypt::initWolfCrypt(cryptVersion_, pw, salted_.data(), nullptr, scratch.data(), 0, 0, true,
                                           keyString.c_str());
            }
            uint64_t size = fileSize_;
            if (size < 64 + 16) return false;
            uint64_t bodySize = std::min<uint64_t>(0x400, size - 64);
            if (wolf::crypt::utils::isV35(cryptVersion_)) {
                uint32_t seed = uint32_t(pw[2] * pw[4] + pw[12]);
                if (!seed) seed = 1;
                wolf::crypt::xorshift32(seed);
                if (size >= wolf::crypt::xorshift32() % 500 + 800) wolf::crypt::xorshift32();
                bodySize = size - 64;
                if (bodySize >= wolf::crypt::xorshift32() % 500 + 800) bodySize = wolf::crypt::xorshift32() % 500 + 800;
            }
            tableStart_ = le64(h + 16);
            if (tableStart_ > size) return false;
            uint8_t roundKey[wolf::crypt::aes::ROUND_KEY_SIZE] = {};
            wolf::crypt::aes::initAES128(roundKey, pw, nullptr, cryptVersion_);
            aesBody_.assign(size_t(bodySize), 0);
            wolf::crypt::aes::aesCtrXCrypt(aesBody_.data(), roundKey, aesBody_.size());
            aesTables_.assign(size_t(size - tableStart_), 0);
            wolf::crypt::aes::aesCtrXCrypt(aesTables_.data(), roundKey, aesTables_.size());
            special_.assign(768, 0);
            wolf::crypt::initWolfCrypt(cryptVersion_, pw, special_.data(), nullptr);
        } else if (cryptVersion_ == 0x64) {
            crypt_ = Crypt::ChaCha;
            std::copy(k.key.begin(), k.key.begin() + 32, chachaKey_.begin());
            std::copy(k.key.begin() + 32, k.key.begin() + 44, chachaNonce_.begin());
        } else {
            crypt_ = (le32(h + 44) & 0x01) ? Crypt::V8NoKey : Crypt::V8;
        }
        uint64_t headSize = le32(h + 4), dataStart = le64(h + 8), nameTable = le64(h + 16);
        uint64_t fileTable = le64(h + 24), dirTable = le64(h + 32);
        codePage_ = le32(h + 40);
        uint32_t flags = le32(h + 44);
        huffmanKB_ = h[48];
        if (headSize > kMaxSize || nameTable > fileSize_ || dataStart > fileSize_) return false;
        globalKey_ = keyV8(keyString);
        Bytes table;
        Bytes stored(static_cast<size_t>(fileSize_ - nameTable));
        if (!rawRead(nameTable, stored.data(), stored.size())) return false;
        if (crypt_ == Crypt::Wolf) unwrapWolf(nameTable, stored.data(), stored.size());
        if (flags & 0x02) {  // header not compressed
            if (stored.size() < headSize) return false;
            stored.resize(size_t(headSize));
            keyConv(stored.data(), stored.size(), 0, &globalKey_);
            table = std::move(stored);
        } else {
            keyConv(stored.data(), stored.size(), 0, &globalKey_);
            Bytes lz;
            if (!huffmanDecode(stored, lz, headSize * 2 + 1024)) return false;
            if (!lzDecode(lz, table) || table.size() != headSize) return false;
        }
        Layout l;
        l.wide = true;
        l.fileHeadSize = 72;
        l.dirSize = 32;
        l.huffman = true;
        return buildEntries(table, fileTable, dirTable, dataStart, l, keyString);
    }

    struct Layout {
        bool wide = true, huffman = false;
        size_t fileHeadSize = 72, dirSize = 32;
    };

    bool buildEntries(const Bytes& table, uint64_t fileTable, uint64_t dirTable, uint64_t dataStart, const Layout& l,
                      const std::string& keyString) {
        auto field = [&](uint64_t at, int index) -> uint64_t {
            size_t width = l.wide ? 8 : 4;
            uint64_t pos = at + uint64_t(index) * width;
            if (pos + width > table.size()) return kNone64;
            return l.wide ? le64(&table[size_t(pos)]) : le32(&table[size_t(pos)]);
        };
        // A name entry: [pack count u16][parity u16][upper-case name][original name], packs of 4 bytes.
        auto names = [&](uint64_t at, std::string& upper, std::string& original) -> bool {
            if (at + 4 > table.size()) return false;
            size_t packs = le16(&table[size_t(at)]);
            size_t start = size_t(at) + 4;
            if (start + packs * 8 > table.size()) return false;
            auto cstr = [&](size_t from, size_t max) {
                size_t n = 0;
                while (n < max && table[from + n]) n++;
                return std::string(reinterpret_cast<const char*>(&table[from]), n);
            };
            upper = cstr(start, packs * 4);
            original = cstr(start + packs * 4, packs * 4);
            return true;
        };
        // Field offsets of a file head: name, attributes, 3 times (always 8 bytes each), address, size, packed, huffman.
        auto fileField = [&](uint64_t head, int which) -> uint64_t {
            size_t w = l.wide ? 8 : 4;
            size_t offsets[] = {0, w, w * 2 + 24, w * 3 + 24, w * 4 + 24, w * 5 + 24};
            uint64_t pos = head + offsets[which];
            if (pos + w > table.size()) return kNone64;
            uint64_t v = w == 8 ? le64(&table[size_t(pos)]) : le32(&table[size_t(pos)]);
            if (w == 4 && v == 0xFFFFFFFFu) v = kNone64;
            return v;
        };
        int visited = 0;
        std::function<bool(uint64_t, const std::string&, const std::vector<std::string>&)> walk =
            [&](uint64_t dirAt, const std::string& prefix, const std::vector<std::string>& upperDirs) -> bool {
            if (++visited > 100000) return false;
            uint64_t at = dirTable + dirAt;
            uint64_t count = field(at, 2), headAt = field(at, 3);
            if (count == kNone64 || count > 1000000) return false;
            for (uint64_t i = 0; i < count; i++) {
                uint64_t fh = fileTable + headAt + i * l.fileHeadSize;
                if (fh + l.fileHeadSize > table.size()) return false;
                std::string upper, original;
                if (!names(fileField(fh, 0), upper, original)) return false;
                std::string name = codePage_ == 65001 ? original : sjisToUtf8(reinterpret_cast<const uint8_t*>(original.data()), original.size());
                uint64_t attributes = fileField(fh, 1);
                uint64_t address = fileField(fh, 2);
                if (attributes & kDirectoryAttribute) {
                    std::vector<std::string> dirs = upperDirs;
                    dirs.insert(dirs.begin(), upper);
                    if (!walk(address, prefix + name + "/", dirs)) return false;
                    continue;
                }
                Entry e;
                e.path = prefix + name;
                e.offset = dataStart + address;
                e.size = fileField(fh, 3);
                Meta m;
                m.pressSize = fileField(fh, 4);
                m.huffSize = l.huffman ? fileField(fh, 5) : kNone64;
                if (e.size > kMaxSize) return false;
                uint64_t stored = m.huffSize != kNone64 ? m.huffSize : m.pressSize != kNone64 ? m.pressSize : e.size;
                if (e.offset + stored > fileSize_) return false;
                e.compressed = m.pressSize != kNone64;
                e.huffman = m.huffSize != kNone64;
                e.packedSize = stored;
                if (crypt_ == Crypt::V8) {
                    // Each file has its own key: the key string, its name and its folders upwards.
                    std::string s = keyString + upper;
                    for (const auto& d : upperDirs) s += d;
                    m.fileKey = keyV8(s);
                }
                entries_.push_back(e);
                meta_.push_back(m);
            }
            return true;
        };
        entries_.clear();
        meta_.clear();
        if (!walk(0, "", {})) {
            entries_.clear();
            meta_.clear();
            return false;
        }
        return true;
    }

    FILE* file_ = nullptr;
    uint64_t fileSize_ = 0;
    Crypt crypt_ = Crypt::V8NoKey;
    uint16_t cryptVersion_ = 0;
    uint32_t codePage_ = 932;
    uint8_t huffmanKB_ = 0xFF;
    std::array<uint8_t, 12> key6_{};
    std::array<uint8_t, 7> globalKey_{};
    std::array<uint8_t, 32> chachaKey_{};
    std::array<uint8_t, 12> chachaNonce_{};
    std::vector<uint8_t> salted_, special_, aesBody_, aesTables_;
    uint64_t tableStart_ = 0;
    std::vector<Meta> meta_;
    std::string keyName_;
};

}  // namespace

std::unique_ptr<Archive> Archive::open(const std::string& path, std::string& error) {
    auto archive = std::make_unique<DxArchive>();
    if (!archive->load(path, error)) return nullptr;
    return archive;
}

}  // namespace wolf
