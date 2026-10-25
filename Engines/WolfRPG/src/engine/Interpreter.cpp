// The event interpreter: runs event command lists (map event pages and common events).
#include <algorithm>
#include <cmath>
#include <cstring>
#include <unordered_map>

#include "Game.hpp"

namespace wolf {

namespace {

constexpr int32_t kMax = 999999999;

int32_t clamp32(double v) {
    if (v > kMax) return kMax;
    if (v < -kMax) return -kMax;
    return int32_t(v);
}

int32_t clamp64(int64_t v) {
    if (v > kMax) return kMax;
    if (v < -kMax) return -kMax;
    return int32_t(v);
}

// Branch and loop structure of a command list, by indent: computed once per list.
struct Flow {
    std::vector<int> next;   // case markers (401/402/420/421) and branch starts: the next marker or the 499
    std::vector<int> end;    // case markers and branch starts: their 499; loop starts: their 498
    std::vector<int> start;  // 498: its loop start
};

Flow buildFlow(const CommandList& list) {
    Flow f;
    size_t n = list.size();
    f.next.assign(n, -1);
    f.end.assign(n, -1);
    f.start.assign(n, -1);
    struct Open { int index; int indent; bool loop; int lastMarker; };
    std::vector<Open> stack;
    for (size_t i = 0; i < n; i++) {
        const Command& c = list[i];
        int ind = c.indent;
        switch (c.code) {
            case 102: case 111: case 112:
                stack.push_back({int(i), ind, false, int(i)});
                break;
            case 401: case 402: case 420: case 421:
                for (auto it = stack.rbegin(); it != stack.rend(); ++it) {
                    if (!it->loop && it->indent == ind) {
                        f.next[size_t(it->lastMarker)] = int(i);
                        it->lastMarker = int(i);
                        break;
                    }
                }
                break;
            case 499:
                for (size_t k = stack.size(); k-- > 0;) {
                    if (!stack[k].loop && stack[k].indent == ind) {
                        f.next[size_t(stack[k].lastMarker)] = int(i);
                        f.end[size_t(stack[k].index)] = int(i);
                        // Every marker of this branch ends here.
                        int m = f.next[size_t(stack[k].index)];
                        while (m >= 0 && m < int(i)) {
                            f.end[size_t(m)] = int(i);
                            m = f.next[size_t(m)];
                        }
                        stack.erase(stack.begin() + long(k), stack.end());
                        break;
                    }
                }
                break;
            case 170: case 179:
                stack.push_back({int(i), ind, true, int(i)});
                break;
            case 498:
                for (size_t k = stack.size(); k-- > 0;) {
                    if (stack[k].loop && stack[k].indent == ind) {
                        f.end[size_t(stack[k].index)] = int(i);
                        f.start[i] = stack[k].index;
                        stack.erase(stack.begin() + long(k), stack.end());
                        break;
                    }
                }
                break;
        }
    }
    return f;
}

const Flow& flowOf(const CommandList* list) {
    static std::unordered_map<const CommandList*, Flow> cache;
    auto it = cache.find(list);
    if (it != cache.end()) return it->second;
    return cache.emplace(list, buildFlow(*list)).first->second;
}

bool compare(int32_t left, int32_t right, int op) {
    switch (op) {
        case 0: return left > right;
        case 1: return left >= right;
        case 2: return left == right;
        case 3: return left <= right;
        case 4: return left < right;
        case 5: return left != right;
        case 6: return (left & right) != 0;
    }
    return false;
}

bool isAddress(int32_t v) { return v >= 1000000 || v <= -1000000; }

}  // namespace

// ---------------------------------------------------------------------------------------------
// Text with variables: \v[n], \s[n], \self[n], \cself[n], \sys[n], \sysS[n], \cdb[t:d:i], …

std::string Game::expandText(const std::string& text, const Frame* frame, int depth) {
    if (text.find('\\') == std::string::npos || depth > 8) return text;
    std::string out;
    out.reserve(text.size());
    size_t i = 0;
    auto readArg = [&](size_t open, size_t& close) -> std::string {
        // Brackets may nest ("\v[\cself[3]]").
        int level = 0;
        for (size_t k = open; k < text.size(); k++) {
            if (text[k] == '[') level++;
            else if (text[k] == ']' && --level == 0) {
                close = k;
                return expandText(text.substr(open + 1, k - open - 1), frame, depth + 1);
            }
        }
        close = std::string::npos;
        return {};
    };
    auto num = [](const std::string& s) { return int32_t(std::strtol(s.c_str(), nullptr, 10)); };
    while (i < text.size()) {
        if (text[i] != '\\' || i + 1 >= text.size()) {
            out += text[i++];
            continue;
        }
        if (text[i + 1] == '\\') {  // a literal backslash stays escaped for the renderer
            out += "\\\\";
            i += 2;
            continue;
        }
        size_t j = i + 1;
        while (j < text.size() && (std::isalpha(static_cast<unsigned char>(text[j])) || text[j] == '?')) j++;
        std::string code = text.substr(i + 1, j - i - 1);
        if (j < text.size() && text[j] == '[') {
            std::string lower = code;
            for (auto& ch : lower) ch = char(std::tolower(static_cast<unsigned char>(ch)));
            bool var = lower == "v" || lower == "s" || lower == "self" || lower == "cself" || lower == "sys" ||
                       lower == "syss" || lower == "cdb" || lower == "udb" || lower == "sdb" || lower == "v?" ||
                       lower == "sp";
            if (var) {
                size_t close;
                std::string arg = readArg(j, close);
                if (close != std::string::npos) {
                    std::string value;
                    if (code == "v" || code == "V") value = std::to_string(getValue(2000000 + num(arg), frame));
                    else if (code == "s" || code == "S") value = getString(3000000 + num(arg), frame);
                    else if (lower == "self") value = std::to_string(getValue(1100000 + num(arg), frame));
                    else if (lower == "cself") {
                        int n = num(arg);
                        value = (n >= 5 && n <= 9) ? getString(1600000 + n, frame) : std::to_string(getValue(1600000 + n, frame));
                    } else if (code == "sysS" || code == "syss" || code == "SysS") value = getString(9900000 + num(arg), frame);
                    else if (lower == "sys") value = std::to_string(getValue(9000000 + num(arg), frame));
                    else if (lower == "cdb" || lower == "udb" || lower == "sdb") {
                        int parts[3] = {0, 0, 0};
                        size_t p = 0, s = 0;
                        for (int k = 0; k < 3; k++) {
                            p = arg.find(':', s);
                            parts[k] = num(arg.substr(s, p == std::string::npos ? std::string::npos : p - s));
                            if (p == std::string::npos) break;
                            s = p + 1;
                        }
                        int db = lower == "udb" ? 0 : lower == "cdb" ? 1 : 2;
                        value = dbString(db, parts[0], parts[1], parts[2]);
                    } else if (lower == "sp") {
                        // \sp[n] is a speed code, not a variable: keep it.
                        value = "\\" + code + "[" + arg + "]";
                    } else {
                        value = std::to_string(getValue(2000000 + num(arg), frame));
                    }
                    // Values may contain codes themselves.
                    out += lower == "sp" ? value : expandText(value, frame, depth + 1);
                    i = close + 1;
                    continue;
                }
            }
            // Other codes: keep them, but expand variables inside their brackets.
            size_t close;
            std::string arg = readArg(j, close);
            if (close != std::string::npos) {
                out += "\\" + code + "[" + arg + "]";
                i = close + 1;
                continue;
            }
        }
        out += '\\';
        i++;
    }
    return out;
}

// ---------------------------------------------------------------------------------------------

void Game::callCommon(Context& ctx, int commonId, const Command* call, int32_t returnTo, const std::vector<int32_t>& numArgs,
                      const std::vector<std::string>& strArgs, bool hasStrArgs) {
    (void)call;
    if (commonId < 0 || size_t(commonId) >= project_->commons.size()) return;
    const CommonEvent& c = project_->commons[size_t(commonId)];
    if (ctx.frames.size() > 2000) {
        log("common event recursion too deep at " + std::to_string(commonId));
        return;
    }
    Frame f;
    f.commands = &c.commands;
    f.commonId = commonId;
    f.returnTo = returnTo;
    f.eventId = ctx.frames.empty() ? ctx.mapEventId : ctx.frames.back().eventId;
    auto& self = commonSelf_[commonId];
    auto& selfStr = commonSelfStr_[commonId];
    // Arguments: CSelf0.. for numbers, CSelf5.. for strings; missing ones take their defaults.
    for (size_t i = 0; i < numArgs.size() && i < 5; i++) self[i] = numArgs[i];
    for (size_t i = numArgs.size(); i < c.argDefaults.size() && i < 5 && i < c.numArgs; i++) self[i] = c.argDefaults[i];
    if (hasStrArgs)
        for (size_t i = 0; i < strArgs.size() && i < 5; i++) selfStr[i] = strArgs[i];
    ctx.frames.push_back(std::move(f));
}

void Game::callMapEventPage(Context& ctx, int eventId, int page) {
    auto it = eventIndex_.find(eventId);
    if (it == eventIndex_.end() || !mapData_) return;
    const MapEvent& e = mapData_->events[it->second];
    if (page < 0) page = events_[it->second].page;
    if (page < 0 || size_t(page) >= e.pages.size()) return;
    Frame f;
    f.commands = &e.pages[size_t(page)].commands;
    f.eventId = eventId;
    ctx.frames.push_back(std::move(f));
}

int Game::resolveCommonId(int32_t id, const std::string& name, const Frame& frame) {
    if (!name.empty()) {
        static std::unordered_map<std::string, int> byName;
        static const Project* owner = nullptr;
        if (owner != project_.get()) {
            byName.clear();
            owner = project_.get();
            for (size_t i = 0; i < project_->commons.size(); i++)
                byName.emplace(project_->commons[i].name, int(i));
        }
        std::string n = expandText(name, &frame);
        auto it = byName.find(n);
        if (it != byName.end()) return it->second;
        log("no common event named " + n);
        return -1;
    }
    if (id >= 1000000) id = getValue(id, &frame);
    if (id >= 500000 && id < 600000) return id - 500000;
    // Relative to the calling common event: 600100 is itself, 600101 the next one, …
    if (id >= 600000 && id < 700000 && frame.commonId >= 0) return frame.commonId + (id - 600100);
    return -1;
}

void Game::runContext(Context& ctx) {
    if (ctx.finished()) return;
    if (ctx.waitFrames > 0) {
        ctx.waitFrames--;
        return;
    }
    switch (ctx.wait) {
        case Context::Wait::None: break;
        case Context::Wait::Message:
            if (msg_.open && !(msg_.done && !msg_.waitingKey)) return;
            ctx.wait = Context::Wait::None;
            break;
        case Context::Wait::Choice: {
            if (msg_.choosing) return;
            ctx.wait = Context::Wait::None;
            // Jump to the chosen case of the choice at waitArg.
            Frame& f = ctx.frames.back();
            const Flow& flow = flowOf(f.commands);
            int r = msg_.result;
            int target = -1;
            for (int m = flow.next[size_t(ctx.waitArg)]; m >= 0; m = flow.next[size_t(m)]) {
                const Command& mc = (*f.commands)[size_t(m)];
                if (mc.code == 499) { target = m; break; }
                if (r >= 0 && mc.code == 401 && mc.arg(0) == r + 2) { target = m; break; }
                if (r == -2 && mc.code == 421) { target = m; break; }
                if (r == -3 && mc.code == 402 && mc.arg(0) == 0x64) { target = m; break; }
                if (r == -4 && mc.code == 402 && mc.arg(0) == 0x65) { target = m; break; }
                if (r == -5 && mc.code == 402 && mc.arg(0) == 0x66) { target = m; break; }
            }
            if (target < 0) target = flow.end[size_t(ctx.waitArg)];
            f.pc = target >= 0 ? size_t(target) + 1 : f.pc;
            msg_.open = false;
            break;
        }
        case Context::Wait::MoveRoute: {
            bool busy = false;
            if (ctx.waitArg == -1000) {
                // Wait for every character with a commanded route.
                if (!hero_.routeDone && hero_.routeFromCommand) busy = true;
                for (auto& c : events_) if (!c.routeDone && c.routeFromCommand) busy = true;
                for (auto& c : party_) if (!c.routeDone && c.routeFromCommand) busy = true;
            } else if (Character* ch = character(ctx.waitArg, ctx.frames.empty() ? nullptr : &ctx.frames.back())) {
                busy = !ch->routeDone;
            }
            if (busy) return;
            ctx.wait = Context::Wait::None;
            break;
        }
        case Context::Wait::KeyInput: {
            Frame& f = ctx.frames.back();
            if (!execKeyInput(ctx, *ctx.waitCmd, f, false)) return;
            ctx.wait = Context::Wait::None;
            break;
        }
        case Context::Wait::Transition:
            if (fx_.transFrames > 0) return;
            ctx.wait = Context::Wait::None;
            break;
        case Context::Wait::Erase:
            ctx.wait = Context::Wait::None;
            break;
        case Context::Wait::PictureText:
        case Context::Wait::StringInput:
            ctx.wait = Context::Wait::None;
            break;
    }
    int budget = 300000;
    while (!ctx.finished() && ctx.wait == Context::Wait::None && ctx.waitFrames == 0) {
        if (--budget <= 0) {
            log("event command limit reached in one frame");
            break;
        }
        if (!step(ctx)) break;
    }
}

void Game::skipToBranchEnd(Frame& f, size_t from) {
    const Flow& flow = flowOf(f.commands);
    int e = flow.end[from];
    f.pc = e >= 0 ? size_t(e) + 1 : f.commands->size();
}

bool Game::step(Context& ctx) {
    Frame& f = ctx.frames.back();
    if (f.pc >= f.commands->size()) {
        // End of the list: return to the caller, with the common event's return value.
        Frame done = std::move(f);
        ctx.frames.pop_back();
        if (done.returnTo != 0 && done.commonId >= 0) {
            const CommonEvent& c = project_->commons[size_t(done.commonId)];
            int rv = c.returnVar;
            if (rv >= 0 && !ctx.frames.empty()) {
                Frame& caller = ctx.frames.back();
                if (rv >= 5 && rv <= 9) {
                    std::string s = commonSelfStr_[done.commonId][size_t(rv - 5)];
                    setString(done.returnTo, s, &caller);
                } else {
                    setValue(done.returnTo, commonSelf_[done.commonId][size_t(std::min(rv, 99))], &caller);
                }
            }
        }
        return !ctx.frames.empty();
    }
    const CommandList& list = *f.commands;
    size_t index = f.pc;
    const Command& c = list[index];
    f.pc++;
    if (trace) {
        std::string line = "trace c" + std::to_string(f.commonId) + " e" + std::to_string(f.eventId) + " @" +
                           std::to_string(index) + " " + std::to_string(c.code);
        for (auto a : c.args) line += " " + std::to_string(a);
        for (auto& st : c.strings) line += " \"" + st.substr(0, 40) + "\"";
        log(line);
    }
    switch (c.code) {
        case 0: case 99: case 103: case 107: case 499: case 260: case 141: case 251:
            return true;
        case 106:
            log("debug: " + expandText(c.string(0), &f));
            return true;
        case 101:
            showMessage(expandText(c.string(0), &f), ctx);
            ctx.wait = Context::Wait::Message;
            return false;
        case 102:
            showChoices(c, ctx);
            ctx.wait = Context::Wait::Choice;
            ctx.waitArg = int(index);
            return false;
        case 104: case 105:
            msg_.open = false;
            msg_.choosing = false;
            return true;
        case 111: case 112: {
            const Flow& flow = flowOf(&list);
            int count = c.arg(0) & 0x0F;
            bool hasElse = (c.arg(0) & 0xF0) != 0;
            int chosen = 0;
            if (c.code == 111) {
                for (int k = 0; k < count; k++) {
                    int32_t left = c.arg(size_t(1 + k * 3)), right = c.arg(size_t(2 + k * 3));
                    int flags = c.arg(size_t(3 + k * 3));
                    int32_t lv = getValue(left, &f);
                    int32_t rv = (flags & 0xF0) ? right : getValue(right, &f);
                    if (compare(lv, rv, flags & 0x0F)) { chosen = k + 1; break; }
                }
            } else {
                for (int k = 0; k < count; k++) {
                    int32_t spec = c.arg(size_t(1 + k));
                    int32_t leftAddr = spec & 0x00FFFFFF;
                    int op = (spec >> 24) & 0xF0;
                    bool rightIsVar = ((spec >> 24) & 0x0F) == 1;
                    // Left: a string variable (the address is relative to 3000000 if small).
                    std::string left = getString(leftAddr < 1000000 ? leftAddr + 3000000 : leftAddr, &f);
                    std::string right;
                    if (rightIsVar) {
                        int32_t ra = c.arg(size_t(1 + count + k));
                        right = getString(ra, &f);
                    } else {
                        right = expandText(c.string(size_t(k)), &f);
                    }
                    bool ok = false;
                    if (op == 0x00) ok = left == right;
                    else if (op == 0x10) ok = left != right;
                    else if (op == 0x20) ok = left.find(right) != std::string::npos;
                    else if (op == 0x30) ok = left.rfind(right, 0) == 0;
                    if (ok) { chosen = k + 1; break; }
                }
            }
            int target = -1;
            for (int m = flow.next[index]; m >= 0; m = flow.next[size_t(m)]) {
                const Command& mc = list[size_t(m)];
                if (mc.code == 499) { target = m; break; }
                if (chosen > 0 && mc.code == 401 && mc.arg(0) == chosen) { target = m; break; }
                if (chosen == 0 && hasElse && mc.code == 420) { target = m; break; }
            }
            if (target < 0) target = flow.end[index];
            f.pc = target >= 0 ? size_t(target) + 1 : list.size();
            return true;
        }
        case 401: case 402: case 420: case 421:
            // The end of a case body: leave the branch.
            skipToBranchEnd(f, index);
            return true;
        case 121: execSetVariable(c, f); return true;
        case 122: execSetString(ctx, c, f); return ctx.wait == Context::Wait::None;
        case 124: execSetVariablePlus(c, f); return true;
        case 250: execDatabase(c, f); return true;
        case 123:
            if (!execKeyInput(ctx, c, f, true)) {
                ctx.wait = Context::Wait::KeyInput;
                ctx.waitCmd = &c;
                return false;
            }
            return true;
        case 125: {
            // Automatic key input: pressed for the next frame.
            int b0 = c.arg(0) & 0xFF;
            int type = (c.arg(0) >> 24) & 0xFF;
            if (type == 0) {
                if (b0 & 0x01) input_.down[KeyOK] = true;
                if (b0 & 0x02) input_.down[KeyCancel] = true;
                if (b0 & 0x04) input_.down[KeySub] = true;
                if (b0 & 0x10) input_.down[KeyDown] = true;
                if (b0 & 0x20) input_.down[KeyLeft] = true;
                if (b0 & 0x40) input_.down[KeyRight] = true;
                if (b0 & 0x80) input_.down[KeyUp] = true;
            }
            return true;
        }
        case 126: {
            int v = c.arg(0);
            int target = (v >> 24) & 0xFF;
            if (target == 0) {
                int keys = v & 0xFF;
                bool deny = ((v >> 8) & 0xFF) != 0;
                // Bits: 0x01 OK, 0x02 Cancel, 0x04 Sub, 0x10 down, 0x20 left, 0x40 right, 0x80 up.
                int map[8] = {KeyOK, KeyCancel, KeySub, -1, KeyDown, KeyLeft, KeyRight, KeyUp};
                for (int b = 0; b < 8; b++)
                    if ((keys >> b) & 1 && map[b] >= 0) inputBanned_[map[b]] = deny;
            }
            return true;
        }
        case 130: execTransfer(c, f); return true;
        case 140: execSound(c, f); return true;
        case 150: execPicture(c, f); return true;
        case 151: {
            int v = c.arg(0);
            int frames = getValue(c.arg(1), &f);
            int r = v & 0xFF, g = (v >> 8) & 0xFF, b = (v >> 16) & 0xFF;
            if (c.args.size() > 4) {
                r = getValue(c.arg(2), &f);
                g = getValue(c.arg(3), &f);
                b = getValue(c.arg(4), &f);
            }
            bool flash = ((v >> 24) & 0xFF) == 1;
            if (flash) {
                fx_.flash = Color{uint8_t(std::clamp(r * 255 / 100, 0, 255)), uint8_t(std::clamp(g * 255 / 100, 0, 255)),
                                  uint8_t(std::clamp(b * 255 / 100, 0, 255)), 255};
                fx_.flashTotal = fx_.flashFrames = std::max(frames, 1);
            } else {
                fx_.fromR = fx_.r; fx_.fromG = fx_.g; fx_.fromB = fx_.b;
                fx_.toR = r; fx_.toG = g; fx_.toB = b;
                fx_.colorTotal = fx_.colorFrames = std::max(frames, 0);
                if (frames <= 0) { fx_.r = r; fx_.g = g; fx_.b = b; }
            }
            return true;
        }
        case 160: {
            // Transition settings: type (-1 fade) and time; with the wait flag the screen is shown now.
            fx_.transType = getValue(c.arg(0), &f);
            int t = c.arg(1);
            fx_.transTotal = std::max(t & 0xFFFF, 0);
            return true;
        }
        case 161:
            fx_.prepared = true;
            fx_.frozen.reset();  // captured when drawing the next frame
            return true;
        case 162:
            if (fx_.prepared) {
                fx_.prepared = false;
                fx_.transFrames = std::max(fx_.transTotal, 1);
                ctx.wait = Context::Wait::Transition;
                return false;
            }
            return true;
        case 170:
            f.loops.push_back({index, 0, true});
            return true;
        case 179: {
            int n = getValue(c.arg(0), &f);
            if (n <= 0) {
                const Flow& flow = flowOf(&list);
                int e = flow.end[index];
                f.pc = e >= 0 ? size_t(e) + 1 : list.size();
                return true;
            }
            f.loops.push_back({index, n, false});
            return true;
        }
        case 498: {
            const Flow& flow = flowOf(&list);
            int s = flow.start[index];
            if (s < 0) return true;
            // The innermost loop record for this start.
            while (!f.loops.empty() && f.loops.back().start != size_t(s)) f.loops.pop_back();
            if (f.loops.empty()) { f.pc = size_t(s) + 1; f.loops.push_back({size_t(s), 0, true}); return false; }
            auto& loop = f.loops.back();
            if (!loop.infinite && --loop.remaining <= 0) {
                f.loops.pop_back();
                return true;
            }
            f.pc = size_t(s) + 1;
            return true;
        }
        case 171: case 176: {
            if (f.loops.empty()) {
                // Outside a loop: break leaves nothing; treat like the end of the event.
                if (c.code == 171) f.pc = list.size();
                return true;
            }
            const Flow& flow = flowOf(&list);
            size_t s = f.loops.back().start;
            if (c.code == 171) {
                int e = flow.end[s];
                f.loops.pop_back();
                f.pc = e >= 0 ? size_t(e) + 1 : list.size();
            } else {
                // Continue: back to the loop start, counting the iteration.
                auto& loop = f.loops.back();
                if (!loop.infinite && --loop.remaining <= 0) {
                    int e = flow.end[s];
                    f.loops.pop_back();
                    f.pc = e >= 0 ? size_t(e) + 1 : list.size();
                } else {
                    f.pc = s + 1;
                }
            }
            return true;
        }
        case 172: {
            // Stop processing: leaves this event (a common returns to its caller).
            f.pc = list.size();
            f.loops.clear();
            return true;
        }
        case 173: {
            int target = c.arg(0);
            if (target == -2) target = f.eventId;
            else if (isAddress(target)) target = getValue(target, &f);
            if (Character* ch = eventChar(target)) {
                ch->erased = true;
                if (target == f.eventId && ctx.mapEventId == target) {
                    // The erased event stops.
                }
            }
            return true;
        }
        case 174:
            returnToTitle();
            return false;
        case 175:
            quit_ = true;
            if (host_.quit) host_.quit();
            return false;
        case 177: pictureOnly_ = true; return true;
        case 178: pictureOnly_ = false; return true;
        case 180: {
            int n = getValue(c.arg(0), &f);
            if (n > 0) {
                ctx.waitFrames = n - 1;
                return false;
            }
            return true;
        }
        case 201:
            execMoveRoute(ctx, c, f);
            return ctx.wait == Context::Wait::None;
        case 202:
            ctx.wait = Context::Wait::MoveRoute;
            ctx.waitArg = -1000;
            return false;
        case 210: case 211: case 300: {
            int32_t id = c.arg(0);
            int flags = c.arg(1);
            int nNum = flags & 0x0F, nStr = (flags >> 4) & 0x0F;
            int strLiteral = (flags >> 8) & 0xFF;
            bool returns = ((flags >> 24) & 0xFF) == 1;
            std::string name = c.code == 300 ? c.string(0) : std::string();
            int commonId = -1;
            bool mapEvent = false;
            if (c.code == 300) {
                commonId = resolveCommonId(0, name, f);
            } else {
                int32_t v = id;
                if (isAddress(v) && !(v >= 500000 && v < 700000)) v = getValue(v, &f);
                if (v >= 500000) commonId = resolveCommonId(v, "", f);
                else mapEvent = true;
                id = v;
            }
            if (mapEvent) {
                int ev = id == -1 ? f.eventId : id;
                int page = c.code == 211 ? -1 : c.arg(1);
                if (c.code == 211) return true;
                callMapEventPage(ctx, ev, page);
                return true;
            }
            if (commonId < 0) return true;
            std::vector<int32_t> nums;
            std::vector<std::string> strs;
            size_t a = 2;
            for (int k = 0; k < nNum; k++) nums.push_back(getValue(c.arg(a++), &f));
            for (int k = 0; k < nStr; k++) {
                int32_t addr = c.arg(a++);
                if ((strLiteral >> k) & 1) strs.push_back(expandText(c.string(size_t(1 + k)), &f));
                else strs.push_back(getString(addr, &f));
            }
            int32_t returnTo = returns ? c.arg(a) : 0;
            if (c.code == 211) {
                reservedCommons_.push_back(commonId);
                return true;
            }
            callCommon(ctx, commonId, &c, returnTo, nums, strs, nStr > 0);
            return true;
        }
        case 212:
            return true;
        case 213: {
            std::string label = expandText(c.string(0), &f);
            for (size_t k = 0; k < list.size(); k++) {
                if (list[k].code == 212 && list[k].string(0) == label) {
                    f.pc = k + 1;
                    // Loops the jump leaves are no longer active.
                    f.loops.clear();
                    return true;
                }
            }
            return true;
        }
        case 220: {
            int slot = getValue(c.arg(1), &f);
            if (c.arg(0) == 0) {
                sys_[24] = save(slot) ? 1 : 0;
            } else {
                loadRequest_ = slot;
                return false;
            }
            return true;
        }
        case 221: case 222: {
            // Read (221) or write (222) one variable of a save file without loading it.
            int32_t target = c.arg(0);
            int slot = getValue(c.arg(1), &f);
            int32_t var = c.arg(2);
            if (c.arg(3) & 1) var = getValue(var, &f);
            std::vector<uint8_t> data;
            if (FILE* fp = std::fopen(savePath(slot).c_str(), "rb")) {
                std::fseek(fp, 0, SEEK_END);
                long n = std::ftell(fp);
                std::fseek(fp, 0, SEEK_SET);
                data.resize(size_t(std::max(n, 0L)));
                size_t got = std::fread(data.data(), 1, data.size(), fp);
                std::fclose(fp);
                data.resize(got);
            }
            if (data.empty()) {
                if (c.code == 221) {
                    if (isStringAddress(target)) setString(target, "", &f);
                    else setValue(target, 0, &f);
                    sys_[24] = 0;
                }
                return true;
            }
            // Swap the save in, read or write, and swap back.
            std::vector<uint8_t> current = serialize();
            if (!deserialize(data)) {
                deserialize(current);
                return true;
            }
            if (c.code == 221) {
                bool str = isStringAddress(var);
                std::string sv = str ? getString(var, &f) : std::string();
                int32_t nv = str ? 0 : getValue(var, &f);
                deserialize(current);
                if (str) setString(target, sv, &f);
                else setValue(target, nv, &f);
                sys_[24] = 1;
            } else {
                bool str = isStringAddress(target);
                deserialize(current);
                std::string sv = str ? getString(target, &f) : std::string();
                int32_t nv = str ? 0 : getValue(target, &f);
                deserialize(data);
                if (str) setString(var, sv, nullptr);
                else setValue(var, nv, nullptr);
                std::vector<uint8_t> updated = serialize();
                deserialize(current);
                if (FILE* fp = std::fopen(savePath(slot).c_str(), "wb")) {
                    std::fwrite(updated.data(), 1, updated.size(), fp);
                    std::fclose(fp);
                }
            }
            return true;
        }
        case 230: moveDuringEvents_ = true; return true;
        case 231: moveDuringEvents_ = false; return true;
        case 240: {
            int chip = getValue(c.arg(0), &f);
            int setting = c.arg(1);
            if (tileset_ && chip >= 0) {
                if (passageOverride_.empty()) passageOverride_ = tileset_->passage;
                size_t idx = size_t(chip);
                if (idx < passageOverride_.size()) passageOverride_[idx] = setting;
            }
            return true;
        }
        case 241: {
            int ts = getValue(c.arg(0), &f);
            if (ts >= 0 && size_t(ts) < project_->tilesets.size()) {
                map_.tileset = ts;
                loadMap(-2);  // reload graphics only
            }
            return true;
        }
        case 242: {
            int layer = getValue(c.arg(0), &f), x = getValue(c.arg(1), &f), y = getValue(c.arg(2), &f);
            int w = getValue(c.arg(3), &f), h = getValue(c.arg(4), &f), chip = getValue(c.arg(5), &f);
            for (int yy = 0; yy < std::max(h, 1); yy++)
                for (int xx = 0; xx < std::max(w, 1); xx++) map_.setTile(layer, x + xx, y + yy, chip);
            return true;
        }
        case 270: execParty(c, f); return true;
        case 280: {
            int v = c.arg(0);
            fx_.shakeSpeed = (v >> 4) & 0x0F;
            fx_.shakePower = v & 0x0F;
            fx_.shakeType = (v >> 8) & 0xFF;
            fx_.shakeFrames = getValue(c.arg(1), &f);
            if (fx_.shakeType == 2) { fx_.shakeFrames = 0; fx_.shakeOffset = 0; }
            return true;
        }
        case 281: {
            int v = c.arg(0);
            int type = v & 0x0F;
            int speedCode = (v >> 4) & 0x0F;
            bool wait = ((v >> 8) & 0x01) != 0;
            bool pixel = ((v >> 8) & 0x02) != 0;
            static const double speeds[] = {0.25, 0.5, 1, 2, 4, 8, 16, 32, 0, 64, 128};
            double sp = speedCode < 11 ? speeds[speedCode] : 4;
            if (type == 2) fx_.scrollLocked = true;
            else if (type == 3) fx_.scrollLocked = false;
            else {
                int x = getValue(c.arg(1), &f), y = getValue(c.arg(2), &f);
                if (type == 1) { x = 0; y = 0; fx_.scrollBack = true; }
                double tx = type == 1 ? 0 : fx_.scrollX + (pixel ? x : x * tileSize_);
                double ty = type == 1 ? 0 : fx_.scrollY + (pixel ? y : y * tileSize_);
                fx_.scrollTargetX = tx;
                fx_.scrollTargetY = ty;
                fx_.scrollSpeed = sp;
                fx_.scrolling = true;
                if (speedCode == 8) { fx_.scrollX = tx; fx_.scrollY = ty; fx_.scrolling = false; }
                if (wait && fx_.scrolling) {
                    // Approximate: wait the frames the scroll takes.
                    double dist = std::max(std::abs(tx - fx_.scrollX), std::abs(ty - fx_.scrollY));
                    ctx.waitFrames = int(dist / std::max(sp, 0.25));
                    return false;
                }
            }
            return true;
        }
        case 290: execEffect(c, f); return true;
        case 1000:
            return true;
        default:
            return true;
    }
}

// ---------------------------------------------------------------------------------------------

void Game::execSetVariable(const Command& c, Frame& f) {
    int32_t left = c.arg(0), r1 = c.arg(1), r2 = c.arg(2);
    int flags = c.arg(3);
    int b0 = flags & 0xFF, b1 = (flags >> 8) & 0xFF, b2 = (flags >> 16) & 0xFF;
    int calcOp = b1 & 0xF0, assignOp = b1 & 0x0F;
    bool real = (b0 & 0x02) != 0;
    int seq = (b2 & 0x01) ? std::max(c.arg(4), 0) : 0;
    bool cdb = left == 1100000000 && c.args.size() >= 7;
    if (cdb) left = 1100000000 + (getValue(c.arg(4), &f) % 100) * 1000000 + (getValue(c.arg(5), &f) % 10000) * 100 +
                     getValue(c.arg(6), &f) % 100, seq = 0;
    if (b0 & 0x10) left = getValue(left, &f);
    if (b0 & 0x20) r1 = getValue(r1, &f);
    if (b0 & 0x40) r2 = getValue(r2, &f);
    double v1 = (b0 & 0x04) ? r1 : getValue(r1, &f);
    double v2 = (b0 & 0x08) ? r2 : getValue(r2, &f);
    double result;
    switch (calcOp) {
        case 0x00: result = v1 + v2; break;
        case 0x10: result = v1 - v2; break;
        case 0x20: result = v1 * v2; break;
        case 0x30: result = v2 == 0 ? 0 : (real ? v1 / v2 : double(int64_t(v1) / int64_t(v2))); break;
        case 0x40: result = v2 == 0 ? 0 : double(int64_t(v1) % int64_t(v2)); break;
        case 0x50: result = double(int64_t(v1) & int64_t(v2)); break;
        case 0x60: {
            int64_t lo = int64_t(std::min(v1, v2)), hi = int64_t(std::max(v1, v2));
            result = double(lo + int64_t(rng_() % uint64_t(hi - lo + 1)));
            break;
        }
        case 0x70: result = double(int64_t(v1) | int64_t(v2)); break;
        case 0x80: result = double(int64_t(v1) ^ int64_t(v2)); break;
        case 0x90: result = double(int64_t(v1) << std::clamp<int64_t>(int64_t(v2), 0, 31)); break;
        case 0xA0: result = double(int64_t(v1) >> std::clamp<int64_t>(int64_t(v2), 0, 31)); break;
        case 0xF0: result = std::round(std::atan2(v1, v2) * 1800.0 / M_PI); break;
        default: result = v1 + v2; break;
    }
    if (calcOp == 0x00 && (b0 & 0x08) == 0 && r2 == 0 && !isAddress(r2)) result = v1;
    for (int k = 0; k <= seq; k++) {
        int32_t addr = left + k;
        if (isStringAddress(addr) && assignOp == 0) {
            setString(addr, std::to_string(clamp32(result)), &f);
            continue;
        }
        double cur = getValue(addr, &f);
        double out;
        switch (assignOp) {
            case 0x00: out = result; break;
            case 0x01: out = cur + result; break;
            case 0x02: out = cur - result; break;
            case 0x03: out = cur * result; break;
            case 0x04: out = result == 0 ? cur : (real ? cur / result : double(int64_t(cur) / int64_t(result))); break;
            case 0x05: out = result == 0 ? cur : double(int64_t(cur) % int64_t(result)); break;
            case 0x06: out = std::max(cur, result); break;   // lower bound
            case 0x07: out = std::min(cur, result); break;   // upper bound
            case 0x08: out = std::abs(result); break;
            case 0x09: out = std::round(std::atan(result / 1000.0) * 1800.0 / M_PI); break;
            case 0x0A: out = std::round(std::sin(result * M_PI / 1800.0) * 1000.0); break;
            case 0x0B: out = std::round(std::cos(result * M_PI / 1800.0) * 1000.0); break;
            case 0x0C: out = result < 0 ? 0 : std::floor(std::sqrt(result) * 1000.0); break;
            default: out = result; break;
        }
        setValue(addr, clamp32(std::trunc(out)), &f);
    }
}

void Game::execSetString(Context& ctx, const Command& c, Frame& f) {
    int32_t left = c.arg(0);
    int flags = c.arg(1);
    int b0 = flags & 0xFF, b1 = (flags >> 8) & 0xFF;
    int source = b0 & 0x0F;
    bool leftIndirect = (b0 & 0xF0) != 0;
    int op = b1 & 0x0F;
    int special = b1 & 0xF0;
    if (leftIndirect) left = getValue(left, &f);
    if (left < 1000000) left += 3000000;
    std::string right;
    switch (source) {
        case 0: right = expandText(c.string(0), &f); break;
        case 1: right = getString(c.arg(2), &f); break;
        case 2: {
            int32_t addr = getValue(c.arg(2), &f);
            if (addr < 1000000) addr += 3000000;
            right = getString(addr, &f);
            break;
        }
        case 3: {
            // Keyboard input.
            int maxChars = getValue(c.arg(2), &f);
            std::string text;
            if (host_.textInput) text = host_.textInput(getString(left, &f), maxChars);
            if (special & 0x20 || true) right = text;
            sys_[39] = 0;
            break;
        }
    }
    std::string cur = getString(left, &f);
    switch (op) {
        case 0x00: setString(left, right, &f); break;
        case 0x01: setString(left, cur + right, &f); break;
        case 0x02: {  // copy the first line of the right side
            size_t nl = right.find('\n');
            setString(left, nl == std::string::npos ? right : right.substr(0, nl), &f);
            break;
        }
        case 0x03: {  // cut the first line out of the right side (a string variable)
            size_t nl = right.find('\n');
            std::string first = nl == std::string::npos ? right : right.substr(0, nl);
            std::string rest = nl == std::string::npos ? std::string() : right.substr(nl + 1);
            setString(left, first, &f);
            if (source == 1) setString(c.arg(2), rest, &f);
            break;
        }
        case 0x04: {  // cut the first character
            size_t n = 1;
            if (!right.empty()) {
                unsigned char ch = static_cast<unsigned char>(right[0]);
                n = ch < 0x80 ? 1 : ch < 0xE0 ? 2 : ch < 0xF0 ? 3 : 4;
            }
            setString(left, right.substr(0, std::min(n, right.size())), &f);
            if (source == 1) setString(c.arg(2), right.size() > n ? right.substr(n) : std::string(), &f);
            break;
        }
        case 0x05: {  // load a text file
            auto data = project_->vfs.read(right);
            if (!data) data = project_->vfs.read("Data/" + right);
            std::string text = data ? std::string(data->begin(), data->end()) : std::string();
            if (data && !project_->game.utf8) {
                bool ascii = true;
                for (unsigned char ch : text) if (ch >= 0x80) { ascii = false; break; }
                if (!ascii) text = sjisToUtf8(data->data(), data->size());
            }
            // Strip a UTF-8 BOM and CRs.
            if (text.rfind("\xEF\xBB\xBF", 0) == 0) text.erase(0, 3);
            text.erase(std::remove(text.begin(), text.end(), '\r'), text.end());
            setString(left, text, &f);
            break;
        }
        case 0x06: break;  // export to file: games may not write into their folder here
        case 0x07: {
            // File list of a folder.
            std::string list;
            for (const auto& p : project_->vfs.list(right)) {
                size_t slash = p.find_last_of('/');
                list += (slash == std::string::npos ? p : p.substr(slash + 1)) + "\n";
            }
            setString(left, list, &f);
            break;
        }
        case 0x08: {  // remove every occurrence
            std::string s = cur;
            if (!right.empty())
                for (size_t p; (p = s.find(right)) != std::string::npos;) s.erase(p, right.size());
            setString(left, s, &f);
            break;
        }
        case 0x09: {  // replace
            std::string with = expandText(c.string(1), &f);
            std::string s = cur;
            if (!right.empty()) {
                size_t p = 0;
                while ((p = s.find(right, p)) != std::string::npos) {
                    s.replace(p, right.size(), with);
                    p += with.size();
                }
            }
            setString(left, s, &f);
            break;
        }
        case 0x0A: {  // cut up to (and including) the first occurrence
            size_t p = cur.find(right);
            if (p == std::string::npos) setString(left, "", &f);
            else setString(left, cur.substr(p + right.size()), &f);
            break;
        }
        case 0x0B: {  // keep what follows the first occurrence… or what precedes it
            size_t p = cur.find(right);
            if (p != std::string::npos) setString(left, cur.substr(0, p), &f);
            break;
        }
        default: setString(left, right, &f); break;
    }
    (void)ctx;
}

void Game::execSetVariablePlus(const Command& c, Frame& f) {
    int32_t left = c.arg(0);
    int flags = c.arg(1);
    int b0 = flags & 0xFF, b1 = (flags >> 8) & 0xFF, b2 = (flags >> 16) & 0xFF;
    int exec = b1 & 0xF0, op = b1 & 0x0F;
    if (b0 & 0x10) left = getValue(left, &f);
    int32_t value = 0;
    if (exec == 0x10) {  // character info
        int target = c.arg(2);
        if (target == -2 || target == 1100000) target = f.eventId;
        else if (isAddress(target)) target = getValue(target, &f);
        value = charInfo(target, c.arg(3), &f);
    } else if (exec == 0x20) {  // position info
        int x = getValue(c.arg(2), &f), y = getValue(c.arg(3), &f);
        bool precise = (b0 & 0x20) != 0;
        int tx = precise ? x / 2 : x, ty = precise ? y / 2 : y;
        int info = b2;
        switch (info) {
            case 0x00: value = tileTag(tx, ty, -1); break;
            case 0x01: {
                value = -1;
                for (auto& e : events_) {
                    if (!e.exists || e.erased || e.page < 0) continue;
                    if (e.px / 2 == tx && e.py / 2 == ty) { value = e.eventId; break; }
                }
                break;
            }
            case 0x02: value = tilePassable(tx * 2, ty * 2, 0, true) ? 1 : 0; break;
            case 0x03: {
                value = tilePassable(tx * 2, ty * 2, 0, true) ? 1 : 0;
                for (auto& e : events_)
                    if (e.exists && !e.erased && e.page >= 0 && !e.through && e.px / 2 == tx && e.py / 2 == ty) value = 0;
                break;
            }
            case 0x04: {
                value = 0;
                for (int l = map_.layers - 1; l >= 0; l--)
                    if (int t = map_.tile(l, tx, ty)) { value = t; break; }
                break;
            }
            case 0x05: case 0x06: case 0x07: value = map_.tile(info - 0x05, tx, ty); break;
            case 0x08: case 0x09: case 0x0A: value = tileTag(tx, ty, info - 0x08); break;
        }
    } else if (exec == 0x30) {  // other info
        switch (c.arg(2)) {
            case 0: value = mapId_; break;
            case 1: value = audioState_.bgmId; break;
            case 2: value = audioState_.bgsId; break;
            case 3: value = audio_.positionMs(Channel::BGM); break;
            case 4: value = audio_.positionMs(Channel::BGS); break;
            case 5: value = audio_.lengthMs(Channel::BGM); break;
            case 6: value = audio_.lengthMs(Channel::BGS); break;
            case 7: value = input_.mouseLeft ? (prevInput_.mouseLeft ? 1 : 2) : (prevInput_.mouseLeft ? 3 : 0); break;
            case 8: value = input_.mouseRight ? (prevInput_.mouseRight ? 1 : 2) : (prevInput_.mouseRight ? 3 : 0); break;
            case 9: value = input_.mouseMiddle ? (prevInput_.mouseMiddle ? 1 : 2) : 0; break;
            case 10: value = input_.wheel; break;
            case 11: value = input_.mouseX - prevInput_.mouseX; break;
            case 12: value = input_.mouseY - prevInput_.mouseY; break;
            case 13: value = -1; break;
            case 14: value = f.eventId; break;
            case 15: value = map_.width; break;
            case 16: value = map_.height; break;
            case 17: value = f.commonId >= 0 ? f.commonId : -1; break;
            case 18: value = f.eventId; break;
            case 19: value = int32_t(f.pc); break;
            case 20: value = input_.mouseX; break;
            case 21: value = input_.mouseY; break;
        }
    } else if (exec == 0x40) {  // picture info
        int num = getValue(c.arg(2), &f);
        auto it = pictures_.find(num);
        Picture* p = it == pictures_.end() ? nullptr : &it->second;
        int info = c.arg(3);
        if (!p || !p->used) value = info == 9 ? 0 : 0;
        else {
            int w = 0, h = 0;
            if (p->texture) {
                w = p->type == 0 ? p->texture->width() / std::max(p->divW, 1) : p->texture->width();
                h = p->type == 0 ? p->texture->height() / std::max(p->divH, 1) : p->texture->height();
            }
            if (p->type == 2) { w = p->textW; h = p->textH; }
            switch (info) {
                case 0: value = int32_t(p->cur.x); break;
                case 1: value = int32_t(p->cur.y); break;
                case 2: value = w; break;
                case 3: value = h; break;
                case 4: value = p->pattern; break;
                case 5: value = int32_t(p->cur.opacity); break;
                case 6: value = int32_t(p->cur.angle); break;
                case 7: case 11: value = int32_t(p->cur.zoomW); break;
                case 12: value = int32_t(p->cur.zoomH); break;
                case 8: {
                    double x0 = p->cur.x, y0 = p->cur.y;
                    double sw = w * p->cur.zoomW / 100, sh = h * p->cur.zoomH / 100;
                    if (p->anchor == 1) { x0 -= sw / 2; y0 -= sh / 2; }
                    value = input_.mouseX >= x0 && input_.mouseX < x0 + sw && input_.mouseY >= y0 && input_.mouseY < y0 + sh;
                    break;
                }
                case 9: value = 1; break;
                case 10: value = p->textDone ? 1 : 0; break;
                default:
                    if (info >= 13 && info <= 20) value = int32_t(p->cur.corners[info - 13]);
                    break;
            }
        }
    }
    int32_t cur = getValue(left, &f);
    int64_t out = value;
    switch (op) {
        case 0x00: out = value; break;
        case 0x01: out = int64_t(cur) + value; break;
        case 0x02: out = int64_t(cur) - value; break;
        case 0x03: out = int64_t(cur) * value; break;
        case 0x04: out = value == 0 ? cur : cur / value; break;
        case 0x05: out = value == 0 ? cur : cur % value; break;
        case 0x06: out = std::max<int64_t>(cur, value); break;
        case 0x07: out = std::min<int64_t>(cur, value); break;
        case 0x08: out = std::llabs(int64_t(value)); break;
    }
    setValue(left, clamp64(out), &f);
}

void Game::execDatabase(const Command& c, Frame& f) {
    int flags = c.arg(3);
    int b0 = flags & 0xFF, b1 = (flags >> 8) & 0xFF, b2 = (flags >> 16) & 0xFF;
    int kind = b1 & 0x0F;   // 0 CDB, 1 SDB, 2 UDB
    bool read = (b1 & 0xF0) == 0x10;
    int db = kind == 0 ? 1 : kind == 1 ? 2 : 0;
    Database& d = db == 0 ? project_->udb : db == 1 ? project_->cdb : project_->sdb;
    auto byName = [&](const std::string& name, int which, int type, int data) -> int {
        std::string n = expandText(name, &f);
        if (which == 0) {
            for (size_t i = 0; i < d.types.size(); i++) if (d.types[i].name == n) return int(i);
        } else if (which == 1) {
            DBType* t = dbType(db, type);
            if (t) for (size_t i = 0; i < t->records.size(); i++) if (t->records[i].name == n) return int(i);
        } else {
            DBType* t = dbType(db, type);
            if (t) for (size_t i = 0; i < t->fields.size(); i++) if (t->fields[i].name == n) return int(i);
        }
        (void)data;
        return -1;
    };
    int32_t rawType = c.arg(0), rawData = c.arg(1), rawItem = c.arg(2);
    int type = (b2 & 0x01) ? byName(c.string(1), 0, 0, 0) : getValue(rawType, &f);
    int data = (b2 & 0x02) ? byName(c.string(2), 1, type, 0) : (rawData < 0 && rawData > -10 ? rawData : getValue(rawData, &f));
    int item = (b2 & 0x04) ? byName(c.string(3), 2, type, data) : (rawItem < 0 && rawItem > -10 ? rawItem : getValue(rawItem, &f));
    int32_t target = c.arg(4);
    if (read) {
        if (b0 & 0x0F) target = getValue(target, &f);
        DBType* t = dbType(db, type);
        // Special requests: names, IDs and counts.
        if (rawData == -3 && rawItem == -3) {
            if (b2 & 0x01) setValue(target, type, &f);
            else setString(target, t ? t->name : std::string(), &f);
            return;
        }
        if (rawItem == -3) {
            DBRecord* r = dbRecord(db, type, data, false);
            if (b2 & 0x02) setValue(target, data, &f);
            else setString(target, r ? r->name : std::string(), &f);
            return;
        }
        if (rawData == -3) {
            const DBField* fl = dbField(db, type, item);
            if (b2 & 0x04) setValue(target, item, &f);
            else setString(target, fl ? fl->name : std::string(), &f);
            return;
        }
        if (rawData == -1) { setValue(target, t ? int32_t(t->records.size()) : 0, &f); return; }
        if (rawItem == -1) { setValue(target, t ? int32_t(t->fields.size()) : 0, &f); return; }
        const DBField* fl = dbField(db, type, item);
        if (fl && fl->isString) {
            if (isStringAddress(target)) setString(target, dbString(db, type, data, item), &f);
            else setValue(target, dbInt(db, type, data, item), &f);
        } else {
            int32_t v = dbInt(db, type, data, item);
            int op = b0 & 0xF0;
            int32_t cur = getValue(target, &f);
            int64_t out = v;
            switch (op) {
                case 0x10: out = int64_t(cur) + v; break;
                case 0x20: out = int64_t(cur) - v; break;
                case 0x30: out = int64_t(cur) * v; break;
                case 0x40: out = v == 0 ? cur : cur / v; break;
                case 0x50: out = v == 0 ? cur : cur % v; break;
                case 0x60: out = std::max(cur, v); break;
                case 0x70: out = std::min(cur, v); break;
            }
            if (isStringAddress(target)) setString(target, std::to_string(v), &f);
            else setValue(target, clamp64(out), &f);
        }
        return;
    }
    // Write into the database.
    if (rawData == -2 && rawItem == 0) {  // clear a whole data record… of the type: all records
        DBType* t = dbType(db, type);
        if (t) for (auto& r : t->records) { for (auto& v : r.ints) v = 0; for (auto& s : r.strings) s.clear(); }
        return;
    }
    if (rawItem == -2) {  // clear one record
        DBRecord* r = dbRecord(db, type, data, false);
        if (r) {
            DBType* t = dbType(db, type);
            for (size_t i = 0; t && i < t->fields.size(); i++) {
                const DBField& fl = t->fields[i];
                if (fl.isString) { if (size_t(fl.index) < r->strings.size()) r->strings[size_t(fl.index)].clear(); }
                else if (size_t(fl.index) < r->ints.size()) r->ints[size_t(fl.index)] = fl.defaultValue;
            }
        }
        return;
    }
    int op = b0 & 0xF0, src = b0 & 0x0F;
    if (src == 2) {
        // String into the database: assign (0x00) or append (0x10).
        std::string s = expandText(c.string(0), &f);
        if (op == 0x10) s = dbString(db, type, data, item) + s;
        dbSetString(db, type, data, item, s);
        return;
    }
    int32_t rv = target;
    if (src == 1) rv = getValue(getValue(rv, &f), &f);
    else rv = getValue(rv, &f);
    const DBField* fl = dbField(db, type, item);
    if (fl && fl->isString && isStringAddress(target)) {
        std::string s = getString(target, &f);
        if (op == 0x10) s = dbString(db, type, data, item) + s;
        dbSetString(db, type, data, item, s);
        return;
    }
    int32_t cur = dbInt(db, type, data, item);
    int64_t out = rv;
    switch (op) {
        case 0x10: out = int64_t(cur) + rv; break;
        case 0x20: out = int64_t(cur) - rv; break;
        case 0x30: out = int64_t(cur) * rv; break;
        case 0x40: out = rv == 0 ? cur : cur / rv; break;
        case 0x50: out = rv == 0 ? cur : cur % rv; break;
        case 0x60: out = std::max(cur, rv); break;
        case 0x70: out = std::min(cur, rv); break;
    }
    dbSetInt(db, type, data, item, clamp64(out));
}

// Key input (123). Returns false while it waits for a key.
bool Game::execKeyInput(Context& ctx, const Command& c, Frame& f, bool first) {
    (void)ctx;
    (void)first;
    int32_t target = c.arg(0);
    int flags = c.arg(1);
    int b0 = flags & 0xFF, b1 = (flags >> 8) & 0xFF;
    bool wait = (b0 & 0x80) != 0;
    int deviceType = b1 & 0x0F;  // 0 basic keys, 1 keyboard, 2 pad, 3 mouse
    int32_t result = 0;
    if (deviceType == 0) {
        int dirType = b0 & 0x0F;
        bool ok = (b0 & 0x10) != 0, cancel = (b0 & 0x20) != 0, sub = (b0 & 0x40) != 0;
        // Pressed now (when waiting: newly pressed or repeating).
        auto held = [&](int k) { return wait ? repeated(k) : input_.down[k]; };
        // OK, cancel and sub report 10, 11 and 12.
        if (ok && held(KeyOK)) result = 10;
        else if (cancel && held(KeyCancel)) result = 11;
        else if (sub && held(KeySub)) result = 12;
        if (result == 0 && dirType != 0) {
            bool u = held(KeyUp), d = held(KeyDown), l = held(KeyLeft), r = held(KeyRight);
            int dir = 0;
            if (dirType == 2) {  // eight directions
                if (d && l) dir = 1; else if (d && r) dir = 3; else if (u && l) dir = 7; else if (u && r) dir = 9;
            }
            if (!dir) {
                if (d) dir = 2; else if (l) dir = 4; else if (r) dir = 6; else if (u) dir = 8;
            }
            switch (dirType) {
                case 1: case 2: result = dir; break;
                case 3: result = u ? 8 : 0; break;
                case 4: result = d ? 2 : 0; break;
                case 5: result = l ? 4 : 0; break;
                case 6: result = r ? 6 : 0; break;
                case 7: result = u ? 8 : d ? 2 : 0; break;
                case 8: result = l ? 4 : r ? 6 : 0; break;
            }
        }
    } else if (deviceType == 1 || deviceType == 2) {
        // Keyboard codes: 100 + the DirectInput scan code (W = 117, A = 130, …).
        bool specific = (b1 & 0x10) != 0;
        int code = getValue(c.arg(2), &f);
        if (specific) {
            result = code >= 0 && code < 512 && input_.keyboard[code] ? 1 : 0;
            if (wait && result && prevInput_.keyboard[code]) result = 0;
        } else {
            for (int k = std::max(code, 0); k < 512; k++) {
                if (input_.keyboard[k] && (!wait || !prevInput_.keyboard[k])) { result = k; break; }
            }
        }
    } else if (deviceType == 3) {
        int what = b0 & 0x0F;
        if (what == 0) result = input_.mouseLeft ? 1 : input_.mouseRight ? 2 : input_.mouseMiddle ? 3 : 0;
        else if (what == 1) result = input_.mouseX;
        else if (what == 2) result = input_.mouseY;
        else result = input_.wheel;
    }
    if (target < 1000000) target += 2000000;
    setValue(target, result, &f);
    if (wait && result == 0) return false;
    return true;
}

void Game::execSound(const Command& c, Frame& f) {
    int v = c.arg(0);
    int type = v & 0xF0, exec = v & 0x0F;
    int id = (v >> 8) & 0xFFFF;
    int spec = (v >> 24) & 0xFF;
    if (id == 0xFFFF) id = -1;
    Channel ch = type == 0x00 ? Channel::BGM : type == 0x10 ? Channel::BGS : Channel::SE;
    if (exec != 0) return;  // preload / release: nothing to do
    int fade = getValue(c.arg(1), &f);
    int startMs = getValue(c.arg(3), &f);
    int volume = c.args.size() > 4 ? getValue(c.arg(4), &f) : 100;
    int pitch = c.args.size() > 5 ? getValue(c.arg(5), &f) : 100;
    int loop = c.args.size() > 6 ? getValue(c.arg(6), &f) : 0;
    if (spec == 1) {
        id = getValue(c.arg(2), &f);
        if (id < 0) id = -1;
    }
    if (spec == 2) {
        std::string file = expandText(c.string(0), &f);
        if (file.empty()) { stopSound(ch, fade); return; }
        playSound(ch, -1, file, volume, pitch, startMs, loop, ch == Channel::SE ? 0 : fade);
        return;
    }
    if (id < 0 || (ch != Channel::SE && id == 0 && spec == 0xFF)) {
        stopSound(ch, fade);
        return;
    }
    playSound(ch, id, "", volume, pitch, startMs, loop, ch == Channel::SE ? 0 : fade);
}

void Game::execTransfer(const Command& c, Frame& f) {
    int32_t target = c.arg(0);
    int x = getValue(c.arg(1), &f), y = getValue(c.arg(2), &f);
    int32_t map = c.arg(3);
    int opts = c.arg(4);
    bool precise = (opts & 0x01) != 0;
    if (target == -10001) {
        // To a position from the system DB position list.
        int idx = getValue(c.arg(1), &f);
        map = dbInt(2, 7, idx, 0);
        x = dbInt(2, 7, idx, 1);
        y = dbInt(2, 7, idx, 2);
        target = -1;
        precise = false;
    } else {
        map = getValue(map, &f);
    }
    if (target == -2) target = f.eventId;
    else if (isAddress(target)) target = getValue(target, &f);
    int px = precise ? x : x * 2, py = precise ? y : y * 2;
    if (target == -1) {
        pendingTransfer_ = true;
        pendingMap_ = (map < 0 || map == mapId_) ? mapId_ : map;
        pendingX = px;
        pendingY = py;
        pendingDir = 0;
        transferFade_ = (opts >> 4) & 0x0F;
        return;
    }
    if (Character* ch = character(target, &f)) {
        ch->px = px;
        ch->py = py;
        ch->realX = px * tileSize_ / 2.0;
        ch->realY = py * tileSize_ / 2.0;
        ch->moving = false;
    }
}

void Game::execParty(const Command& c, Frame& f) {
    int v = c.arg(0);
    int exec = v & 0x0F;
    bool byValue = ((v >> 8) & 0x01) != 0;
    int index = getValue(c.arg(1), &f);
    std::string graphic;
    if (byValue) {
        int id = getValue(c.arg(2), &f);
        graphic = sdbFile(8, id);
    } else {
        graphic = expandText(c.string(0), &f);
    }
    // Party graphics: SysS[10] hero, SysS[11..15] followers.
    std::vector<std::string> members;
    for (int i = 10; i <= 15; i++) members.push_back(sysStr_[size_t(i)]);
    while (!members.empty() && members.back().empty()) members.pop_back();
    switch (exec) {
        case 0:  // remove
            if (index >= 0 && size_t(index) < members.size()) members.erase(members.begin() + index);
            break;
        case 1:  // insert
            if (index < 0) index = 0;
            if (size_t(index) > members.size()) index = int(members.size());
            members.insert(members.begin() + index, graphic);
            break;
        case 2:  // replace
            if (index >= 0) {
                if (size_t(index) >= members.size()) members.resize(size_t(index) + 1);
                members[size_t(index)] = graphic;
            }
            break;
        case 3:  // remove by graphic
            for (size_t i = 0; i < members.size(); i++)
                if (members[i] == graphic) { members.erase(members.begin() + long(i)); break; }
            break;
        case 4: {  // special: v >> 4 & 0x0F: 0 hide followers, 1 show, 2 gather, …
            int special = (v >> 4) & 0x0F;
            if (special == 0) partyVisible_ = false;
            else if (special == 1) partyVisible_ = true;
            else if (special == 2) for (auto& m : party_) { m.px = hero_.px; m.py = hero_.py; m.realX = hero_.realX; m.realY = hero_.realY; }
            return;
        }
    }
    for (int i = 10; i <= 15; i++) sysStr_[size_t(i)] = size_t(i - 10) < members.size() ? members[size_t(i - 10)] : std::string();
    needRefresh_ = true;
}

void Game::execMoveRoute(Context& ctx, const Command& c, Frame& f) {
    int target = c.arg(0);
    if (target == -1) target = f.eventId;       // this event
    else if (target == -2) target = -1;         // the hero
    else if (target <= -3 && target >= -7) target = -2 - (-3 - target);  // party members
    else if (isAddress(target)) target = getValue(target, &f);
    Character* ch = character(target, &f);
    if (!ch || !c.route) return;
    ch->route = c.route->commands;
    ch->routeIndex = 0;
    ch->routeRepeat = (c.route->flags & 0x01) != 0;
    ch->routeSkip = (c.route->flags & 0x02) != 0;
    ch->routeFromCommand = true;
    ch->routeDone = ch->route.empty();
    ch->routeWait = 0;
    if ((c.route->flags & 0x04) && !ch->routeRepeat && !ch->routeDone) {
        ctx.wait = Context::Wait::MoveRoute;
        ctx.waitArg = target;
    }
}

}  // namespace wolf
