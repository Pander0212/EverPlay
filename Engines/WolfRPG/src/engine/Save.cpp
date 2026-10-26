// Saves: EverPlay's own format (WOLF's .sav files are not readable), one file per slot in the
// folder EverPlay passes in, which is On My iPhone › EverPlay › Saves › <game>.
#include <cstdio>
#include <cstring>
#include <sys/stat.h>

#include "Game.hpp"

namespace wolf {

namespace {

constexpr uint32_t kMagic = 0x57455053;
constexpr uint32_t kVersion = 2;

struct Writer {
    std::vector<uint8_t> out;
    void u32(uint32_t v) { for (int i = 0; i < 4; i++) out.push_back(uint8_t(v >> (i * 8))); }
    void i32(int32_t v) { u32(uint32_t(v)); }
    void f64(double v) { uint64_t b; std::memcpy(&b, &v, 8); for (int i = 0; i < 8; i++) out.push_back(uint8_t(b >> (i * 8))); }
    void str(const std::string& s) { u32(uint32_t(s.size())); out.insert(out.end(), s.begin(), s.end()); }
    void ints(const std::vector<int32_t>& v) { u32(uint32_t(v.size())); for (auto x : v) i32(x); }
    void strs(const std::vector<std::string>& v) { u32(uint32_t(v.size())); for (auto& x : v) str(x); }
};

struct In {
    const std::vector<uint8_t>& in;
    size_t pos = 0;
    bool ok = true;
    explicit In(const std::vector<uint8_t>& d) : in(d) {}
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

void readChar(In& r, Character& c) {
    c.eventId = r.i32(); c.px = r.i32(); c.py = r.i32(); c.direction = r.i32(); c.pattern = r.i32();
    c.graphic = r.str(); c.tileId = r.i32(); c.opacity = r.i32(); c.blend = r.i32(); c.height = r.i32();
    c.moveSpeed = r.i32(); c.moveFrequency = r.i32(); c.animSpeed = r.i32();
    uint32_t flags = r.u32();
    c.erased = flags & 1; c.through = flags & 2; c.fixedDir = flags & 4; c.halfStep = flags & 8;
    for (int i = 0; i < 10; i++) c.selfVars[i] = r.i32();
}

void writeDb(Writer& w, const std::vector<std::vector<DBRecord>>& db) {
    w.u32(uint32_t(db.size()));
    for (const auto& t : db) {
        w.u32(uint32_t(t.size()));
        for (const auto& r : t) { w.str(r.name); w.ints(r.ints); w.strs(r.strings); }
    }
}

std::vector<std::vector<DBRecord>> readDb(In& r) {
    std::vector<std::vector<DBRecord>> db;
    uint32_t types = r.u32();
    for (uint32_t i = 0; i < types && r.ok && i < 1000; i++) {
        uint32_t n = r.u32();
        if (!r.ok || n > 1000000) { r.ok = false; break; }
        std::vector<DBRecord> records(n);
        for (auto& rec : records) { rec.name = r.str(); rec.ints = r.ints(); rec.strings = r.strs(); }
        db.push_back(std::move(records));
    }
    return db;
}

std::vector<std::vector<DBRecord>> recordsOf(const Database& db) {
    std::vector<std::vector<DBRecord>> out;
    for (const auto& t : db.types) out.push_back(t.records);
    return out;
}

}  // namespace

std::string Game::savePath(int slot) const {
    char name[64];
    std::snprintf(name, sizeof name, "/Save%02d.everplay.sav", slot);
    return saveFolder_ + name;
}

void Game::captureState(SaveState& s) {
    if (mapId_ >= 0)
        for (const auto& e : events_)
            for (int i = 0; i < 10; i++) mapSelf_[mapId_][e.eventId][size_t(i)] = e.selfVars[i];
    s.mapId = mapId_;
    s.hero = hero_;
    s.events = events_;
    s.vars = vars_;
    s.spare = spare_;
    s.strs = strs_;
    s.sys = sys_;
    s.sysStr = sysStr_;
    s.cself = commonSelf_;
    s.cselfStr = commonSelfStr_;
    s.mapSelf = mapSelf_;
    s.cdb = recordsOf(project_->cdb);
    s.udb = recordsOf(project_->udb);
    s.audio = audioState_;
    s.r = fx_.r; s.g = fx_.g; s.b = fx_.b;
    s.frames = playFrames_;
    s.pictures.clear();
    for (const auto& [n, p] : pictures_) {
        Picture copy = p;
        copy.texture.reset();
        if (copy.moveFrames > 0) copy.cur = copy.to;
        s.pictures[n] = std::move(copy);
    }
}

std::vector<uint8_t> Game::encodeState(const SaveState& s) {
    Writer w;
    w.u32(kMagic);
    w.u32(kVersion);
    w.str(project_->game.title());
    w.i32(s.mapId);
    writeChar(w, s.hero);
    w.u32(uint32_t(s.events.size()));
    for (const auto& e : s.events) writeChar(w, e);
    w.ints(s.vars);
    for (int k = 1; k <= 9; k++) w.ints(s.spare[size_t(k)]);
    w.strs(s.strs);
    w.ints(s.sys);
    w.strs(s.sysStr);
    w.u32(uint32_t(s.cself.size()));
    for (const auto& [id, v] : s.cself) { w.i32(id); for (auto x : v) w.i32(x); }
    w.u32(uint32_t(s.cselfStr.size()));
    for (const auto& [id, v] : s.cselfStr) { w.i32(id); for (auto& x : v) w.str(x); }
    w.u32(uint32_t(s.mapSelf.size()));
    for (const auto& [map, events] : s.mapSelf) {
        w.i32(map);
        w.u32(uint32_t(events.size()));
        for (const auto& [ev, v] : events) { w.i32(ev); for (auto x : v) w.i32(x); }
    }
    writeDb(w, s.cdb);
    writeDb(w, s.udb);
    w.str(s.audio.bgmFile); w.i32(s.audio.bgmId); w.i32(s.audio.bgmVolume); w.i32(s.audio.bgmPitch);
    w.str(s.audio.bgsFile); w.i32(s.audio.bgsId); w.i32(s.audio.bgsVolume); w.i32(s.audio.bgsPitch);
    w.f64(s.r); w.f64(s.g); w.f64(s.b);
    w.u32(uint32_t(s.frames & 0xFFFFFFFF));
    w.u32(uint32_t(s.frames >> 32));
    w.u32(uint32_t(s.pictures.size()));
    for (const auto& [n, p] : s.pictures) {
        w.i32(n); w.i32(p.type); w.str(p.file); w.str(p.text);
        w.i32(p.divW); w.i32(p.divH); w.i32(p.pattern); w.i32(p.anchor); w.i32(p.blend);
        w.u32((p.scroll ? 1 : 0) | (p.freePos ? 2 : 0));
        w.i32(p.windowW); w.i32(p.windowH);
        const auto& c = p.cur;
        w.f64(c.x); w.f64(c.y); w.f64(c.zoomW); w.f64(c.zoomH); w.f64(c.angle); w.f64(c.opacity);
        w.f64(c.r); w.f64(c.g); w.f64(c.b);
        for (double v : c.corners) w.f64(v);
        w.f64(p.corrW); w.f64(p.corrH);
        w.i32(p.z); w.u32((p.flipX ? 1 : 0) | (p.flipY ? 2 : 0));
    }
    return w.out;
}

bool Game::decodeState(const std::vector<uint8_t>& data, SaveState& s) {
    In r(data);
    if (r.u32() != kMagic || r.u32() != kVersion) return false;
    r.str();
    s.mapId = r.i32();
    readChar(r, s.hero);
    uint32_t n = r.u32();
    if (!r.ok || n > 100000) return false;
    s.events.assign(n, Character());
    for (auto& e : s.events) readChar(r, e);
    s.vars = r.ints();
    for (int k = 1; k <= 9; k++) s.spare[size_t(k)] = r.ints();
    s.strs = r.strs();
    s.sys = r.ints();
    s.sysStr = r.strs();
    uint32_t cn = r.u32();
    for (uint32_t i = 0; i < cn && r.ok; i++) {
        int id = r.i32();
        auto& v = s.cself[id];
        for (auto& x : v) x = r.i32();
    }
    cn = r.u32();
    for (uint32_t i = 0; i < cn && r.ok; i++) {
        int id = r.i32();
        auto& v = s.cselfStr[id];
        for (auto& x : v) x = r.str();
    }
    uint32_t mn = r.u32();
    for (uint32_t i = 0; i < mn && r.ok; i++) {
        int m = r.i32();
        uint32_t en = r.u32();
        for (uint32_t k = 0; k < en && r.ok; k++) {
            int ev = r.i32();
            auto& v = s.mapSelf[m][ev];
            for (auto& x : v) x = r.i32();
        }
    }
    s.cdb = readDb(r);
    s.udb = readDb(r);
    s.audio.bgmFile = r.str(); s.audio.bgmId = r.i32(); s.audio.bgmVolume = r.i32(); s.audio.bgmPitch = r.i32();
    s.audio.bgsFile = r.str(); s.audio.bgsId = r.i32(); s.audio.bgsVolume = r.i32(); s.audio.bgsPitch = r.i32();
    s.r = r.f64(); s.g = r.f64(); s.b = r.f64();
    s.frames = r.u32();
    s.frames |= uint64_t(r.u32()) << 32;
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
        auto& c = p.cur;
        c.x = r.f64(); c.y = r.f64(); c.zoomW = r.f64(); c.zoomH = r.f64(); c.angle = r.f64(); c.opacity = r.f64();
        c.r = r.f64(); c.g = r.f64(); c.b = r.f64();
        for (double& v : c.corners) v = r.f64();
        p.corrW = p.corrToW = r.f64(); p.corrH = p.corrToH = r.f64();
        p.z = r.i32();
        uint32_t flips = r.u32();
        p.flipX = flips & 1; p.flipY = flips & 2;
        p.from = p.to = p.cur;
        s.pictures[num] = std::move(p);
    }
    return r.ok;
}

// Applies a saved state. Must not run inside an event (it replaces every running event).
void Game::applyState(SaveState& s) {
    contexts_.clear();
    commonContexts_.clear();
    mapParallel_.clear();
    reservedCommons_.clear();
    msg_ = MessageWindow();
    vars_ = std::move(s.vars);
    if (vars_.size() < 10000) vars_.resize(10000, 0);
    spare_ = std::move(s.spare);
    strs_ = std::move(s.strs);
    if (strs_.size() < 1000) strs_.resize(1000);
    sys_ = std::move(s.sys);
    if (sys_.size() < 1000) sys_.resize(1000, 0);
    sysStr_ = std::move(s.sysStr);
    if (sysStr_.size() < 200) sysStr_.resize(200);
    commonSelf_ = std::move(s.cself);
    commonSelfStr_ = std::move(s.cselfStr);
    mapSelf_ = std::move(s.mapSelf);
    for (size_t t = 0; t < s.cdb.size() && t < project_->cdb.types.size(); t++) project_->cdb.types[t].records = std::move(s.cdb[t]);
    for (size_t t = 0; t < s.udb.size() && t < project_->udb.types.size(); t++) project_->udb.types[t].records = std::move(s.udb[t]);
    playFrames_ = s.frames;
    fx_ = ScreenEffects();
    fx_.r = s.r; fx_.g = s.g; fx_.b = s.b;
    mapId_ = -1;
    hero_ = s.hero;
    hero_.realX = hero_.px * tileSize_ / 2.0;
    hero_.realY = hero_.py * tileSize_ / 2.0;
    hero_.moving = false;
    hero_.routeDone = true;
    hero_.routeFromCommand = false;
    hero_.exists = true;
    loadMap(s.mapId);
    for (const auto& e : s.events) {
        Character* ch = eventChar(e.eventId);
        if (!ch) continue;
        ch->px = e.px; ch->py = e.py; ch->direction = e.direction; ch->erased = e.erased;
        ch->realX = e.px * tileSize_ / 2.0;
        ch->realY = e.py * tileSize_ / 2.0;
        for (int i = 0; i < 10; i++) ch->selfVars[i] = e.selfVars[i];
    }
    party_.clear();
    refreshPages();
    pictures_ = std::move(s.pictures);
    for (auto& [num, p] : pictures_) {
        if (p.type == 2) p.texture = renderRichText(p.text, -1, p.textW, p.textH, true, sysVar(8) > 0 ? sysVar(8) : 16, &p);
        else if (p.file.rfind("<SQUARE>", 0) == 0) p.texture = squareTexture(p.file, p.windowW, p.windowH);
        else if (p.type == 3) p.texture = windowTexture(p.file, p.windowW, p.windowH);
        else p.texture = loadImage(p.file);
    }
    stopSound(Channel::BGM, 0);
    stopSound(Channel::BGS, 0);
    if (!s.audio.bgmFile.empty()) playSound(Channel::BGM, -1, s.audio.bgmFile, s.audio.bgmVolume, s.audio.bgmPitch, 0, 0, 0);
    if (!s.audio.bgsFile.empty()) playSound(Channel::BGS, -1, s.audio.bgsFile, s.audio.bgsVolume, s.audio.bgsPitch, 0, 0, 0);
    audioState_.bgmId = s.audio.bgmId;
    audioState_.bgsId = s.audio.bgsId;
    updateCamera();
}

// A variable inside a saved state, for "Load/Save variable" (221/222). Returns false for
// addresses a save does not hold.
bool Game::stateValue(SaveState& s, int32_t a, int32_t* number, std::string* text, bool write) {
    auto intSlot = [&](std::vector<int32_t>& v, size_t idx) -> bool {
        if (idx >= v.size()) {
            if (!write || idx > 1000000) { if (number) *number = 0; return true; }
            v.resize(idx + 1, 0);
        }
        if (write) v[idx] = *number;
        else *number = v[idx];
        return true;
    };
    auto strSlot = [&](std::vector<std::string>& v, size_t idx) -> bool {
        if (idx >= v.size()) {
            if (!write || idx > 1000000) { if (text) text->clear(); return true; }
            v.resize(idx + 1);
        }
        if (write) v[idx] = *text;
        else *text = v[idx];
        return true;
    };
    if (a >= 2000000 && a < 2100000 && number) return intSlot(s.vars, size_t(a - 2000000));
    if (a >= 2100000 && a < 3000000 && number) return intSlot(s.spare[size_t(std::clamp((a - 2000000) / 100000, 1, 9))], size_t(a % 100000));
    if (a >= 3000000 && a < 4000000 && text) return strSlot(s.strs, size_t(a - 3000000));
    if (a >= 9000000 && a < 9100000 && number) return intSlot(s.sys, size_t(a - 9000000));
    if (a >= 9900000 && a < 10000000 && text) return strSlot(s.sysStr, size_t(a - 9900000));
    if (a >= 15000000 && a < 16000000) {
        int id = (a - 15000000) / 100, idx = a % 100;
        if (idx >= 5 && idx <= 9 && text) {
            if (write) s.cselfStr[id][size_t(idx - 5)] = *text; else *text = s.cselfStr[id][size_t(idx - 5)];
            return true;
        }
        if (number) {
            if (write) s.cself[id][size_t(idx)] = *number; else *number = s.cself[id][size_t(idx)];
            return true;
        }
    }
    if (a >= 1000000000 && a < 1200000000) {
        int db = (a / 100000000) % 10;  // 0 user, 1 changeable
        auto& records = db == 0 ? s.udb : s.cdb;
        int type = (a / 1000000) % 100, rec = (a / 100) % 10000, field = a % 100;
        const DBField* f = dbField(db, type, field);
        if (!f || size_t(type) >= records.size() || size_t(rec) >= records[size_t(type)].size()) return false;
        DBRecord& r = records[size_t(type)][size_t(rec)];
        if (f->isString && text) return strSlot(r.strings, size_t(f->index));
        if (!f->isString && number) return intSlot(r.ints, size_t(f->index));
    }
    return false;
}

std::vector<uint8_t> Game::serialize() {
    SaveState s;
    captureState(s);
    return encodeState(s);
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

bool Game::readSave(int slot, std::vector<uint8_t>& data) const {
    FILE* f = std::fopen(savePath(slot).c_str(), "rb");
    if (!f) return false;
    std::fseek(f, 0, SEEK_END);
    long n = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    data.resize(size_t(std::max(n, 0L)));
    size_t got = std::fread(data.data(), 1, data.size(), f);
    std::fclose(f);
    data.resize(got);
    return !data.empty();
}

bool Game::load(int slot) {
    std::vector<uint8_t> data;
    SaveState s;
    bool ok = readSave(slot, data) && decodeState(data, s);
    if (ok) applyState(s);
    sys_[24] = ok ? 1 : 0;
    if (ok) sys_[25] = slot;
    log(ok ? "loaded slot " + std::to_string(slot) : "load failed for slot " + std::to_string(slot));
    return ok;
}

}  // namespace wolf
