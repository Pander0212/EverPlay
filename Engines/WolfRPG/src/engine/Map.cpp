// The map: tiles, characters, movement, collisions, event triggers and drawing.
#include <algorithm>
#include <cmath>

#include "Game.hpp"

namespace wolf {

namespace {

// Frames for one whole tile per move speed (0 slowest … 6 fastest).
const int kFramesPerTile[] = {64, 32, 16, 8, 4, 2, 1};
// Frames between automatic moves per move frequency.
const int kMoveWait[] = {0, 8, 16, 32, 64, 128, 256};
// Frames per animation pattern per animation speed.
const int kAnimWait[] = {2, 4, 8, 12, 18, 24, 36};

// Chips of 100000 and up are autotiles: 1xxxxx is the empty one, 2xxxxx to 16xxxxx the tileset's 15
// autotile files; the last digits say how each quarter joins its neighbours. Tag and passage lists
// start with these 16 slots, then the base chips.
bool blankChip(int chip) { return chip == 0 || chip / 100000 == 1; }
int chipIndex(int chip, int offset) { return chip >= 100000 ? chip / 100000 - 1 : chip + offset; }

int dirIndex(int dir, int rows) {
    switch (dir) {
        case 2: return 0;
        case 4: return 1;
        case 6: return 2;
        case 8: return 3;
        case 1: return rows == 8 ? 4 : 1;
        case 3: return rows == 8 ? 5 : 2;
        case 7: return rows == 8 ? 6 : 1;
        case 9: return rows == 8 ? 7 : 2;
    }
    return 0;
}

}  // namespace

std::pair<int, int> Game::dirDelta(int dir) const {
    switch (dir) {
        case 1: return {-1, 1};
        case 2: return {0, 1};
        case 3: return {1, 1};
        case 4: return {-1, 0};
        case 6: return {1, 0};
        case 7: return {-1, -1};
        case 8: return {0, -1};
        case 9: return {1, -1};
    }
    return {0, 0};
}

void Game::setDirection(Character& ch, int dir) {
    if (dir < 1 || dir > 9 || dir == 5) return;
    ch.direction = dir;
}

int Game::stepFrames(const Character& ch) const {
    int s = std::clamp(ch.moveSpeed, 0, 6);
    int frames = kFramesPerTile[s] * tileSize_ / 32;
    if (tileSize_ < 32) frames = kFramesPerTile[s] / 2;
    return std::max(frames, 1);
}

// ---------------------------------------------------------------------------------------------
// Loading

void Game::loadMap(int mapId) {
    bool graphicsOnly = mapId == -2;
    if (!graphicsOnly) {
        // Remember the self variables of the map being left.
        if (mapId_ >= 0)
            for (const auto& e : events_)
                for (int i = 0; i < 10; i++) mapSelf_[mapId_][e.eventId][size_t(i)] = e.selfVars[i];
        mapParallel_.clear();
        mapData_ = project_->map(mapId);
        if (!mapData_) {
            auto empty = std::make_shared<Map>();
            empty->width = std::max(screenW_ / tileSize_, 1);
            empty->height = std::max(screenH_ / tileSize_, 1);
            empty->tiles.assign(size_t(empty->width * empty->height * 3), 0);
            mapData_ = empty;
            log("map " + std::to_string(mapId) + " is missing");
        }
        map_ = *mapData_;
        mapId_ = mapId;
        events_.clear();
        eventIndex_.clear();
        for (size_t i = 0; i < map_.events.size(); i++) {
            const MapEvent& e = map_.events[i];
            Character ch;
            ch.eventId = e.id;
            ch.px = e.x * 2;
            ch.py = e.y * 2;
            ch.realX = e.x * tileSize_;
            ch.realY = e.y * tileSize_;
            auto ms = mapSelf_.find(mapId);
            if (ms != mapSelf_.end()) {
                auto es = ms->second.find(e.id);
                if (es != ms->second.end())
                    for (int k = 0; k < 10; k++) ch.selfVars[k] = es->second[size_t(k)];
            }
            eventIndex_[e.id] = events_.size();
            events_.push_back(std::move(ch));
        }
        passageOverride_.clear();
        // Map BGM, BGS and background from the system DB map settings (type 0).
        int bgm = dbInt(2, 0, mapId, 1), bgs = dbInt(2, 0, mapId, 2);
        if (bgm >= 0) playSound(Channel::BGM, bgm, "", 100, 100, 0, 0, 0);
        else if (bgm == -3) playSound(Channel::BGM, -1, dbString(2, 0, mapId, 5), 100, 100, 0, 0, 0);
        if (bgs >= 0) playSound(Channel::BGS, bgs, "", 100, 100, 0, 0, 0);
        else if (bgs == -3) playSound(Channel::BGS, -1, dbString(2, 0, mapId, 6), 100, 100, 0, 0, 0);
        int pano = dbInt(2, 0, mapId, 4);
        std::string panoFile = pano == -3 ? dbString(2, 0, mapId, 7) : pano >= 0 ? sdbFile(13, pano) : std::string();
        panorama_ = panoFile.empty() ? nullptr : loadImage(panoFile);
    }
    tileset_ = map_.tileset >= 0 && size_t(map_.tileset) < project_->tilesets.size()
                   ? &project_->tilesets[size_t(map_.tileset)]
                   : nullptr;
    baseTiles_.reset();
    autoTiles_.clear();
    if (tileset_) {
        if (!tileset_->baseFile.empty()) baseTiles_ = loadImage(tileset_->baseFile);
        for (const auto& f : tileset_->autotileFiles) autoTiles_.push_back(f.empty() ? nullptr : loadImage(f));
    }
    needRefresh_ = true;
    if (!graphicsOnly) {
        refreshPages();
        updateCamera();
    }
}

// ---------------------------------------------------------------------------------------------
// Event pages

int Game::activePage(const MapEvent& e, const Character& ch) {
    (void)ch;
    Frame f;
    f.eventId = e.id;
    for (int p = int(e.pages.size()) - 1; p >= 0; p--) {
        const EventPage& page = e.pages[size_t(p)];
        bool ok = true;
        for (const auto& c : page.conditions) {
            if (!c.used) continue;
            int32_t left = getValue(c.left, &f);
            int32_t right = (c.right >= 1000000 || c.right <= -1000000) ? getValue(c.right, &f) : c.right;
            bool r = false;
            switch (c.op) {
                case 0x00: r = left > right; break;
                case 0x10: r = left >= right; break;
                case 0x20: r = left == right; break;
                case 0x30: r = left <= right; break;
                case 0x40: r = left < right; break;
                case 0x50: r = left != right; break;
                case 0x60: r = (left & right) != 0; break;
            }
            if (!r) { ok = false; break; }
        }
        if (ok) return p;
    }
    return -1;
}

void Game::setupPage(Character& ch, const MapEvent& e, int page) {
    if (ch.page == page) return;
    ch.page = page;
    // A parallel page that is no longer active stops.
    auto par = mapParallel_.find(e.id);
    if (par != mapParallel_.end()) mapParallel_.erase(par);
    if (page < 0) {
        ch.graphic.clear();
        ch.tileId = -1;
        ch.through = true;
        return;
    }
    const EventPage& p = e.pages[size_t(page)];
    ch.tileId = p.tileId;
    ch.graphic = p.tileId >= 0 ? std::string() : p.graphic;
    if (p.direction >= 1 && p.direction <= 9) ch.direction = p.direction;
    ch.pattern = std::clamp<int>(p.frame, 0, charPatterns_ - 1);
    ch.opacity = p.opacity;
    ch.blend = p.blend;
    ch.moveType = p.moveType;
    ch.moveSpeed = p.moveSpeed;
    ch.moveFrequency = p.moveFrequency;
    ch.animSpeed = p.animSpeed;
    ch.waitAnim = (p.options & 0x01) != 0;
    ch.moveAnim = (p.options & 0x02) != 0;
    ch.fixedDir = (p.options & 0x04) != 0;
    ch.through = (p.options & 0x08) != 0;
    ch.above = (p.options & 0x10) != 0;
    if (p.options & 0x40) {
        // Placed half a tile up.
        ch.py = e.y * 2 - 1;
        ch.realY = ch.py * tileSize_ / 2.0;
    }
    ch.shadow = p.shadow;
    ch.rangeX = p.rangeX;
    ch.rangeY = p.rangeY;
    if (!ch.routeFromCommand) {
        ch.route = p.route;
        ch.routeIndex = 0;
        ch.routeRepeat = (p.routeFlags & 0x01) != 0 || ch.moveType == 1;
        ch.routeSkip = (p.routeFlags & 0x02) != 0;
        ch.routeDone = ch.moveType != 1 || ch.route.empty();
    }
    if (p.trigger == 2 && !p.commands.empty()) {
        auto ctx = std::make_unique<Context>();
        ctx->kind = Context::Kind::Parallel;
        ctx->mapEventId = e.id;
        Frame f;
        f.commands = &p.commands;
        f.eventId = e.id;
        ctx->frames.push_back(f);
        mapParallel_[e.id] = std::move(ctx);
    }
}

void Game::refreshPages() {
    needRefresh_ = false;
    for (size_t i = 0; i < events_.size() && mapData_; i++) {
        Character& ch = events_[i];
        if (ch.erased) continue;
        int page = activePage(map_.events[i], ch);
        setupPage(ch, map_.events[i], page);
    }
    // The hero and followers take their graphics from SysS[10..15].
    std::string heroGraphic = sysStr_[10];
    hero_.graphic = heroGraphic;
    size_t members = 0;
    for (int i = 11; i <= 15; i++)
        if (!sysStr_[size_t(i)].empty()) members = size_t(i - 10);
    while (party_.size() < members) {
        Character m;
        m.eventId = -2 - int(party_.size());
        m.px = hero_.px;
        m.py = hero_.py;
        m.realX = hero_.realX;
        m.realY = hero_.realY;
        m.direction = hero_.direction;
        m.moveAnim = true;
        m.through = true;
        party_.push_back(m);
    }
    party_.resize(members);
    for (size_t i = 0; i < party_.size(); i++) party_[i].graphic = sysStr_[11 + i];
}

// ---------------------------------------------------------------------------------------------
// Passability

int Game::tileTag(int x, int y, int layer) {
    if (!tileset_) return 0;
    int offset = int(tileset_->autotileFiles.size()) + 1;
    auto tagOf = [&](int chip) -> int {
        int idx = chipIndex(chip, offset);
        return idx >= 0 && size_t(idx) < tileset_->tags.size() ? tileset_->tags[size_t(idx)] : 0;
    };
    if (layer >= 0) return tagOf(map_.tile(layer, x, y));
    for (int l = map_.layers - 1; l >= 0; l--) {
        int chip = map_.tile(l, x, y);
        if (!blankChip(chip)) return tagOf(chip);
    }
    return tagOf(0);
}

// Whether the quarter-tile grid cell (qx, qy) (half-tile units) can be entered, moving in `dir`.
bool Game::tilePassable(int qx, int qy, int dir, bool entering) {
    int x = qx >> 1, y = qy >> 1;
    if (x < 0 || y < 0 || x >= map_.width || y >= map_.height) return false;
    if (!tileset_) return true;
    const auto& passage = passageOverride_.empty() ? tileset_->passage : passageOverride_;
    int offset = int(tileset_->autotileFiles.size()) + 1;
    int quarter = ((qy & 1) ? 0 : 2) + ((qx & 1) ? 0 : 1);  // bit index: RD=0, LD=1, RU=2, LU=3
    for (int l = map_.layers - 1; l >= 0; l--) {
        int chip = map_.tile(l, x, y);
        if (blankChip(chip) && l > 0) continue;
        int idx = chipIndex(chip, offset);
        int code = idx >= 0 && size_t(idx) < passage.size() ? passage[size_t(idx)] : 0;
        if (code & 0x200) continue;  // depends on the layer below
        if (code & 0x20) return ((code >> quarter) & 1) == 0;
        if ((code & 0x0F) == 0x0F) return false;
        if (code & 0x0F) {
            // Directional: 0x01 down, 0x02 left, 0x04 right, 0x08 up cannot be passed.
            int bit = 0;
            int d = dir;
            if (entering) {
                // Entering this tile moving `dir` crosses its opposite edge.
                switch (dir) { case 2: d = 8; break; case 8: d = 2; break; case 4: d = 6; break; case 6: d = 4; break; }
            }
            switch (d) { case 2: bit = 0x01; break; case 4: bit = 0x02; break; case 6: bit = 0x04; break; case 8: bit = 0x08; break; }
            if (code & bit) return false;
        }
        return true;
    }
    return true;
}

bool Game::canPass(const Character& ch, int dir, int fromPx, int fromPy, bool forEvent) {
    (void)forEvent;
    if (ch.through || (ch.eventId == -1 && cheatThrough)) {
        auto [dx, dy] = dirDelta(dir);
        int step = ch.halfStep ? 1 : 2;
        int nx = fromPx + dx * step, ny = fromPy + dy * step;
        return nx >= 0 && ny >= 0 && nx <= (map_.width - 1) * 2 + 1 && ny <= (map_.height - 1) * 2 + 1;
    }
    auto [dx, dy] = dirDelta(dir);
    int step = ch.halfStep ? 1 : 2;
    int nx = fromPx + dx * step, ny = fromPy + dy * step;
    if (nx < 0 || ny < 0 || nx + 1 > map_.width * 2 - 1 + 1 || ny + 1 > map_.height * 2 - 1 + 1) return false;
    // Diagonal moves need both straight moves to be possible.
    if (dx != 0 && dy != 0) {
        if (!canPass(ch, dx < 0 ? 4 : 6, fromPx, fromPy, forEvent)) return false;
        if (!canPass(ch, dy < 0 ? 8 : 2, fromPx, fromPy, forEvent)) return false;
    }
    // Leaving: the edges of the tiles left behind.
    if (dx == 0 || dy == 0) {
        for (int qy = fromPy; qy <= fromPy + 1; qy++)
            for (int qx = fromPx; qx <= fromPx + 1; qx++)
                if (!tilePassable(qx, qy, dir, false) && tilePassable(qx, qy, 0, true)) {
                    // A directional block on the tile we stand on.
                    return false;
                }
    }
    // Entering: every quarter the character covers at the destination.
    for (int qy = ny; qy <= ny + 1; qy++)
        for (int qx = nx; qx <= nx + 1; qx++) {
            bool inside = qx >= fromPx && qx <= fromPx + 1 && qy >= fromPy && qy <= fromPy + 1;
            if (inside) continue;
            if (!tilePassable(qx, qy, dir, true)) return false;
        }
    // Other characters.
    auto blocks = [&](const Character& o) {
        if (&o == &ch || !o.exists || o.erased || o.through) return false;
        if (o.eventId >= 0 && o.page < 0) return false;
        return std::abs(o.px - nx) < 2 && std::abs(o.py - ny) < 2;
    };
    for (const auto& e : events_)
        if (blocks(e)) return false;
    if (ch.eventId != -1 && ch.eventId > -2 && blocks(hero_)) return false;
    return true;
}

// ---------------------------------------------------------------------------------------------
// Movement

bool Game::moveCharacter(Character& ch, int dir, bool turn) {
    if (turn && !ch.fixedDir) setDirection(ch, dir);
    if (!canPass(ch, dir, ch.px, ch.py, ch.eventId >= 0)) {
        if (ch.eventId == -1) {
            auto [dx, dy] = dirDelta(dir);
            checkTouch(ch.px + dx * 2, ch.py + dy * 2, false);
        } else if (ch.eventId >= 0) {
            // An event that walks into the hero ("event touch").
            auto [dx, dy] = dirDelta(dir);
            int step = ch.halfStep ? 1 : 2;
            int nx = ch.px + dx * step, ny = ch.py + dy * step;
            if (std::abs(hero_.px - nx) < 2 && std::abs(hero_.py - ny) < 2 && ch.page >= 0) {
                auto it = eventIndex_.find(ch.eventId);
                if (it != eventIndex_.end() && map_.events[it->second].pages[size_t(ch.page)].trigger == 4)
                    startMapEvent(ch.eventId, true);
            }
        }
        return false;
    }
    auto [dx, dy] = dirDelta(dir);
    int step = ch.halfStep ? 1 : 2;
    ch.px += dx * step;
    ch.py += dy * step;
    double dist = step * tileSize_ / 2.0;
    int frames = std::max(stepFrames(ch) * step / 2, 1);
    ch.dx = dx * dist / frames;
    ch.dy = dy * dist / frames;
    ch.moveRemaining = frames;
    ch.moving = true;
    return true;
}

void Game::startJump(Character& ch, int dx, int dy) {
    ch.px += dx * 2;
    ch.py += dy * 2;
    int frames = std::max(stepFrames(ch), 8) + 8;
    ch.dx = dx * tileSize_ / double(frames);
    ch.dy = dy * tileSize_ / double(frames);
    ch.moveRemaining = frames;
    ch.moving = true;
    ch.jumping = true;
    ch.jumpTotal = frames;
    ch.jumpCount = 0;
}

void Game::processRoute(Character& ch) {
    if (ch.routeDone || ch.route.empty()) return;
    if (ch.routeWait > 0) { ch.routeWait--; return; }
    int guard = 0;
    while (!ch.moving && ch.routeWait == 0 && !ch.routeDone && guard++ < 64) {
        if (ch.routeIndex >= ch.route.size()) {
            if (ch.routeRepeat) ch.routeIndex = 0;
            else {
                ch.routeDone = true;
                if (ch.routeFromCommand) {
                    ch.routeFromCommand = false;
                    // Back to the page's own route.
                    if (ch.eventId >= 0 && ch.page >= 0 && mapData_) {
                        auto it = eventIndex_.find(ch.eventId);
                        if (it != eventIndex_.end()) {
                            const EventPage& p = map_.events[it->second].pages[size_t(ch.page)];
                            ch.route = p.route;
                            ch.routeIndex = 0;
                            ch.routeRepeat = true;
                            ch.routeDone = ch.moveType != 1 || ch.route.empty();
                        }
                    }
                }
                return;
            }
        }
        const RouteCommand& rc = ch.route[ch.routeIndex];
        auto arg = [&](size_t i) { return i < rc.args.size() ? rc.args[i] : 0; };
        bool advance = true;
        int id = rc.id;
        if (id <= 0x07) {
            static const int dirs[] = {2, 4, 6, 8, 1, 3, 7, 9};
            if (!moveCharacter(ch, dirs[id]) && !ch.routeSkip) advance = false;
        } else if (id <= 0x0F) {
            static const int dirs[] = {2, 4, 6, 8, 1, 3, 7, 9};
            setDirection(ch, dirs[id - 8]);
        } else {
            switch (id) {
                case 0x10: {
                    static const int dirs[] = {2, 4, 6, 8};
                    moveCharacter(ch, dirs[rng_() % 4]);
                    break;
                }
                case 0x11: case 0x12: {
                    int dx = hero_.px - ch.px, dy = hero_.py - ch.py;
                    if (id == 0x12) { dx = -dx; dy = -dy; }
                    int dir = std::abs(dx) > std::abs(dy) ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2);
                    if (dx == 0 && dy == 0) break;
                    if (!moveCharacter(ch, dir)) {
                        int alt = std::abs(dx) > std::abs(dy) ? (dy < 0 ? 8 : dy > 0 ? 2 : 0) : (dx < 0 ? 4 : dx > 0 ? 6 : 0);
                        if (alt) moveCharacter(ch, alt);
                    }
                    break;
                }
                case 0x13: if (!moveCharacter(ch, ch.direction) && !ch.routeSkip) advance = false; break;
                case 0x14: {
                    int back = 10 - ch.direction;
                    if (!moveCharacter(ch, back, false) && !ch.routeSkip) advance = false;
                    break;
                }
                case 0x15: startJump(ch, arg(0), arg(1)); break;
                case 0x16: { static const int r[] = {0, 4, 1, 2, 7, 0, 3, 8, 9, 6}; setDirection(ch, r[ch.direction]); break; }
                case 0x17: { static const int l[] = {0, 2, 3, 6, 1, 0, 9, 4, 7, 8}; setDirection(ch, l[ch.direction]); break; }
                case 0x18: {
                    static const int r[] = {0, 4, 1, 2, 7, 0, 3, 8, 9, 6}, l[] = {0, 2, 3, 6, 1, 0, 9, 4, 7, 8};
                    setDirection(ch, (rng_() & 1) ? r[ch.direction] : l[ch.direction]);
                    break;
                }
                case 0x19: { static const int d[] = {2, 4, 6, 8}; setDirection(ch, d[rng_() % 4]); break; }
                case 0x1A: setDirection(ch, 10 - ch.direction); break;
                case 0x1B: {
                    int dx = hero_.px - ch.px, dy = hero_.py - ch.py;
                    setDirection(ch, std::abs(dx) > std::abs(dy) ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2));
                    break;
                }
                case 0x1C: case 0x37: {
                    Frame f;
                    f.eventId = ch.eventId;
                    int32_t var = arg(0), v = arg(1);
                    if (id == 0x37) v += getValue(var, &f);
                    setValue(var, v, &f);
                    break;
                }
                case 0x1D: ch.moveSpeed = arg(0); break;
                case 0x1E: ch.moveFrequency = arg(0); break;
                case 0x1F: ch.animSpeed = arg(0); break;
                case 0x20: ch.waitAnim = true; break;
                case 0x21: ch.waitAnim = false; break;
                case 0x22: ch.moveAnim = true; break;
                case 0x23: ch.moveAnim = false; break;
                case 0x24: ch.fixedDir = true; break;
                case 0x25: ch.fixedDir = false; break;
                case 0x26: ch.through = true; break;
                case 0x27: ch.through = false; break;
                case 0x28: ch.above = true; break;
                case 0x29: ch.above = false; break;
                case 0x2C: {
                    // Graphic from the system DB character images (type 8); negative: a tile.
                    int g = arg(0);
                    std::string file = sdbFile(8, g);
                    if (!file.empty()) { ch.graphic = file; ch.tileId = -1; }
                    break;
                }
                case 0x2D: ch.opacity = std::clamp(arg(0), 0, 255); if (rc.args.size() > 1) ch.blend = arg(1); break;
                case 0x2E: playSound(Channel::SE, arg(0), "", 100, 100, 0, 0, 0); break;
                case 0x2F: ch.routeWait = std::max(arg(0), 0); break;
                case 0x30: ch.halfStep = true; break;
                case 0x31: ch.halfStep = false; ch.px &= ~1; ch.py &= ~1; break;
                case 0x32: ch.pattern = 0; break;
                case 0x33: ch.pattern = 1; break;
                case 0x34: ch.pattern = 2; break;
                case 0x38: ch.pattern = 3; break;
                case 0x39: ch.pattern = 4; break;
                case 0x35: {
                    Character* t = eventChar(arg(0));
                    if (t) {
                        int dx = t->px - ch.px, dy = t->py - ch.py;
                        if (dx || dy) moveCharacter(ch, std::abs(dx) > std::abs(dy) ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2));
                    }
                    break;
                }
                case 0x36: {
                    int dx = arg(0) * 2 - ch.px, dy = arg(1) * 2 - ch.py;
                    if (dx || dy) moveCharacter(ch, std::abs(dx) > std::abs(dy) ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2));
                    break;
                }
                case 0x3A: ch.height = arg(0); break;
                default: break;
            }
        }
        if (!advance) {
            // Blocked: try again next frame.
            return;
        }
        ch.routeIndex++;
        // A move takes its frames; other commands run on.
        if (ch.moving) break;
    }
}

