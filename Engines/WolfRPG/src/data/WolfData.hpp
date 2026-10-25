// Readers for WOLF RPG Editor (v2.x and v3.x) game data: Game.dat, the three databases
// (.project + .dat), CommonEvent.dat, TileSetData.dat and the .mps maps.
//
// The binary layouts follow WolfTL (github.com/Sinflower/WolfTL, MIT) and WodiLib
// (github.com/kameske/WodiLib, MIT); see ThirdPartyNotices. Strings are converted to UTF-8.
#pragma once

#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace wolf {

struct DataError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

using Bytes = std::vector<uint8_t>;

// Little-endian reader over a byte buffer with WOLF's length-prefixed strings.
class Reader {
public:
    explicit Reader(Bytes data, bool utf8 = false) : data_(std::move(data)), utf8_(utf8) {}
    size_t size() const { return data_.size(); }
    size_t offset() const { return pos_; }
    size_t remaining() const { return pos_ < data_.size() ? data_.size() - pos_ : 0; }
    bool eof() const { return pos_ >= data_.size(); }
    void seek(size_t pos) { pos_ = pos; }
    void skip(size_t n) { need(n); pos_ += n; }
    uint8_t at(size_t pos) const { return pos < data_.size() ? data_[pos] : 0; }
    const Bytes& data() const { return data_; }
    Bytes& mutableData() { return data_; }
    bool utf8() const { return utf8_; }
    void setUtf8(bool v) { utf8_ = v; }

    uint8_t u8() { need(1); return data_[pos_++]; }
    uint16_t u16() { need(2); uint16_t v = data_[pos_] | (data_[pos_ + 1] << 8); pos_ += 2; return v; }
    int32_t i32() {
        need(4);
        uint32_t v = uint32_t(data_[pos_]) | (uint32_t(data_[pos_ + 1]) << 8) | (uint32_t(data_[pos_ + 2]) << 16) |
                     (uint32_t(data_[pos_ + 3]) << 24);
        pos_ += 4;
        return int32_t(v);
    }
    Bytes bytes(size_t n) { need(n); Bytes b(data_.begin() + pos_, data_.begin() + pos_ + n); pos_ += n; return b; }
    std::string str();
    Bytes byteArray() { uint32_t n = uint32_t(i32()); return bytes(n); }
    std::vector<int32_t> intArray() {
        uint32_t n = count(4);
        std::vector<int32_t> v(n);
        for (auto& x : v) x = i32();
        return v;
    }
    std::vector<std::string> strArray() {
        uint32_t n = count(4);
        std::vector<std::string> v(n);
        for (auto& s : v) s = str();
        return v;
    }
    // A count of elements of at least `minSize` bytes each, checked against what is left.
    uint32_t count(size_t minSize = 1) {
        int32_t n = i32();
        if (n < 0 || size_t(n) * minSize > remaining()) throw DataError("bad element count " + std::to_string(n));
        return uint32_t(n);
    }
    void expect(std::initializer_list<uint8_t> magic, const char* what);

private:
    void need(size_t n) const {
        if (pos_ + n > data_.size()) throw DataError("unexpected end of data at offset " + std::to_string(pos_));
    }
    Bytes data_;
    size_t pos_ = 0;
    bool utf8_ = false;
};

// Shift-JIS (CP932) to UTF-8; invalid bytes become U+FFFD.
std::string sjisToUtf8(const uint8_t* data, size_t size);

// ---------------------------------------------------------------------------------------------
// Event commands

struct RouteCommand {
    uint8_t id = 0;
    std::vector<int32_t> args;
};

struct MoveRoute {
    uint8_t target[5] = {};  // the Move command's 5 "unknown" bytes (WodiLib: target is args[0])
    uint8_t flags = 0;       // 0x01 repeat, 0x02 skip if blocked, 0x04 wait until done
    std::vector<RouteCommand> commands;
};

struct Command {
    int32_t code = 0;
    std::vector<int32_t> args;
    std::vector<std::string> strings;
    uint8_t indent = 0;
    std::shared_ptr<MoveRoute> route;  // Move (201) commands only

    int32_t arg(size_t i, int32_t fallback = 0) const { return i < args.size() ? args[i] : fallback; }
    const std::string& string(size_t i) const {
        static const std::string empty;
        return i < strings.size() ? strings[i] : empty;
    }
};
using CommandList = std::vector<Command>;

// ---------------------------------------------------------------------------------------------
// Maps

struct BootCondition {
    uint8_t op = 0;  // high nibble of the operator byte (0x00 >, 0x10 >=, 0x20 ==, 0x30 <=, 0x40 <, 0x50 !=, 0x60 &)
    bool used = false;
    int32_t left = 0;
    int32_t right = 0;
};

