#include "Game.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <ctime>

namespace wolf {

namespace {

constexpr int32_t kMaxValue = 999999999;

int32_t clampValue(int64_t v) {
    if (v > kMaxValue) return kMaxValue;
    if (v < -kMaxValue) return -kMaxValue;
    return int32_t(v);
}

int32_t toNumber(const std::string& s) {
    char* end = nullptr;
    long v = std::strtol(s.c_str(), &end, 10);
    return clampValue(v);
}

}  // namespace

Game::Game(std::unique_ptr<Project> project, Gfx& gfx, Audio& audio, std::string saveFolder, HostCallbacks host)
    : project_(std::move(project)), gfx_(gfx), audio_(audio), saveFolder_(std::move(saveFolder)), host_(std::move(host)) {
    rng_.seed(uint32_t(std::time(nullptr)));
    const GameDat& g = project_->game;
    tileSize_ = g.setting(0) > 0 ? g.setting(0) : 16;
    charDirs_ = g.setting(1) == 8 ? 8 : 4;
    fps_ = g.setting(4) > 0 ? g.setting(4) : 60;
    charPatterns_ = g.setting(7) == 5 ? 5 : 3;
    int w = g.setting16(16), h = g.setting16(17);
    if (w > 0 && h > 0) {
        screenW_ = w;
        screenH_ = h;
    } else {
        // Older games: 320x240 (drawn doubled), 640x480 or 800x600, from the tile size.
        screenW_ = tileSize_ <= 16 ? 320 : 640;
        screenH_ = tileSize_ <= 16 ? 240 : 480;
    }
    vars_.assign(10000, 0);
    strs_.assign(1000, "");
    sys_.assign(1000, 0);
    sysStr_.assign(200, "");
    initSystemValues();

    // Fonts: the game's own font files (any .ttf/.otf/.ttc in the game or Data folder).
    for (const std::string& folder : {std::string(""), std::string("Data")}) {
        std::vector<std::string> files = folder.empty() ? std::vector<std::string>() : project_->vfs.list(folder);
        if (folder.empty()) {
            for (const auto& f : project_->vfs.list("."))
                if (f.find('/') == std::string::npos) files.push_back(f);
        }
        for (const auto& f : files) {
            std::string lower = Vfs::normalize(f);
            if (lower.size() < 4) continue;
            std::string ext = lower.substr(lower.size() - 4);
            if (ext != ".ttf" && ext != ".otf" && ext != ".ttc") continue;
            if (folder == "Data" && lower.find('/', 5) != std::string::npos) continue;
            if (auto data = project_->vfs.read(f)) gfx_.addFont(f, *data);
        }
    }
    gfx_.setFonts({g.font(), g.subFont(0), g.subFont(1), g.subFont(2)});
}

Game::~Game() = default;

void Game::log(const std::string& message) {
    if (host_.log) host_.log(message);
}

std::string Game::debugState() {
    std::string s = "map " + std::to_string(mapId_) + " hero " + std::to_string(hero_.px / 2) + "," +
                    std::to_string(hero_.py / 2) + " graphic '" + hero_.graphic + "' frame " + std::to_string(frameCount_) + "\n";
    auto describe = [&](const char* kind, const Context& c) {
        s += std::string(kind) + " event " + std::to_string(c.mapEventId) + " common " + std::to_string(c.commonId) +
             " wait " + std::to_string(int(c.wait)) + " frames " + std::to_string(c.waitFrames) + ":";
        for (const auto& f : c.frames)
            s += " [c" + std::to_string(f.commonId) + " e" + std::to_string(f.eventId) + " pc" + std::to_string(f.pc) + "]";
        s += "\n";
    };
    for (const auto& c : contexts_) describe("main", *c);
    for (const auto& [id, c] : commonContexts_) describe("parallel", *c);
    for (const auto& [id, c] : mapParallel_) describe("map-parallel", *c);
    s += "pictures " + std::to_string(pictures_.size()) + ":";
    for (const auto& [n, p] : pictures_)
        s += " " + std::to_string(n) + "(" + (p.type == 2 ? "text" : p.file) + " " + std::to_string(int(p.cur.x)) + "," +
             std::to_string(int(p.cur.y)) + " op" + std::to_string(int(p.cur.opacity)) + ")";
    s += "\nmessage " + std::to_string(msg_.open) + " choosing " + std::to_string(msg_.choosing) + " text '" +
         msg_.text.substr(0, 80) + "'\n";
    s += "screen color " + std::to_string(int(fx_.r)) + "," + std::to_string(int(fx_.g)) + "," + std::to_string(int(fx_.b)) +
         " prepared " + std::to_string(fx_.prepared) + " trans " + std::to_string(fx_.transFrames) + "\n";
    s += "sys0-11:";
    for (int i = 0; i <= 11; i++) s += " " + std::to_string(sys_[size_t(i)]);
    s += "\n";
    return s;
}

void Game::initSystemValues() {
    sys_[8] = tileSize_ <= 16 ? 12 : 24;   // basic font size
    sys_[9] = 120;                         // message speed (characters per second)
    sys_[11] = 0;
    sys_[15] = 15;
    sys_[16] = 4;
    sys_[37] = 1;
    sys_[84] = screenW_ == 320 ? 0 : screenW_ == 640 ? 1 : screenW_ == 800 ? 2 : -1;
    sys_[100] = sys_[101] = sys_[102] = 100;
    sys_[111] = 1;
    sys_[115] = project_->game.setting16(18) > 0 ? project_->game.setting16(18) : 225;
    sys_[116] = screenW_;
    sys_[117] = screenH_;
    sys_[118] = tileSize_;
    sys_[5] = sys_[6] = -1;
    sys_[1] = sys_[2] = sys_[3] = sys_[4] = -1;
    sys_[14] = 1;
    sys_[73] = 1;
    sysStr_[10] = project_->game.heroGraphic();
}

std::string Game::variableName(int index) {
    // System DB type 14 lists the normal variable names.
    const DBRecord* r = dbRecord(2, 14, index, false);
    return r ? r->name : std::string();
}

// ---------------------------------------------------------------------------------------------
// Databases. Internal numbering: 0 user (UDB), 1 changeable (CDB), 2 system (SDB).

DBType* Game::dbType(int db, int type) {
    Database& d = db == 0 ? project_->udb : db == 1 ? project_->cdb : project_->sdb;
    if (type < 0 || size_t(type) >= d.types.size()) return nullptr;
    return &d.types[size_t(type)];
}

DBRecord* Game::dbRecord(int db, int type, int record, bool create) {
    DBType* t = dbType(db, type);
    if (!t || record < 0) return nullptr;
    if (size_t(record) >= t->records.size()) {
        if (!create || record > 100000) return nullptr;
        size_t ints = 0, strs = 0;
        for (auto& f : t->fields) (f.isString ? strs : ints)++;
        while (t->records.size() <= size_t(record)) {
            DBRecord r;
            r.ints.assign(ints, 0);
            r.strings.assign(strs, "");
            t->records.push_back(std::move(r));
        }
    }
    return &t->records[size_t(record)];
}

const DBField* Game::dbField(int db, int type, int field) {
    DBType* t = dbType(db, type);
    if (!t || field < 0 || size_t(field) >= t->fields.size()) return nullptr;
    return &t->fields[size_t(field)];
}

int Game::dbInt(int db, int type, int record, int field) {
    const DBField* f = dbField(db, type, field);
    DBRecord* r = dbRecord(db, type, record, false);
    if (!f || !r) return 0;
    if (f->isString) return size_t(f->index) < r->strings.size() ? toNumber(r->strings[size_t(f->index)]) : 0;
    return size_t(f->index) < r->ints.size() ? r->ints[size_t(f->index)] : 0;
}

std::string Game::dbString(int db, int type, int record, int field) {
    const DBField* f = dbField(db, type, field);
    DBRecord* r = dbRecord(db, type, record, false);
    if (!f || !r) return {};
    if (f->isString) return size_t(f->index) < r->strings.size() ? r->strings[size_t(f->index)] : std::string();
    return size_t(f->index) < r->ints.size() ? std::to_string(r->ints[size_t(f->index)]) : std::string();
}

void Game::dbSetInt(int db, int type, int record, int field, int32_t value) {
    const DBField* f = dbField(db, type, field);
    DBRecord* r = dbRecord(db, type, record, true);
    if (!f || !r) return;
    if (f->isString) {
        if (size_t(f->index) < r->strings.size()) r->strings[size_t(f->index)] = std::to_string(value);
    } else if (size_t(f->index) < r->ints.size()) {
        r->ints[size_t(f->index)] = value;
    }
}

void Game::dbSetString(int db, int type, int record, int field, const std::string& value) {
    const DBField* f = dbField(db, type, field);
    DBRecord* r = dbRecord(db, type, record, true);
    if (!f || !r) return;
    if (f->isString) {
        if (size_t(f->index) < r->strings.size()) r->strings[size_t(f->index)] = value;
    } else if (size_t(f->index) < r->ints.size()) {
        r->ints[size_t(f->index)] = toNumber(value);
    }
}

std::string Game::sdbFile(int type, int record) {
    // The first string field of a system DB record (file lists: BGM, SE, characters, faces, …).
    DBType* t = dbType(2, type);
    DBRecord* r = dbRecord(2, type, record, false);
    if (!t || !r) return {};
    for (const auto& f : t->fields)
        if (f.isString && size_t(f.index) < r->strings.size()) return r->strings[size_t(f.index)];
    return {};
}

// ---------------------------------------------------------------------------------------------
// Variables

std::vector<int32_t>& Game::spare(int set) {
    auto& v = spare_[size_t(std::clamp(set, 1, 9))];
    if (v.empty()) v.assign(1000, 0);
    return v;
}

bool Game::isStringAddress(int32_t a) const {
    if (a >= 3000000 && a <= 3999999) return true;
    if (a >= 9900000 && a <= 9999999) return true;
    if (a >= 1600005 && a <= 1600009) return true;
    if (a >= 15000000 && a <= 15999999) {
        int idx = a % 100;
        return idx >= 5 && idx <= 9;
    }
    if (a >= 1000000000 && a < 1400000000) {
        int db = (a / 100000000) % 10;
        int idb = db == 0 ? 0 : db == 1 ? 1 : 2;
        const DBField* f = const_cast<Game*>(this)->dbField(idb, (a / 1000000) % 100, a % 100);
        return f && f->isString;
    }
    return false;
}

int32_t Game::getValue(int32_t a, const Frame* f) {
    if (a > -1000000 && a < 1000000) return a;
    if (a >= 1000000000) {
        if (a >= 1400000000) return a;
        int db = (a / 100000000) % 10;
        if (db == 2) return a;
        int idb = db == 0 ? 0 : db == 1 ? 1 : 2;
        return dbInt(idb, (a / 1000000) % 100, (a / 100) % 10000, a % 100);
    }
    if (a < 0) return a;
    if (a < 1100000) {  // map event self variables
        int id = (a - 1000000) / 10, idx = a % 10;
        if (Character* ch = eventChar(id)) return ch->selfVars[idx];
        return 0;
    }
    if (a < 1100010) {  // this map event's self variables
        int id = f ? f->eventId : -1;
        if (Character* ch = eventChar(id)) return ch->selfVars[a % 10];
        return 0;
    }
    if (a >= 1600000 && a < 1600100) {  // this common event's self variables
        if (!f || f->commonId < 0) return 0;
        int idx = a - 1600000;
        if (idx >= 5 && idx <= 9) return toNumber(commonSelfStr_[f->commonId][size_t(idx - 5)]);
        return commonSelf_[f->commonId][size_t(idx)];
    }
    if (a >= 2000000 && a < 2100000) {
        size_t idx = size_t(a - 2000000);
        return idx < vars_.size() ? vars_[idx] : 0;
    }
    if (a >= 2100000 && a < 3000000) {
        auto& s = spare((a - 2000000) / 100000);
        size_t idx = size_t(a % 100000);
        return idx < s.size() ? s[idx] : 0;
    }
    if (a >= 3000000 && a < 4000000) return toNumber(getString(a, f));
    if (a >= 8000000 && a < 9000000) {
        int range = a - 8000000;
        return range <= 0 ? 0 : int32_t(rng_() % uint32_t(range + 1));
    }
    if (a >= 9000000 && a < 9100000) {
        size_t idx = size_t(a - 9000000);
        if (idx == 28) return int32_t(frameCount_ % 10000000);
        if (idx == 29) return int32_t(playFrames_ / std::max(fps_, 1));
        if (idx == 30) return int32_t(playFrames_ * 1000 / std::max(fps_, 1));
        if (idx == 31 || idx == 32) return fps_;
        if (idx >= 77 && idx <= 82) {
            std::time_t t = std::time(nullptr);
            std::tm tm = *std::localtime(&t);
            int v[] = {tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec};
            return v[idx - 77];
        }
        if (idx == 104) return int32_t(camX_);
        if (idx == 105) return int32_t(camY_);
        return idx < sys_.size() ? sys_[idx] : 0;
    }
    if (a >= 9100000 && a < 9180000) return charInfo((a - 9100000) / 10, a % 10, f);
    if (a >= 9180000 && a < 9180010) return charInfo(-1, a % 10, f);
    if (a >= 9180010 && a < 9180060) return charInfo(-2 - (a - 9180010) / 10, a % 10, f);
    if (a >= 9190000 && a < 9190010) return charInfo(f ? f->eventId : -1, a % 10, f);
    if (a >= 9900000 && a < 10000000) return toNumber(getString(a, f));
    if (a >= 15000000 && a < 16000000) {
        int id = (a - 15000000) / 100, idx = a % 100;
        if (idx >= 5 && idx <= 9) return toNumber(commonSelfStr_[id][size_t(idx - 5)]);
        return commonSelf_[id][size_t(idx)];
    }
    return a;
}

void Game::setValue(int32_t a, int32_t v, const Frame* f) {
    if (a >= 1000000000 && a < 1400000000) {
        int db = (a / 100000000) % 10;
        if (db == 2) return;
        int idb = db == 0 ? 0 : db == 1 ? 1 : 2;
        dbSetInt(idb, (a / 1000000) % 100, (a / 100) % 10000, a % 100, v);
        return;
    }
    if (a >= 1000000 && a < 1100000) {
        if (Character* ch = eventChar((a - 1000000) / 10)) {
            ch->selfVars[a % 10] = v;
            needRefresh_ = true;
        }
        return;
    }
    if (a >= 1100000 && a < 1100010) {
        if (Character* ch = eventChar(f ? f->eventId : -1)) {
            ch->selfVars[a % 10] = v;
            needRefresh_ = true;
        }
        return;
    }
    if (a >= 1600000 && a < 1600100) {
        if (!f || f->commonId < 0) return;
        int idx = a - 1600000;
        if (idx >= 5 && idx <= 9) commonSelfStr_[f->commonId][size_t(idx - 5)] = std::to_string(v);
        else commonSelf_[f->commonId][size_t(idx)] = v;
        return;
    }
    if (a >= 2000000 && a < 2100000) {
        size_t idx = size_t(a - 2000000);
        if (idx >= vars_.size()) vars_.resize(std::min<size_t>(idx + 1, 100000), 0);
        if (idx < vars_.size()) vars_[idx] = v;
        needRefresh_ = true;
        return;
    }
    if (a >= 2100000 && a < 3000000) {
        auto& s = spare((a - 2000000) / 100000);
        size_t idx = size_t(a % 100000);
        if (idx >= s.size()) s.resize(idx + 1, 0);
        s[idx] = v;
        needRefresh_ = true;
        return;
    }
    if ((a >= 3000000 && a < 4000000) || (a >= 9900000 && a < 10000000)) {
        setString(a, std::to_string(v), f);
        return;
    }
    if (a >= 9000000 && a < 9100000) {
        size_t idx = size_t(a - 9000000);
        if (idx >= sys_.size()) sys_.resize(idx + 1, 0);
        sys_[idx] = v;
        if (idx == 104) camX_ = v;
        if (idx == 105) camY_ = v;
        needRefresh_ = true;
        return;
    }
    if (a >= 9100000 && a < 9190010) {
        // Event info: height and direction can be written.
        int target = a >= 9190000 ? (f ? f->eventId : -1) : a >= 9180010 ? -2 - (a - 9180010) / 10
                                                             : a >= 9180000 ? -1 : (a - 9100000) / 10;
        if (Character* ch = character(target, f)) {
            int info = a % 10;
            if (info == 4) ch->height = v;
            else if (info == 5) setDirection(*ch, v);
            else if (info == 8) ch->shadow = v;
        }
        return;
    }
    if (a >= 15000000 && a < 16000000) {
        int id = (a - 15000000) / 100, idx = a % 100;
        if (idx >= 5 && idx <= 9) commonSelfStr_[id][size_t(idx - 5)] = std::to_string(v);
        else commonSelf_[id][size_t(idx)] = v;
        return;
    }
}

std::string Game::getString(int32_t a, const Frame* f) {
    if (a >= 3000000 && a < 4000000) {
        size_t idx = size_t(a - 3000000);
        return idx < strs_.size() ? strs_[idx] : std::string();
    }
    if (a >= 9900000 && a < 10000000) {
        size_t idx = size_t(a - 9900000);
        if (idx == 33) return audioState_.bgmFile;
        if (idx == 34) return audioState_.bgsFile;
        if (idx == 52) return project_->vfs.root() + "/Data/";
        return idx < sysStr_.size() ? sysStr_[idx] : std::string();
    }
    if (a >= 1600005 && a <= 1600009)
        return f && f->commonId >= 0 ? commonSelfStr_[f->commonId][size_t(a - 1600005)] : std::string();
    if (a >= 15000000 && a < 16000000) {
        int id = (a - 15000000) / 100, idx = a % 100;
        if (idx >= 5 && idx <= 9) return commonSelfStr_[id][size_t(idx - 5)];
    }
    if (a >= 1000000000 && a < 1400000000) {
        int db = (a / 100000000) % 10;
        int idb = db == 0 ? 0 : db == 1 ? 1 : 2;
        return dbString(idb, (a / 1000000) % 100, (a / 100) % 10000, a % 100);
    }
    return std::to_string(getValue(a, f));
}

void Game::setString(int32_t a, const std::string& value, const Frame* f) {
    if (a >= 3000000 && a < 4000000) {
        size_t idx = size_t(a - 3000000);
        if (idx >= strs_.size()) strs_.resize(std::min<size_t>(idx + 1, 100000));
        if (idx < strs_.size()) strs_[idx] = value;
        return;
    }
    if (a >= 9900000 && a < 10000000) {
        size_t idx = size_t(a - 9900000);
        if (idx >= sysStr_.size()) sysStr_.resize(idx + 1);
        sysStr_[idx] = value;
        if (idx >= 10 && idx <= 15) needRefresh_ = true;  // hero and party graphics
        return;
    }
    if (a >= 1600005 && a <= 1600009) {
        if (f && f->commonId >= 0) commonSelfStr_[f->commonId][size_t(a - 1600005)] = value;
        return;
    }
    if (a >= 15000000 && a < 16000000) {
        int id = (a - 15000000) / 100, idx = a % 100;
        if (idx >= 5 && idx <= 9) {
            commonSelfStr_[id][size_t(idx - 5)] = value;
            return;
        }
    }
    if (a >= 1000000000 && a < 1400000000) {
        int db = (a / 100000000) % 10;
        int idb = db == 0 ? 0 : db == 1 ? 1 : 2;
        dbSetString(idb, (a / 1000000) % 100, (a / 100) % 10000, a % 100, value);
        return;
    }
    setValue(a, toNumber(value), f);
}

// ---------------------------------------------------------------------------------------------
// Characters as event-command targets: -1 hero, -2.. party members, -2 in "this event" contexts.

Character* Game::eventChar(int id) {
    auto it = eventIndex_.find(id);
    return it == eventIndex_.end() ? nullptr : &events_[it->second];
}

Character* Game::character(int target, const Frame* frame) {
    if (target == -1) return &hero_;
    if (target <= -2 && target >= -6) {
        size_t i = size_t(-2 - target);
        return i < party_.size() ? &party_[i] : nullptr;
    }
    if (target >= 1000000 && frame) target = getValue(target, frame);
    if (target == -1) return &hero_;
    return eventChar(target);
}

int32_t Game::charInfo(int target, int info, const Frame* frame) {
    Character* ch = character(target, frame);
    if (!ch) return 0;
    switch (info) {
        case 0: return ch->px / 2;
        case 1: return ch->py / 2;
        case 2: return ch->px;
        case 3: return ch->py;
        case 4: return ch->height;
        case 5: return ch->direction;
        case 6: return int32_t(std::lround(ch->realX - camX_ + tileSize_ / 2.0));
        case 7: return int32_t(std::lround(ch->realY - camY_ + tileSize_));
        case 8: return ch->shadow;
        case 9: return tileTag(ch->px / 2, ch->py / 2, -1);
        case 10: return ch->eventId;
        case 11: {
            double sx = ch->realX - camX_, sy = ch->realY - camY_;
            return sx > -tileSize_ && sy > -tileSize_ && sx < screenW_ && sy < screenH_ ? 1 : 0;
        }
        case 12: return ch->page + 1;
        case 13: {
            if (ch->page < 0 || !mapData_) return -1;
            auto it = eventIndex_.find(ch->eventId);
            if (it == eventIndex_.end()) return -1;
            return mapData_->events[it->second].pages[size_t(ch->page)].trigger;
        }
        case 14: return ch->rangeX;
        case 15: return ch->rangeY;
        case 16: return ch->pattern;
        case 17: return ch->moving ? 1 : 0;
    }
    return 0;
}

// ---------------------------------------------------------------------------------------------
// Frame logic

bool Game::repeated(int key) const {
    if (!input_.down[key]) return false;
    if (!prevInput_.down[key]) return true;
    int first = std::max(sysVar(15), 1), next = std::max(sysVar(16), 1);
    int c = repeatCounter_[key];
    return c >= first && (c - first) % next == 0;
}

bool Game::mainEventRunning() const {
    for (const auto& c : contexts_)
        if (c->kind == Context::Kind::Main && !c->finished()) return true;
    return false;
}

void Game::start() {
    // The initial position: system DB type 7, record 0 (map, x, y).
    int map = dbInt(2, 7, 0, 0), x = dbInt(2, 7, 0, 1), y = dbInt(2, 7, 0, 2);
    hero_ = Character();
    hero_.eventId = -1;
    hero_.moveSpeed = project_->game.setting(16) > 0 ? project_->game.setting(16) : 4;
    hero_.halfStep = project_->game.setting(8) == 0;
    hero_.moveAnim = true;
    hero_.px = x * 2;
    hero_.py = y * 2;
    hero_.realX = x * tileSize_;
    hero_.realY = y * tileSize_;
    loadMap(map);
    started_ = true;
}

void Game::returnToTitle() {
    contexts_.clear();
    commonContexts_.clear();
    mapParallel_.clear();
    pictures_.clear();
    msg_ = MessageWindow();
    fx_ = ScreenEffects();
    vars_.assign(10000, 0);
    for (auto& s : spare_) s.clear();
    strs_.assign(1000, "");
    std::vector<int32_t> keep(sys_.begin(), sys_.end());
    sys_.assign(1000, 0);
    sysStr_.assign(200, "");
    initSystemValues();
    commonSelf_.clear();
    commonSelfStr_.clear();
    mapSelf_.clear();
    stopSound(Channel::BGM, 0);
    stopSound(Channel::BGS, 0);
    // Databases back to their initial contents.
    std::string root = project_->vfs.root();
    try {
        auto fresh = std::make_unique<Project>(root);
        project_->udb = std::move(fresh->udb);
        project_->cdb = std::move(fresh->cdb);
        project_->sdb = std::move(fresh->sdb);
    } catch (const std::exception& e) {
        log(std::string("reload failed: ") + e.what());
    }
    playFrames_ = 0;
    start();
}

void Game::frame(const InputState& in) {
    for (int step = 0; step < std::max(1, speed); step++) {
        prevInput_ = input_;
        input_ = in;
        for (int k = 0; k < KeyCount; k++) {
            if (inputBanned_[k]) input_.down[k] = false;
            repeatCounter_[k] = input_.down[k] ? repeatCounter_[k] + 1 : 0;
        }
        frameCount_++;
        playFrames_++;
        sys_[12] = msg_.open ? 1 : 0;
        sys_[13] = mainEventRunning() ? 1 : 0;
        sys_[35] = hero_.moving ? 1 : 0;
        sys_[71] = input_.mouseX;
        sys_[72] = input_.mouseY;

        if (loadRequest_ >= 0) {
            int slot = loadRequest_;
            loadRequest_ = -1;
            load(slot);
        }
        if (pendingTransfer_) {
            pendingTransfer_ = false;
            if (pendingMap_ >= 0 && pendingMap_ != mapId_) {
                hero_.px = pendingX;
                hero_.py = pendingY;
                loadMap(pendingMap_);
            } else {
                hero_.px = pendingX;
                hero_.py = pendingY;
            }
            hero_.realX = hero_.px * tileSize_ / 2.0;
            hero_.realY = hero_.py * tileSize_ / 2.0;
            hero_.moving = false;
            if (pendingDir) setDirection(hero_, pendingDir);
            for (auto& m : party_) {
                m.px = hero_.px;
                m.py = hero_.py;
                m.realX = hero_.realX;
                m.realY = hero_.realY;
                m.direction = hero_.direction;
                m.moving = false;
            }
            fx_.scrollX = fx_.scrollY = 0;
            needRefresh_ = true;
            updateCamera();
        }
        if (needRefresh_) refreshPages();

        updateMessage();
        updateEvents();
        updateCommonTriggers();
        if (!pictureOnly_) updateMap();
        updatePictures();
        updateScreenEffects();
        if (quit_) return;
    }
}

bool Game::commonCondition(const CommonEvent& c) {
    int32_t left = getValue(c.left);
    int32_t right = c.right;
    switch (c.op) {
        case 0x00: return left > right;
        case 0x10: return left >= right;
        case 0x20: return left == right;
        case 0x30: return left <= right;
        case 0x40: return left < right;
        case 0x50: return left != right;
        case 0x60: return (left & right) != 0;
    }
    return false;
}

void Game::startCommonContext(int commonId, Context::Kind kind) {
    auto ctx = std::make_unique<Context>();
    ctx->kind = kind;
    ctx->commonId = commonId;
    callCommon(*ctx, commonId, nullptr, 0, {}, {}, false);
    if (kind == Context::Kind::Main) contexts_.push_back(std::move(ctx));
    else commonContexts_[commonId] = std::move(ctx);
}

void Game::updateCommonTriggers() {
    auto& commons = project_->commons;
    bool mainRunning = mainEventRunning();
    for (size_t i = 0; i < commons.size(); i++) {
        const CommonEvent& c = commons[i];
        if (!c.valid || c.commands.empty()) continue;
        if (c.trigger == 1) {
            if (mainRunning) continue;
            if (commonCondition(c)) {
                startCommonContext(int(i), Context::Kind::Main);
                mainRunning = true;
            }
        } else if (c.trigger == 2 || c.trigger == 3) {
            auto it = commonContexts_.find(int(i));
            bool running = it != commonContexts_.end() && !it->second->finished();
            if (!running && commonCondition(c))
                startCommonContext(int(i), c.trigger == 3 ? Context::Kind::ParallelAlways : Context::Kind::Parallel);
        }
    }
    if (!mainRunning && !reservedCommons_.empty()) {
        int id = reservedCommons_.front();
        reservedCommons_.erase(reservedCommons_.begin());
        startCommonContext(id, Context::Kind::Main);
    }
}

void Game::updateEvents() {
    // The main event first, then parallel commons and parallel map events.
    for (size_t i = 0; i < contexts_.size(); i++) {
        if (contexts_[i]->kind != Context::Kind::Main) continue;
        runContext(*contexts_[i]);
        break;  // one main event at a time
    }
    contexts_.erase(std::remove_if(contexts_.begin(), contexts_.end(), [](const auto& c) { return c->finished(); }),
                    contexts_.end());
    bool mainRunning = mainEventRunning();
    std::vector<int> ids;
    for (auto& [id, ctx] : commonContexts_) ids.push_back(id);
    for (int id : ids) {
        auto it = commonContexts_.find(id);
        if (it == commonContexts_.end()) continue;
        Context& ctx = *it->second;
        if (ctx.kind == Context::Kind::Parallel && mainRunning) continue;
        // A parallel common stops when its condition no longer holds (checked at its start).
        if (size_t(id) < project_->commons.size() && !commonCondition(project_->commons[size_t(id)]) && ctx.frames.size() == 1 &&
            ctx.frames[0].pc == 0) {
            commonContexts_.erase(it);
            continue;
        }
        runContext(ctx);
    }
    for (auto it = commonContexts_.begin(); it != commonContexts_.end();)
        it = it->second->finished() ? commonContexts_.erase(it) : std::next(it);

    ids.clear();
    for (auto& [id, ctx] : mapParallel_) ids.push_back(id);
    for (int id : ids) {
        auto it = mapParallel_.find(id);
        if (it == mapParallel_.end()) continue;
        if (mainRunning) continue;
        runContext(*it->second);
    }
    for (auto it = mapParallel_.begin(); it != mapParallel_.end();)
        it = it->second->finished() ? mapParallel_.erase(it) : std::next(it);
}

// ---------------------------------------------------------------------------------------------
// Sound

void Game::playSound(Channel ch, int id, const std::string& file, int volume, int pitch, int startMs, int loopMs,
                     int fade) {
    std::string name = file;
    if (id >= 0) {
        int type = ch == Channel::BGM ? 1 : ch == Channel::BGS ? 2 : 3;
        name = sdbFile(type, id);
        // List entries carry their own volume, pitch and loop point.
        if (volume == 100) volume = dbInt(2, type, id, 1);
        if (pitch == 100) pitch = dbInt(2, type, id, 2);
        if (loopMs == 0 && ch != Channel::SE) loopMs = dbInt(2, type, id, 3);
        if (volume <= 0) volume = 100;
        if (pitch <= 0) pitch = 100;
    }
    // Map BGM settings store "file\nvolume\npitch\nloop".
    if (name.find('\n') != std::string::npos) {
        std::vector<std::string> parts;
        size_t s = 0;
        while (true) {
            size_t e = name.find('\n', s);
            parts.push_back(name.substr(s, e == std::string::npos ? std::string::npos : e - s));
            if (e == std::string::npos) break;
            s = e + 1;
        }
        name = parts[0];
        if (parts.size() > 1 && !parts[1].empty()) volume = std::atoi(parts[1].c_str());
        if (parts.size() > 2 && !parts[2].empty()) pitch = std::atoi(parts[2].c_str());
        if (parts.size() > 3 && !parts[3].empty()) loopMs = std::atoi(parts[3].c_str());
    }
    while (!name.empty() && (name.back() == '\r' || name.back() == ' ')) name.pop_back();
    if (name.empty()) return;
    if (ch == Channel::BGM && name == audioState_.bgmFile && startMs == 0 && audio_.lengthMs(ch) >= 0 &&
        audioState_.bgmVolume == volume && audioState_.bgmPitch == pitch)
        return;  // already playing
    if (ch == Channel::BGS && name == audioState_.bgsFile && audioState_.bgsVolume == volume) return;
    auto data = project_->vfs.read("Data/" + name);
    if (!data) data = project_->vfs.read(name);
    if (!data) {
        log("missing sound " + name);
        return;
    }
    int master = ch == Channel::BGM ? sysVar(100) : ch == Channel::BGS ? sysVar(101) : sysVar(102);
    int vol = volume * (master > 0 ? master : 100) / 100;
    audio_.play(ch, name, *data, vol, pitch, startMs, loopMs, fade * 1000 / std::max(fps_, 1));
    if (ch == Channel::BGM) {
        audioState_.bgmFile = name;
        audioState_.bgmId = id;
        audioState_.bgmVolume = volume;
        audioState_.bgmPitch = pitch;
        audioState_.bgmLoop = loopMs;
        sys_[95] = volume;
        sys_[96] = pitch;
    } else if (ch == Channel::BGS) {
        audioState_.bgsFile = name;
        audioState_.bgsId = id;
        audioState_.bgsVolume = volume;
        audioState_.bgsPitch = pitch;
        audioState_.bgsLoop = loopMs;
        sys_[97] = volume;
        sys_[98] = pitch;
    }
}

void Game::stopSound(Channel ch, int fade) {
    audio_.stop(ch, fade * 1000 / std::max(fps_, 1));
    if (ch == Channel::BGM) {
        audioState_.bgmFile.clear();
        audioState_.bgmId = -1;
    } else if (ch == Channel::BGS) {
        audioState_.bgsFile.clear();
        audioState_.bgsId = -1;
    }
}

}  // namespace wolf