void Game::updateCharacter(Character& ch) {
    if (ch.moving) {
        ch.realX += ch.dx;
        ch.realY += ch.dy;
        if (ch.jumping) ch.jumpCount++;
        if (--ch.moveRemaining <= 0) {
            ch.moving = false;
            ch.jumping = false;
            ch.realX = ch.px * tileSize_ / 2.0;
            ch.realY = ch.py * tileSize_ / 2.0;
        }
        if (ch.moveAnim || ch.eventId < 0) {
            ch.animCounter++;
            int wait = std::max(stepFrames(ch) / 2, 2);
            if (ch.animCounter >= wait) {
                ch.animCounter = 0;
                ch.idleCounter = (ch.idleCounter + 1) % 4;
                int stand = charPatterns_ / 2;
                static const int cycle3[] = {1, 0, 1, 2};
                ch.pattern = charPatterns_ == 3 ? cycle3[(ch.idleCounter + 1) % 4] : (stand + (ch.idleCounter % 2 ? -1 : 1) * (ch.idleCounter / 2 + 1)) % charPatterns_;
                if (charPatterns_ == 5) {
                    static const int cycle5[] = {2, 3, 4, 3, 2, 1, 0, 1};
                    ch.pattern = cycle5[size_t(ch.idleCounter * 2 % 8)];
                }
            }
        }
    } else {
        if (ch.waitAnim) {
            ch.animCounter++;
            if (ch.animCounter >= kAnimWait[std::clamp(ch.animSpeed, 0, 6)]) {
                ch.animCounter = 0;
                ch.idleCounter = (ch.idleCounter + 1) % 4;
                static const int cycle3[] = {1, 2, 1, 0};
                ch.pattern = charPatterns_ == 3 ? cycle3[ch.idleCounter] : ch.idleCounter % charPatterns_;
            }
        } else if (ch.moveAnim) {
            // Back to the standing frame after a short pause.
            if (++ch.stopCounter > 4 && ch.pattern != charPatterns_ / 2 && ch.stopCounter < 1000) {
                ch.pattern = charPatterns_ / 2;
                ch.idleCounter = 0;
            }
        }
    }
    if (!ch.moving) ch.stopCounter++;
    else ch.stopCounter = 0;
    if (ch.flashFrames > 0) ch.flashFrames--;
    if (ch.shakeFrames > 0) ch.shakeFrames--;
}