struct EventPage {
    int32_t tileId = -1;  // -1: the page shows a character sheet, else a tile of the map's tileset
    std::string graphic;
    uint8_t direction = 2, frame = 1, opacity = 255, blend = 0;
    uint8_t trigger = 0;  // 0 action key, 1 auto, 2 parallel, 3 hero touch, 4 event touch, 5 none
    BootCondition conditions[4];
    uint8_t animSpeed = 0, moveSpeed = 0, moveFrequency = 0, moveType = 0;
    uint8_t options = 0;  // 0x01 wait-animation, 0x02 pass-through, 0x04 above hero, 0x08 no direction anim,
                          // 0x10 fixed direction, 0x20 slip/sliding, 0x40 half-step/"same priority"?
    uint8_t routeFlags = 0;
    std::vector<RouteCommand> route;
    CommandList commands;
    uint8_t shadow = 0, rangeX = 0, rangeY = 0;
};

struct MapEvent {
    int32_t id = 0;
    std::string name;
    int32_t x = 0, y = 0;
    std::vector<EventPage> pages;
};

struct Map {
    int32_t version = 0;
    int32_t tileset = 0;
    int32_t width = 0, height = 0;
    int32_t layers = 3;
    std::vector<int32_t> tiles;  // [layer][x][y], column-major like the file
    std::vector<MapEvent> events;

    int32_t tile(int layer, int x, int y) const {
        if (layer < 0 || layer >= layers || x < 0 || y < 0 || x >= width || y >= height) return 0;
        size_t i = (size_t(layer) * width + x) * height + y;
        return i < tiles.size() ? tiles[i] : 0;
    }
    void setTile(int layer, int x, int y, int32_t v) {
        if (layer < 0 || layer >= layers || x < 0 || y < 0 || x >= width || y >= height) return;
        size_t i = (size_t(layer) * width + x) * height + y;
        if (i < tiles.size()) tiles[i] = v;
    }
};

// ---------------------------------------------------------------------------------------------
// Common events

struct CommonEvent {
    int32_t id = 0;
    uint8_t op = 0;       // boot condition operator (high nibble)
    uint8_t trigger = 0;  // 0 call only, 1 auto, 2 parallel, 3 parallel always, 4 none
    int32_t left = 0, right = 0;
    uint8_t numArgs = 0, strArgs = 0;
    std::string name;
    CommandList commands;
    std::vector<int32_t> argDefaults;  // initial values of the number arguments
    std::vector<std::string> selfVarNames;
    int32_t returnVar = -1;            // self variable returned to the caller (-1: none)
    bool valid = false;
};

// ---------------------------------------------------------------------------------------------
// Databases (UDB = DataBase, CDB = CDataBase, SDB = SysDatabase)

struct DBField {
    std::string name;
    bool isString = false;
    int32_t index = 0;  // index into the ints or strings of a record
    uint8_t type = 0;
    int32_t defaultValue = 0;
    std::vector<std::string> stringArgs;
    std::vector<int32_t> args;
};

struct DBRecord {
    std::string name;
    std::vector<int32_t> ints;
    std::vector<std::string> strings;
};

struct DBType {
    std::string name;
    std::string description;
    int32_t idMode = 0;  // how data names are set (0x1D4C0: from the first string field)
    std::vector<DBField> fields;
    std::vector<DBRecord> records;
};

struct Database {
    std::vector<DBType> types;
};

// ---------------------------------------------------------------------------------------------
// Tilesets

struct TileSet {
    std::string name;
    std::string baseFile;
    std::vector<std::string> autotileFiles;  // 15 names (v2) or 31 (v3)
    std::vector<uint8_t> tags;
    std::vector<int32_t> passage;            // per tile: autotiles 0..15 first, then base tiles
};

// ---------------------------------------------------------------------------------------------
// Game.dat

struct GameDat {
    bool utf8 = false;
    std::vector<uint8_t> u8;   // basic settings (tile size, FPS, character sheet layout, …)
    std::vector<std::string> strings;
    std::vector<uint16_t> u16; // screen size, editor version, …
    std::string title() const { return strings.size() > 0 ? strings[0] : ""; }
    std::string font() const { return strings.size() > 3 ? strings[3] : ""; }
    std::string subFont(int i) const { return strings.size() > size_t(4 + i) ? strings[4 + i] : ""; }
    std::string heroGraphic() const { return strings.size() > 7 ? strings[7] : ""; }
    int setting(size_t i) const { return i < u8.size() ? u8[i] : 0; }
    int setting16(size_t i) const { return i < u16.size() ? u16[i] : 0; }
};

// ---------------------------------------------------------------------------------------------
// Parsing entry points. Each takes the raw file contents.

GameDat parseGameDat(Bytes data);
Database parseDatabase(Bytes project, Bytes dat);
std::vector<CommonEvent> parseCommonEvents(Bytes data);
std::vector<TileSet> parseTileSets(Bytes data);
Map parseMap(Bytes data);

// The text encoding detected from the last parsed file with a UTF-8 marker (v3 games).
bool lastFileWasUtf8();

}  // namespace wolf
