// Saves: EverPlay's own format (WOLF's .sav files are not readable), one file per slot in the
// folder EverPlay passes in, which is On My iPhone › EverPlay › Saves › <game>.
#include <cstdio>
#include <cstring>
#include <sys/stat.h>

#include "Game.hpp"

namespace wolf {

namespace {

constexpr uint32_t kMagic = 0x57455053;  // "SPEW"
constexpr uint32_t kVersion = 1;

struct Writer {
    std::vector<uint8_t> out;
    void u32(uint32_t v) { for (int i = 0; i < 4; i++) out.push_back(uint8_t(v >> (i * 8))); }
    void i32(int32_t v) { u32(uint32_t(v)); }
    void f64(double v) { uint64_t b; std::memcpy(&b, &v, 8); for (int i = 0; i < 8; i++) out.push_back(uint8_t(b >> (i * 8))); }
    void str(const std::string& s) { u32(uint32_t(s.size())); out.insert(out.end(), s.begin(), s.end()); }
    void ints(const std::vector<int32_t>& v) { u32(uint32_t(v.size())); for (auto x : v) i32(x); }
    void strs(const std::vector<std::string>& v) { u32(uint32_t(v.size())); for (auto& x : v) str(x); }
};

struct ReaderB {
    const std::vector<uint8_t>& in;
    size_t pos = 0;
    bool ok = true;
    explicit ReaderB(const std::vector<uint8_t>& d) : in(d) {}
    uint32_t u32() {
        if (pos + 4 > in.size()) { ok = false; return 0; }
        uint32_t v = 0;
        for (int i = 0; i < 4; i++) v |= uint32_t(in[pos + i]) << (i * 8);
        pos += 4;
        return v;
    }
    int32_t i32() { return int32_t(u32()); }
    double f64() {
        if (pos + 8 > in.size()) { ok = false; return 0; }
        uint64_t b = 0;
        for (int i = 0; i < 8; i++) b |= uint64_t(in[pos + i]) << (i * 8);
        pos += 8;
        double v;
        std::memcpy(&v, &b, 8);
        return v;
    }
    std::string str() {
        uint32_t n = u32();
        if (!ok || pos + n > in.size()) { ok = false; return {}; }
        std::string s(in.begin() + long(pos), in.begin() + long(pos + n));
        pos += n;
        return s;
    }
    std::vector<int32_t> ints() {
        uint32_t n = u32();
        if (!ok || n > (in.size() - pos) / 4) { ok = false; return {}; }
        std::vector<int32_t> v(n);
        for (auto& x : v) x = i32();
        return v;
    }
    std::vector<std::string> strs() {
        uint32_t n = u32();
        if (!ok || n > in.size() - pos) { ok = false; return {}; }
        std::vector<std::string> v(n);
        for (auto& x : v) x = str();
        return v;
    }
};

void writeChar(Writer& w, const Character& c) {
    w.i32(c.eventId); w.i32(c.px); w.i32(c.py); w.i32(c.direction); w.i32(c.pattern);
    w.str(c.graphic); w.i32(c.tileId); w.i32(c.opacity); w.i32(c.blend); w.i32(c.height);
    w.i32(c.moveSpeed); w.i32(c.moveFrequency); w.i32(c.animSpeed);
    w.u32((c.erased ? 1 : 0) | (c.through ? 2 : 0) | (c.fixedDir ? 4 : 0) | (c.halfStep ? 8 : 0));
    for (int i = 0; i < 10; i++) w.i32(c.selfVars[i]);
}

void readChar(ReaderB& r, Character& c) {
    c.eventId = r.i32(); c.px = r.i32(); c.py = r.i32(); c.direction = r.i32(); c.pattern = r.i32();
    c.graphic = r.str(); c.tileId = r.i32(); c.opacity = r.i32(); c.blend = r.i32(); c.height = r.i32();
    c.moveSpeed = r.i32(); c.moveFrequency = r.i32(); c.animSpeed = r.i32();
    uint32_t flags = r.u32();
    c.erased = flags & 1; c.through = flags & 2; c.fixedDir = flags & 4; c.halfStep = flags & 8;
    for (int i = 0; i < 10; i++) c.selfVars[i] = r.i32();
}

void writeDb(Writer& w, const Database& db) {
    w.u32(uint32_t(db.types.size()));
    for (const auto& t : db.types) {
        w.u32(uint32_t(t.records.size()));
        for (const auto& r : t.records) { w.str(r.name); w.ints(r.ints); w.strs(r.strings); }
    }
}

void readDb(ReaderB& r, Database& db) {
    uint32_t types = r.u32();
    for (uint32_t i = 0; i < types && r.ok; i++) {
        uint32_t n = r.u32();
        std::vector<DBRecord> records(n);
        for (auto& rec : records) { rec.name = r.str(); rec.ints = r.ints(); rec.strings = r.strs(); }
        if (i < db.types.size() && r.ok) db.types[i].records = std::move(records);
    }
}

}  // namespace

std::string Game::savePath(int slot) const {
    char name[64];
    std::snprintf(name, sizeof name, "/Save%02d.everplay.sav", slot);
    return saveFolder_ + name;
}

std::vector<uint8_t> Game::serialize() {
    // The current map's event self variables go with the map table.
    if (mapId_ >= 0)
        for (const auto& e : events_)
            for (int i = 0; i < 10; i++) mapSelf_[mapId_][e.eventId][size_t(i)] = e.selfVars[i];
    Writer w;
    w.u32(kMagic);
    w.u32(kVersion);
    w.str(project_->game.title());
    w.i32(mapId_);
    writeChar(w, hero_);
    w.u32(uint32_t(events_.size()));
    for (const auto& e : events_) writeChar(w, e);
    w.ints(vars_);
    for (int s = 1; s <= 9; s++) w.ints(spare_[size_t(s)]);
    w.strs(strs_);
    w.ints(sys_);
    w.strs(sysStr_);
    w.u32(uint32_t(commonSelf_.size()));
    for (const auto& [id, v] : commonSelf_) {
        w.i32(id);
        for (auto x : v) w.i32(x);
    }
    w.u32(uint32_t(commonSelfStr_.size()));
    for (const auto& [id, v] : commonSelfStr_) {
        w.i32(id);
        for (auto& x : v) w.str(x);
    }
    w.u32(uint32_t(mapSelf_.size()));
    for (const auto& [map, events] : mapSelf_) {
        w.i32(map);
        w.u32(uint32_t(events.size()));
        for (const auto& [ev, v] : events) {
            w.i32(ev);
            for (auto x : v) w.i32(x);
        }
    }
    writeDb(w, project_->cdb);
    writeDb(w, project_->udb);
    w.str(audioState_.bgmFile); w.i32(audioState_.bgmId); w.i32(audioState_.bgmVolume); w.i32(audioState_.bgmPitch);
    w.str(audioState_.bgsFile); w.i32(audioState_.bgsId); w.i32(audioState_.bgsVolume); w.i32(audioState_.bgsPitch);
    w.f64(fx_.r); w.f64(fx_.g); w.f64(fx_.b);
    w.u32(uint32_t(playFrames_ & 0xFFFFFFFF));
    w.u32(uint32_t(playFrames_ >> 32));
    // Pictures
    w.u32(uint32_t(pictures_.size()));
    for (const auto& [n, p] : pictures_) {
        w.i32(n); w.i32(p.type); w.str(p.file); w.str(p.text);
        w.i32(p.divW); w.i32(p.divH); w.i32(p.pattern); w.i32(p.anchor); w.i32(p.blend);
        w.u32((p.scroll ? 1 : 0) | (p.freePos ? 2 : 0));
        w.i32(p.windowW); w.i32(p.windowH);
        const auto& s = p.moveFrames > 0 ? p.to : p.cur;
        w.f64(s.x); w.f64(s.y); w.f64(s.zoomW); w.f64(s.zoomH); w.f64(s.angle); w.f64(s.opacity);
        w.f64(s.r); w.f64(s.g); w.f64(s.b);
        for (double c : s.corners) w.f64(c);
    }
    return w.out;
}

bool Game::deserialize(const std::vector<uint8_t>& data) {
    ReaderB r(data);
    if (r.u32() != kMagic || r.u32() != kVersion) return false;
    r.str();
    int map = r.i32();
    Character hero;
    readChar(r, hero);
    uint32_t n = r.u32();
    std::vector<Character> evs(r.ok ? std::min<uint32_t>(n, 100000) : 0);
    for (auto& e : evs) readChar(r, e);
    auto vars = r.ints();
    std::array<std::vector<int32_t>, 10> spare;
    for (int s = 1; s <= 9; s++) spare[size_t(s)] = r.ints();
    auto strs = r.strs();
    auto sys = r.ints();
    auto sysStr = r.strs();
    std::map<int, std::array<int32_t, 100>> cself;
    uint32_t cn = r.u32();
    for (uint32_t i = 0; i < cn && r.ok; i++) {
        int id = r.i32();
        auto& v = cself[id];
        for (auto& x : v) x = r.i32();
    }
    std::map<int, std::array<std::string, 5>> cselfStr;
    cn = r.u32();
    for (uint32_t i = 0; i < cn && r.ok; i++) {
        int id = r.i32();
        auto& v = cselfStr[id];
        for (auto& x : v) x = r.str();
    }
    std::map<int, std::map<int, std::array<int, 10>>> mapSelf;
    uint32_t mn = r.u32();
    for (uint32_t i = 0; i < mn && r.ok; i++) {
        int m = r.i32();
        uint32_t en = r.u32();
        for (uint32_t k = 0; k < en && r.ok; k++) {
            int ev = r.i32();
            auto& v = mapSelf[m][ev];
            for (auto& x : v) x = r.i32();
        }
    }
    if (!r.ok) return false;
    Database cdb = project_->cdb, udb = project_->udb;
    readDb(r, cdb);
    readDb(r, udb);
    AudioState audio;
    audio.bgmFile = r.str(); audio.bgmId = r.i32(); audio.bgmVolume = r.i32(); audio.bgmPitch = r.i32();
    audio.bgsFile = r.str(); audio.bgsId = r.i32(); audio.bgsVolume = r.i32(); audio.bgsPitch = r.i32();
    double cr = r.f64(), cg = r.f64(), cb = r.f64();
    uint64_t frames = r.u32();
    frames |= uint64_t(r.u32()) << 32;
    std::map<int, Picture> pics;
    uint32_t pn = r.u32();
    for (uint32_t i = 0; i < pn && r.ok; i++) {
        int num = r.i32();
        Picture p;
        p.used = true;
        p.type = r.i32(); p.file = r.str(); p.text = r.str();
        p.divW = r.i32(); p.divH = r.i32(); p.pattern = r.i32(); p.anchor = r.i32(); p.blend = r.i32();
        uint32_t fl = r.u32();
        p.scroll = fl & 1; p.freePos = fl & 2;
        p.windowW = r.i32(); p.windowH = r.i32();
        auto& s = p.cur;
        s.x = r.f64(); s.y = r.f64(); s.zoomW = r.f64(); s.zoomH = r.f64(); s.angle = r.f64(); s.opacity = r.f64();
        s.r = r.f64(); s.g = r.f64(); s.b = r.f64();
        for (double& c : s.corners) c = r.f64();
        p.from = p.to = p.cur;
        pics[num] = std::move(p);
    }
    if (!r.ok) return false;

    // Everything read: apply.
    contexts_.clear();
    commonContexts_.clear();
    mapParallel_.clear();
    reservedCommons_.clear();
    msg_ = MessageWindow();
    vars_ = std::move(vars);
    if (vars_.size() < 10000) vars_.resize(10000, 0);
    spare_ = std::move(spare);
    strs_ = std::move(strs);
    if (strs_.size() < 1000) strs_.resize(1000);
    sys_ = std::move(sys);
    if (sys_.size() < 1000) sys_.resize(1000, 0);
    sysStr_ = std::move(sysStr);
    if (sysStr_.size() < 200) sysStr_.resize(200);
    commonSelf_ = std::move(cself);
    commonSelfStr_ = std::move(cselfStr);
    mapSelf_ = std::move(mapSelf);
    project_->cdb = std::move(cdb);
    project_->udb = std::move(udb);
    playFrames_ = frames;
    fx_ = ScreenEffects();
    fx_.r = cr; fx_.g = cg; fx_.b = cb;
    mapId_ = -1;
    hero_ = hero;
    hero_.realX = hero_.px * tileSize_ / 2.0;
    hero_.realY = hero_.py * tileSize_ / 2.0;
    hero_.moving = false;
    hero_.routeDone = true;
    hero_.routeFromCommand = false;
    loadMap(map);
    // Event positions and states as saved.
    for (const auto& e : evs) {
        Character* ch = eventChar(e.eventId);
        if (!ch) continue;
        ch->px = e.px; ch->py = e.py; ch->direction = e.direction; ch->erased = e.erased;
        ch->realX = e.px * tileSize_ / 2.0;
        ch->realY = e.py * tileSize_ / 2.0;
        for (int i = 0; i < 10; i++) ch->selfVars[i] = e.selfVars[i];
    }
    party_.clear();
    refreshPages();
    // Pictures: textures again.
    pictures_ = std::move(pics);
    for (auto& [num, p] : pictures_) {
        if (p.type == 2) {
            p.texture = renderRichText(p.text, -1, p.textW, p.textH, true, sysVar(8) > 0 ? sysVar(8) : 16, &p);
        } else if (p.type == 3) {
            p.texture = windowTexture(p.file, p.windowW, p.windowH);
        } else {
            p.texture = loadImage(p.file);
        }
    }
    // Sound
    stopSound(Channel::BGM, 0);
    stopSound(Channel::BGS, 0);
    if (!audio.bgmFile.empty()) playSound(Channel::BGM, -1, audio.bgmFile, audio.bgmVolume, audio.bgmPitch, 0, 0, 0);
    if (!audio.bgsFile.empty()) playSound(Channel::BGS, -1, audio.bgsFile, audio.bgsVolume, audio.bgsPitch, 0, 0, 0);
    audioState_.bgmId = audio.bgmId;
    audioState_.bgsId = audio.bgsId;
    updateCamera();
    return true;
}

bool Game::save(int slot) {
    if (saveFolder_.empty()) return false;
    mkdir(saveFolder_.c_str(), 0755);
    std::vector<uint8_t> data = serialize();
    std::string path = savePath(slot), temp = path + ".tmp";
    FILE* f = std::fopen(temp.c_str(), "wb");
    if (!f) {
        log("cannot write save " + path);
        return false;
    }
    bool ok = std::fwrite(data.data(), 1, data.size(), f) == data.size();
    ok = std::fclose(f) == 0 && ok;
    if (ok) ok = std::rename(temp.c_str(), path.c_str()) == 0;
    log(ok ? "saved slot " + std::to_string(slot) : "save failed for slot " + std::to_string(slot));
    return ok;
}

bool Game::load(int slot) {
    FILE* f = std::fopen(savePath(slot).c_str(), "rb");
    if (!f) {
        sys_[24] = 0;
        return false;
    }
    std::fseek(f, 0, SEEK_END);
    long n = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> data(size_t(std::max(n, 0L)));
    size_t got = std::fread(data.data(), 1, data.size(), f);
    std::fclose(f);
    data.resize(got);
    bool ok = deserialize(data);
    sys_[24] = ok ? 1 : 0;
    sys_[25] = slot;
    log(ok ? "loaded slot " + std::to_string(slot) : "load failed for slot " + std::to_string(slot));
    return ok;
}

}  // namespace wolf