void Game::updateHeroInput() {
    if (hero_.moving) return;
    // A route given to the hero runs instead of the player's input.
    if (!hero_.routeDone) return;
    int dir = 0;
    auto walk = [&](int k) { return input_.down[k] && inputBanned_[k] == 0; };
    bool u = walk(KeyUp), d = walk(KeyDown), l = walk(KeyLeft), r = walk(KeyRight);
    bool eight = project_->game.setting(2) == 8;
    if (eight) {
        if (d && l) dir = 1; else if (d && r) dir = 3; else if (u && l) dir = 7; else if (u && r) dir = 9;
    }
    if (!dir) {
        if (d) dir = 2; else if (l) dir = 4; else if (r) dir = 6; else if (u) dir = 8;
    }
    if (dir) {
        int oldX = hero_.px, oldY = hero_.py;
        // Followers walk where the one ahead was.
        std::vector<std::pair<int, int>> trail;
        trail.push_back({hero_.px, hero_.py});
        for (auto& m : party_) trail.push_back({m.px, m.py});
        if (moveCharacter(hero_, dir)) {
            for (size_t i = 0; i < party_.size(); i++) {
                Character& m = party_[i];
                int tx = trail[i].first, ty = trail[i].second;
                int mdx = (tx - m.px), mdy = (ty - m.py);
                if (mdx == 0 && mdy == 0) continue;
                int md = mdx < 0 ? (mdy < 0 ? 7 : mdy > 0 ? 1 : 4) : mdx > 0 ? (mdy < 0 ? 9 : mdy > 0 ? 3 : 6) : (mdy < 0 ? 8 : 2);
                setDirection(m, md);
                m.px = tx;
                m.py = ty;
                int frames = std::max(int(hero_.moveRemaining), 1);
                m.dx = (tx * tileSize_ / 2.0 - m.realX) / frames;
                m.dy = (ty * tileSize_ / 2.0 - m.realY) / frames;
                m.moveRemaining = frames;
                m.moving = true;
                m.moveSpeed = hero_.moveSpeed;
            }
            (void)oldX;
            (void)oldY;
        }
    }
    if (pressed(KeyOK) && inputBanned_[KeyOK] == 0) checkAction();
}

void Game::checkTouch(int px, int py, bool heroMoved) {
    (void)heroMoved;
    if (mainEventRunning()) return;
    for (const auto& e : events_) {
        if (!e.exists || e.erased || e.page < 0) continue;
        if (std::abs(e.px - px) < 2 + e.rangeX * 2 && std::abs(e.py - py) < 2 + e.rangeY * 2) {
            const EventPage& p = map_.events[eventIndex_[e.eventId]].pages[size_t(e.page)];
            if (p.trigger == 3 || p.trigger == 4) {
                startMapEvent(e.eventId, true);
                return;
            }
        }
    }
}

void Game::checkAction() {
    if (mainEventRunning() || msg_.open) return;
    auto [dx, dy] = dirDelta(hero_.direction);
    int fx = hero_.px + dx * 2, fy = hero_.py + dy * 2;
    // The event in front, then one under the hero.
    for (int pass = 0; pass < 2; pass++) {
        int tx = pass == 0 ? fx : hero_.px, ty = pass == 0 ? fy : hero_.py;
        for (const auto& e : events_) {
            if (!e.exists || e.erased || e.page < 0) continue;
            if (std::abs(e.px - tx) < 2 + e.rangeX * 2 && std::abs(e.py - ty) < 2 + e.rangeY * 2) {
                const EventPage& p = map_.events[eventIndex_[e.eventId]].pages[size_t(e.page)];
                if (p.trigger == 0) {
                    // Events face the hero when spoken to.
                    Character* ch = eventChar(e.eventId);
                    if (ch && !ch->fixedDir && !ch->graphic.empty()) setDirection(*ch, 10 - hero_.direction);
                    startMapEvent(e.eventId, true);
                    return;
                }
            }
        }
    }
}

void Game::startMapEvent(int eventId, bool asMain) {
    auto it = eventIndex_.find(eventId);
    if (it == eventIndex_.end()) return;
    Character& ch = events_[it->second];
    if (ch.page < 0) return;
    const EventPage& p = map_.events[it->second].pages[size_t(ch.page)];
    if (p.commands.empty()) return;
    auto ctx = std::make_unique<Context>();
    ctx->kind = asMain ? Context::Kind::Main : Context::Kind::Parallel;
    ctx->mapEventId = eventId;
    Frame f;
    f.commands = &p.commands;
    f.eventId = eventId;
    ctx->frames.push_back(f);
    contexts_.push_back(std::move(ctx));
}

void Game::updateMap() {
    bool mainRunning = mainEventRunning();
    bool canMove = (!mainRunning || moveDuringEvents_) && !msg_.open && !pendingTransfer_ && fx_.transFrames == 0;
    if (canMove) {
        bool wasMoving = hero_.moving;
        updateHeroInput();
        (void)wasMoving;
    }
    // Hero route (move route commands targeting the hero).
    processRoute(hero_);
    bool heroWasMoving = hero_.moving;
    updateCharacter(hero_);
    for (auto& m : party_) updateCharacter(m);
    if (heroWasMoving && !hero_.moving && canMove) {
        // Arrived: events that are touched by standing on them.
        checkTouch(hero_.px, hero_.py, true);
    }
    for (auto& e : events_) {
        if (e.erased || e.page < 0) {
            updateCharacter(e);
            continue;
        }
        if (!e.routeDone || (e.moveType == 1 && !e.route.empty())) {
            if (!e.moving) {
                if (e.routeDone && e.moveType == 1 && !e.route.empty() && e.routeRepeat) e.routeDone = false;
                if (e.routeFromCommand || !mainRunning || true) processRoute(e);
            }
        } else if (!e.moving && !mainRunning && (e.moveType == 2 || e.moveType == 3)) {
            if (++e.idleCounter > kMoveWait[std::clamp(e.moveFrequency, 0, 6)] + int(rng_() % 16)) {
                e.idleCounter = 0;
                if (e.moveType == 2) {
                    static const int dirs[] = {2, 4, 6, 8};
                    moveCharacter(e, dirs[rng_() % 4]);
                } else {
                    int dx = hero_.px - e.px, dy = hero_.py - e.py;
                    if (dx || dy) moveCharacter(e, std::abs(dx) > std::abs(dy) ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2));
                }
            }
        }
        updateCharacter(e);
    }
    // Auto-run pages.
    if (!mainEventRunning()) {
        for (const auto& e : events_) {
            if (e.erased || e.page < 0) continue;
            const EventPage& p = map_.events[eventIndex_[e.eventId]].pages[size_t(e.page)];
            if (p.trigger == 1 && !p.commands.empty()) {
                startMapEvent(e.eventId, true);
                break;
            }
        }
    }
    updateCamera();
}

void Game::updateCamera() {
    if (fx_.scrolling) {
        double sx = fx_.scrollTargetX - fx_.scrollX, sy = fx_.scrollTargetY - fx_.scrollY;
        double d = std::sqrt(sx * sx + sy * sy);
        if (d <= fx_.scrollSpeed) {
            fx_.scrollX = fx_.scrollTargetX;
            fx_.scrollY = fx_.scrollTargetY;
            fx_.scrolling = false;
        } else {
            fx_.scrollX += sx / d * fx_.scrollSpeed;
            fx_.scrollY += sy / d * fx_.scrollSpeed;
        }
    }
    if (fx_.scrollLocked) return;
    double cx = hero_.realX + tileSize_ / 2.0 - screenW_ / 2.0 + fx_.scrollX;
    double cy = hero_.realY + tileSize_ / 2.0 - screenH_ / 2.0 + fx_.scrollY;
    double maxX = map_.width * tileSize_ - screenW_, maxY = map_.height * tileSize_ - screenH_;
    camX_ = maxX <= 0 ? 0 : std::clamp(cx, 0.0, maxX);
    camY_ = maxY <= 0 ? 0 : std::clamp(cy, 0.0, maxY);
    camX_ = std::floor(camX_);
    camY_ = std::floor(camY_);
}

// ---------------------------------------------------------------------------------------------
// Drawing

void Game::drawTiles(int layerMask, double camX, double camY, bool upper) {
    if (!tileset_) return;
    const auto& passage = passageOverride_.empty() ? tileset_->passage : passageOverride_;
    int offset = int(tileset_->autotileFiles.size()) + 1;
    int ts = tileSize_, half = ts / 2;
    int x0 = int(std::floor(camX / ts)), y0 = int(std::floor(camY / ts));
    int cols = screenW_ / ts + 2, rows = screenH_ / ts + 2;
    int frame = (frameCount_ / 16);
    for (int l = 0; l < map_.layers; l++) {
        if (!((layerMask >> l) & 1)) continue;
        for (int ty = y0; ty < y0 + rows; ty++) {
            for (int tx = x0; tx < x0 + cols; tx++) {
                int chip = map_.tile(l, tx, ty);
                if (blankChip(chip)) continue;
                int idx = chipIndex(chip, offset);
                int code = idx >= 0 && size_t(idx) < passage.size() ? passage[size_t(idx)] : 0;
                bool isUpper = (code & 0x10) != 0;
                if (isUpper != upper) continue;
                float sx = float(tx * ts - camX), sy = float(ty * ts - camY);
                if (chip >= 100000) {
                    int a = chip / 100000 - 2;
                    if (a < 0 || size_t(a) >= autoTiles_.size() || !autoTiles_[size_t(a)]) continue;
                    const TexturePtr& t = autoTiles_[size_t(a)];
                    int frames = std::max(t->width() / ts, 1);
                    int fx = (frame % frames) * ts;
                    int parts[4] = {chip / 1000 % 10, chip / 100 % 10, chip / 10 % 10, chip % 10};  // LU RU LD RD
                    for (int q = 0; q < 4; q++) {
                        int qx = q & 1, qy = q >> 1;
                        RectI src{fx + qx * half, parts[q] * ts + qy * half, half, half};
                        PointF p[4] = {{sx + qx * half, sy + qy * half}, {sx + qx * half + half, sy + qy * half},
                                       {sx + qx * half + half, sy + qy * half + half}, {sx + qx * half, sy + qy * half + half}};
                        gfx_.drawQuad(t, src, p, Color{}, Blend::Normal);
                    }
                } else if (baseTiles_) {
                    int perRow = std::max(baseTiles_->width() / ts, 1);
                    RectI src{(chip % perRow) * ts, (chip / perRow) * ts, ts, ts};
                    PointF p[4] = {{sx, sy}, {sx + ts, sy}, {sx + ts, sy + ts}, {sx, sy + ts}};
                    gfx_.drawQuad(baseTiles_, src, p, Color{}, Blend::Normal);
                }
            }
        }
    }
}

void Game::drawCharacter(const Character& ch, double camX, double camY) {
    if (!ch.exists || ch.erased || ch.opacity <= 0) return;
    if (ch.flickerMode && (frameCount_ / 4) % 2) return;
    double shake = ch.shakeFrames > 0 ? std::sin(frameCount_ * 1.7) * ch.shakePower : 0;
    double jump = 0;
    if (ch.jumping && ch.jumpTotal > 0) {
        double t = double(ch.jumpCount) / ch.jumpTotal;
        jump = std::sin(t * M_PI) * tileSize_ * 0.6;
    }
    Color mod{255, 255, 255, uint8_t(std::clamp(ch.opacity, 0, 255))};
    Blend blend = ch.blend == 1 ? Blend::Add : ch.blend == 2 ? Blend::Subtract : ch.blend == 3 ? Blend::Multiply : Blend::Normal;
    if (ch.tileId >= 0) {
        if (!baseTiles_) return;
        int ts = tileSize_;
        int perRow = std::max(baseTiles_->width() / ts, 1);
        int chip = ch.tileId;
        RectI src{(chip % perRow) * ts, (chip / perRow) * ts, ts, ts};
        float sx = float(ch.realX - camX + shake), sy = float(ch.realY - camY - ch.height - jump);
        PointF p[4] = {{sx, sy}, {sx + ts, sy}, {sx + ts, sy + ts}, {sx, sy + ts}};
        gfx_.drawQuad(baseTiles_, src, p, mod, blend);
        return;
    }
    if (ch.graphic.empty()) return;
    TexturePtr t = loadImage(ch.graphic);
    if (!t) return;
    int rows = charDirs_;
    int fw = t->width() / charPatterns_, fh = t->height() / rows;
    if (fw <= 0 || fh <= 0) return;
    int row = dirIndex(ch.direction, rows);
    int col = std::clamp(ch.pattern, 0, charPatterns_ - 1);
    RectI src{col * fw, row * fh, fw, fh};
    float sx = float(ch.realX - camX + tileSize_ / 2.0 - fw / 2.0 + shake);
    float sy = float(ch.realY - camY + tileSize_ - fh - ch.height - jump);
    PointF p[4] = {{sx, sy}, {sx + fw, sy}, {sx + fw, sy + fh}, {sx, sy + fh}};
    gfx_.drawQuad(t, src, p, mod, blend);
    if (ch.flashFrames > 0 && ch.flashTotal > 0) {
        Color fc = ch.flashColor;
        fc.a = uint8_t(255 * ch.flashFrames / ch.flashTotal);
        gfx_.drawQuad(t, src, p, fc, Blend::Add);
    }
}

void Game::drawMap() {
    double camX = camX_, camY = camY_ + fx_.shakeOffset * (fx_.shakeType == 0 ? 1 : 0);
    if (fx_.shakeType == 1) camX += fx_.shakeOffset;
    if (panorama_) {
        float w = float(panorama_->width()), h = float(panorama_->height());
        float ox = float(-std::fmod(camX * 0.5, double(w))), oy = float(-std::fmod(camY * 0.5, double(h)));
        for (float y = oy; y < screenH_; y += h)
            for (float x = ox; x < screenW_; x += w) {
                PointF p[4] = {{x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}};
                gfx_.drawQuad(panorama_, RectI{0, 0, int(w), int(h)}, p, Color{}, Blend::Normal);
            }
    }
    drawTiles(0x7FFF, camX, camY, false);
    // Characters by their feet.
    std::vector<const Character*> chars;
    for (const auto& e : events_)
        if (!e.above && e.page >= 0) chars.push_back(&e);
    if (partyVisible_)
        for (auto it = party_.rbegin(); it != party_.rend(); ++it) chars.push_back(&*it);
    if (heroVisible_) chars.push_back(&hero_);
    std::stable_sort(chars.begin(), chars.end(), [](const Character* a, const Character* b) { return a->realY < b->realY; });
    for (const Character* c : chars) drawCharacter(*c, camX, camY);
    drawTiles(0x7FFF, camX, camY, true);
    for (const auto& e : events_)
        if (e.above && e.page >= 0) drawCharacter(e, camX, camY);
}

}  // namespace wolf
