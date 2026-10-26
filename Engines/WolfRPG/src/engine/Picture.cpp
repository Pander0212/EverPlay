// Pictures, text with control codes, the message window, choices and screen effects.
#include <algorithm>
#include <cmath>
#include <cstring>

#include "Game.hpp"

namespace wolf {

namespace {

constexpr int32_t kSame = -1000000;

size_t utf8Len(unsigned char c) { return c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4; }

Blend blendOf(int b) {
    return b == 1 ? Blend::Add : b == 2 ? Blend::Subtract : b == 3 ? Blend::Multiply : Blend::Normal;
}

}  // namespace

TexturePtr Game::loadImage(const std::string& path) {
    if (path.empty()) return nullptr;
    std::string key = Vfs::normalize(path);
    auto it = imageCache_.find(key);
    if (it != imageCache_.end()) return it->second;
    auto data = project_->vfs.read("Data/" + path);
    if (!data) data = project_->vfs.read(path);
    if (!data) {
        // Files without an extension: try the usual ones.
        for (const char* ext : {".png", ".jpg", ".bmp"}) {
            data = project_->vfs.read("Data/" + path + ext);
            if (data) break;
        }
    }
    TexturePtr t;
    if (data) t = gfx_.loadTexture(*data);
    if (!t) log("missing image " + path);
    imageCache_[key] = t;
    if (imageCache_.size() > 600) {
        // Keep memory bounded: drop images nothing else holds.
        for (auto i = imageCache_.begin(); i != imageCache_.end();)
            i = (i->second.use_count() <= 1 && i->first != key) ? imageCache_.erase(i) : std::next(i);
    }
    return t;
}

// A window from a 3x3 window skin, stretched to w x h.
TexturePtr Game::windowTexture(const std::string& file, int w, int h) {
    TexturePtr skin = loadImage(file);
    if (!skin || w <= 0 || h <= 0) return nullptr;
    TexturePtr target = gfx_.createTarget(w, h);
    if (!target) return nullptr;
    gfx_.setTarget(target);
    gfx_.clear(Color{0, 0, 0, 0});
    int cw = skin->width() / 3, chh = skin->height() / 3;
    int xs[4] = {0, cw, w - cw, w}, ys[4] = {0, chh, h - chh, h};
    int sxs[4] = {0, cw, skin->width() - cw, skin->width()}, sys[4] = {0, chh, skin->height() - chh, skin->height()};
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++) {
            RectI src{sxs[c], sys[r], sxs[c + 1] - sxs[c], sys[r + 1] - sys[r]};
            PointF p[4] = {{float(xs[c]), float(ys[r])}, {float(xs[c + 1]), float(ys[r])},
                           {float(xs[c + 1]), float(ys[r + 1])}, {float(xs[c]), float(ys[r + 1])}};
            if (xs[c + 1] > xs[c] && ys[r + 1] > ys[r]) gfx_.drawQuad(skin, src, p, Color{}, Blend::Normal);
        }
    gfx_.setTarget(nullptr);
    return target;
}

// ---------------------------------------------------------------------------------------------
// Text with formatting codes.

TexturePtr Game::renderRichText(const std::string& text, int maxChars, int& outW, int& outH, bool picture, int baseSize,
                                const Picture* pic) {
    (void)pic;
    struct Run {
        std::string text;
        TextStyle style;
        Color color;
        bool edge;
        int x, y;
        TexturePtr icon;
        int iconW = 0, iconH = 0;
    };
    std::vector<Run> runs;
    TextStyle style;
    style.size = baseSize > 0 ? baseSize : 16;
    Color color{255, 255, 255, 255};
    bool edge = false;
    int spacing = 0, lineGap = 0;
    int x = 0, y = 0, lineH = 0;  // line height: the largest font used on the line
    int maxW = 0;
    int shown = 0;
    int align = 0;  // 0 left, 1 center, 2 right
    std::vector<size_t> lineStarts{0};
    std::vector<int> lineWidths;
    std::string cur;
    int curX = 0;
    auto flush = [&]() {
        if (cur.empty()) return;
        Run r{cur, style, color, edge, curX, y, nullptr};
        runs.push_back(r);
        cur.clear();
    };
    auto newline = [&]() {
        flush();
        lineWidths.push_back(x);
        maxW = std::max(maxW, x);
        y += (lineH > 0 ? lineH : gfx_.lineHeight(style)) + lineGap;
        x = 0;
        curX = 0;
        lineH = 0;
        lineStarts.push_back(runs.size());
    };
    size_t i = 0;
    bool stop = false;
    while (i < text.size() && !stop) {
        if (i == 0 || text[i - 1] == '\n') {
            if (text.compare(i, 3, "<C>") == 0) { align = 1; i += 3; continue; }
            if (text.compare(i, 3, "<R>") == 0) { align = 2; i += 3; continue; }
            if (text.compare(i, 3, "<L>") == 0) { align = 0; i += 3; continue; }
        }
        char ch = text[i];
        if (ch == '\r') { i++; continue; }
        if (ch == '\n') { newline(); i++; continue; }
        if (ch == '\\' && i + 1 < text.size()) {
            char n = text[i + 1];
            if (n == '\\') {
                if (maxChars >= 0 && shown >= maxChars) { stop = true; break; }
                cur += '\\';
                x += gfx_.textWidth("\\", style) + spacing;
                shown++;
                i += 2;
                continue;
            }
            // Read the code name and an optional [argument].
            size_t j = i + 1;
            if (j < text.size() && !std::isalpha(static_cast<unsigned char>(text[j]))) {
                j++;  // one symbol: "\." "\^" "\>" "\<" "\!" "\-"
            } else {
                while (j < text.size() && std::isalpha(static_cast<unsigned char>(text[j]))) j++;
            }
            std::string code = text.substr(i + 1, j - i - 1);
            std::string arg;
            bool hasArg = false;
            if (j < text.size() && text[j] == '[') {
                size_t close = text.find(']', j);
                if (close != std::string::npos) {
                    arg = text.substr(j + 1, close - j - 1);
                    hasArg = true;
                    j = close + 1;
                }
            }
            int a = std::atoi(arg.c_str());
            // Some single-letter codes take a following name ("\E" then text): only the letter counts.
            auto isCode = [&](const char* name) { return code == name; };
            if (code.size() > 1 && std::isalpha(static_cast<unsigned char>(code[0])) && !hasArg) {
                // "\ESana": the code is "\E" and "Sana" is text.
                std::string first(1, code[0]);
                if (first == "E" || first == "N") {
                    code = first;
                    j = i + 2;
                }
            }
            if (code == "A" && j < text.size() && (text[j] == '+' || text[j] == '-' || text[j] == '=')) {
                code += text[j];
                j++;
            }
            if (isCode("f")) { flush(); curX = x; style.size = std::max(a, 4); }
            else if (isCode("c")) {
                flush(); curX = x;
                int r = dbInt(2, 12, a, 0), g = dbInt(2, 12, a, 1), b = dbInt(2, 12, a, 2);
                if (!dbRecord(2, 12, a, false)) r = g = b = 255;
                color = Color{uint8_t(std::clamp(r, 0, 255)), uint8_t(std::clamp(g, 0, 255)), uint8_t(std::clamp(b, 0, 255)), 255};
            } else if (isCode("E")) { flush(); curX = x; edge = true; }
            else if (isCode("N")) { flush(); curX = x; edge = false; }
            else if (isCode("A+")) { flush(); curX = x; style.antialias = true; }
            else if (isCode("A-")) { flush(); curX = x; style.antialias = false; }
            else if (isCode("A=")) { flush(); curX = x; style.antialias = true; }
            else if (isCode("font")) { flush(); curX = x; style.font = std::clamp(a, 0, 3); }
            else if (code == "-") { spacing = -a; }
            else if (isCode("space")) { lineGap = a; }
            else if (isCode("m")) { TextStyle big = style; big.size = std::max(a, 4); lineH = std::max(lineH, gfx_.lineHeight(big)); }
            else if (isCode("img") && hasArg) {
                flush();
                if (maxChars >= 0 && shown >= maxChars) { stop = true; break; }
                if (TexturePtr img = loadImage(arg)) {
                    Run r{"", style, color, false, x, y, img, img->width(), img->height()};
                    runs.push_back(r);
                    x += img->width() + spacing;
                    curX = x;
                    lineH = std::max(lineH, img->height());
                }
                shown++;
            }
            else if (isCode("ax")) { flush(); x = a; curX = x; }
            else if (isCode("ay")) { flush(); y = a; }
            else if (isCode("mx")) { flush(); x += a; curX = x; }
            else if (isCode("my")) { flush(); y += a; }
            else if (isCode("i")) {
                flush();
                if (maxChars >= 0 && shown >= maxChars) { stop = true; break; }
                TexturePtr icon;
                char name[64];
                for (const char* fmt : {"BasicData/icon%03d.png", "BasicData/icon%02d.png", "BasicData/icon%d.png",
                                        "BasicData/icon%03d.bmp", "BasicData/icon%03d.jpg"}) {
                    std::snprintf(name, sizeof name, fmt, a);
                    if (project_->vfs.exists("Data/" + std::string(name))) { icon = loadImage(name); break; }
                }
                if (icon) {
                    int h = style.size, w = icon->width() * h / std::max(icon->height(), 1);
                    Run r{"", style, color, false, x, y, icon, w, h};
                    runs.push_back(r);
                    x += w + spacing;
                    curX = x;
                    lineH = std::max(lineH, gfx_.lineHeight(style));
                }
                shown++;
            } else if (isCode("r") && hasArg) {
                // Ruby: "\r[base,reading]" shows the base text (the reading is left out).
                std::string base = arg.substr(0, arg.find(','));
                if (maxChars >= 0 && shown >= maxChars) { stop = true; break; }
                cur += base;
                x += gfx_.textWidth(base, style) + spacing;
                shown++;
            } else {
                // Timing codes (\. \| \^ \> \< \sp, \w) and unknown ones draw nothing.
            }
            i = j;
            continue;
        }
        size_t len = utf8Len(static_cast<unsigned char>(ch));
        if (maxChars >= 0 && shown >= maxChars) { stop = true; break; }
        std::string glyph = text.substr(i, len);
        if (cur.empty()) curX = x;
        if (spacing != 0) {
            flush();
            curX = x;
            cur = glyph;
            flush();
        } else {
            cur += glyph;
        }
        x += gfx_.textWidth(glyph, style) + spacing;
        if (spacing != 0) curX = x;
        lineH = std::max(lineH, gfx_.lineHeight(style));
        shown++;
        i += len;
    }
    flush();
    lineWidths.push_back(x);
    maxW = std::max(maxW, x);
    int totalH = y + (lineH > 0 ? lineH : gfx_.lineHeight(style));
    // Alignment applies per line when requested.
    if (align != 0) {
        for (size_t l = 0; l < lineWidths.size(); l++) {
            size_t from = lineStarts[l], to = l + 1 < lineStarts.size() ? lineStarts[l + 1] : runs.size();
            int shift = align == 1 ? (maxW - lineWidths[l]) / 2 : maxW - lineWidths[l];
            for (size_t k = from; k < to; k++) runs[k].x += shift;
        }
    }
    int pad = 2;
    outW = std::max(maxW + pad * 2, 1);
    outH = std::max(totalH + pad * 2, 1);
    if (runs.empty()) return nullptr;
    TexturePtr target = gfx_.createTarget(outW, outH);
    if (!target) return nullptr;
    gfx_.setTarget(target);
    gfx_.clear(Color{0, 0, 0, 0});
    bool shadow = !picture && sysVar(21) > 0;
    for (const Run& r : runs) {
        if (r.icon) {
            PointF p[4] = {{float(r.x + pad), float(r.y + pad)}, {float(r.x + pad + r.iconW), float(r.y + pad)},
                           {float(r.x + pad + r.iconW), float(r.y + pad + r.iconH)}, {float(r.x + pad), float(r.y + pad + r.iconH)}};
            gfx_.drawQuad(r.icon, RectI{0, 0, r.icon->width(), r.icon->height()}, p, Color{}, Blend::Normal);
            continue;
        }
        TexturePtr t = gfx_.renderText(r.text, r.style);
        if (!t) continue;
        float w = float(t->width()), h = float(t->height());
        auto put = [&](float ox, float oy, Color c) {
            PointF p[4] = {{r.x + pad + ox, r.y + pad + oy}, {r.x + pad + ox + w, r.y + pad + oy},
                           {r.x + pad + ox + w, r.y + pad + oy + h}, {r.x + pad + ox, r.y + pad + oy + h}};
            gfx_.drawQuad(t, RectI{0, 0, int(w), int(h)}, p, c, Blend::Normal);
        };
        if (r.edge) {
            Color dark{0, 0, 0, 255};
            for (int oy = -1; oy <= 1; oy++)
                for (int ox = -1; ox <= 1; ox++)
                    if (ox || oy) put(float(ox), float(oy), dark);
        } else if (shadow) {
            put(1, 1, Color{0, 0, 0, 200});
        }
        put(0, 0, r.color);
    }
    gfx_.setTarget(nullptr);
    return target;
}

// ---------------------------------------------------------------------------------------------
// Pictures

void Game::execPicture(const Command& c, Frame& f) {
    int v = c.arg(0);
    int b0 = v & 0xFF, b1 = (v >> 8) & 0xFF, b2 = (v >> 16) & 0xFF, b3 = (v >> 24) & 0xFF;
    int exec = b0 & 0x0F, type = (b0 >> 4) & 0x0F;
    int first = getValue(c.arg(1), &f);
    auto val = [&](size_t i, int32_t def) -> int32_t {
        if (i >= c.args.size()) return def;
        int32_t raw = c.args[i];
        if (raw == kSame) return kSame;
        return getValue(raw, &f);
    };
    if (exec == 2) {  // erase
        int time = val(2, 0), delay = val(3, 0);
        int last = c.args.size() > 5 ? val(5, 0) : 0;
        if (b3 & 0x01) last = std::max(last, first);
        else last = first;
        for (int n = first; n <= last; n++) {
            auto it = pictures_.find(n);
            if (it == pictures_.end()) continue;
            if (time <= 0 && delay <= 0) {
                pictures_.erase(it);
            } else {
                Picture& p = it->second;
                p.from = p.cur;
                p.to = p.cur;
                p.to.opacity = 0;
                p.moveTotal = p.moveFrames = std::max(time, 1);
                p.delay = delay;
                p.effect = -2;  // erase when done
            }
        }
        return;
    }
    if (exec == 3) {  // reset delays
        int last = (b3 & 0x01) ? val(3, first) : first;
        for (int n = first; n <= last; n++) {
            auto it = pictures_.find(n);
            if (it != pictures_.end()) it->second.delay = 0;
        }
        return;
    }
    int time = val(2, 0);
    int divW = val(3, 1), divH = val(4, 1), pattern = val(5, 1);
    int opacity = val(6, 255);
    int x = val(7, 0), y = val(8, 0);
    int zoom = val(9, 100), angle = val(10, 0);
    int fileVar = c.args.size() > 11 ? c.args[11] : 0;
    int colorFlag = c.args.size() > 12 ? (c.args[12] >> 24) & 0xFF : 1;
    int delay = val(13, 0);
    int seq = val(14, 0);
    int cr = 100, cg = 100, cb = 100;
    if (colorFlag == 2) {
        cr = val(15, 100);
        cg = val(16, 100);
        cb = val(17, 100);
    }
    int zoomH = val(18, zoom);
    int zoomType = b2 & 0xF0;
    bool relative = (b2 & 0x0F) == 1;
    bool multi = (b3 & 0x01) != 0;
    bool scroll = (b3 & 0x02) != 0;
    bool freePos = (b3 & 0x04) != 0;
    int anchor = (b1 >> 4) & 0x0F;
    int blend = b1 & 0x0F;
    int last = multi ? std::max(seq, first) : first;
    std::string str = c.string(0);
    for (int n = first; n <= last; n++) {
        Picture& p = pictures_[n];
        bool existed = p.used;
        if (exec == 0) {
            Picture fresh;
            fresh.used = true;
            fresh.type = type == 0 || type == 1 ? 0 : type == 2 ? 2 : 3;
            if (type == 0) fresh.file = expandText(str, &f);
            else if (type == 1) fresh.file = getString(fileVar, &f);
            else if (type == 2) fresh.text = expandText(str, &f);
            else if (type == 3) fresh.file = expandText(str, &f);
            else if (type == 4) fresh.file = getString(fileVar, &f);
            fresh.divW = std::max(divW == kSame ? 1 : divW, 1);
            fresh.divH = std::max(divH == kSame ? 1 : divH, 1);
            fresh.pattern = pattern == kSame ? 1 : pattern;
            fresh.anchor = anchor;
            fresh.blend = blend;
            fresh.scroll = scroll;
            fresh.freePos = freePos;
            Picture::State s;
            s.x = x == kSame ? 0 : x;
            s.y = y == kSame ? 0 : y;
            s.opacity = opacity == kSame ? 255 : opacity;
            s.zoomW = zoom == kSame ? 100 : zoom;
            s.zoomH = s.zoomW;
            if (zoomType == 0x30) s.zoomH = zoomH;
            else if (zoomType == 0x10) { s.zoomH = zoom; s.zoomW = 100; }
            else if (zoomType == 0x20) { s.zoomW = zoom; s.zoomH = 100; }
            s.angle = angle == kSame ? 0 : angle;
            s.r = cr; s.g = cg; s.b = cb;
            if (freePos)
                for (int k = 0; k < 8; k++) s.corners[k] = k < 2 ? (k == 0 ? s.x : s.y) : val(size_t(19 + k - 2), 0);
            if (type == 3 || type == 4) {
                // Window pictures: the "divisions" are the window size.
                fresh.windowW = divW;
                fresh.windowH = divH;
                fresh.divW = fresh.divH = 1;
                fresh.texture = windowTexture(fresh.file, divW, divH);
            } else if (type == 2) {
                int baseSize = sysVar(8) > 0 ? sysVar(8) : 16;
                int speed = sysVar(11);
                fresh.textChars = 1 << 30;
                fresh.texture = renderRichText(fresh.text, -1, fresh.textW, fresh.textH, true, baseSize, &fresh);
                fresh.textDone = true;
                if (speed > 0) {
                    fresh.textDone = false;
                    fresh.textShown = 0;
                    fresh.textProgress = 0;
                }
            } else {
                fresh.texture = loadImage(fresh.file);
            }
            if (time > 0 || delay > 0) {
                fresh.from = existed ? p.cur : s;
                if (!existed) fresh.from.opacity = 0;
                fresh.cur = fresh.from;
                fresh.to = s;
                fresh.moveTotal = fresh.moveFrames = std::max(time, 1);
                fresh.delay = delay;
            } else {
                fresh.cur = fresh.to = fresh.from = s;
            }
            p = std::move(fresh);
        } else if (exec == 1) {
            if (!p.used) {
                pictures_.erase(n);
                continue;
            }
            Picture::State s = p.moveFrames > 0 ? p.to : p.cur;
            auto apply = [&](double& field, int32_t v) {
                if (v == kSame) return;
                field = relative ? field + v : v;
            };
            apply(s.x, x);
            apply(s.y, y);
            if (opacity != kSame) s.opacity = opacity;
            if (zoom != kSame && zoomType != 0x40) {
                if (zoomType == 0x30) { s.zoomW = zoom; if (zoomH != kSame) s.zoomH = zoomH; }
                else if (zoomType == 0x10) s.zoomH = zoom;
                else if (zoomType == 0x20) s.zoomW = zoom;
                else { s.zoomW = zoom; s.zoomH = zoom; }
            }
            if (angle != kSame) s.angle = relative ? s.angle + angle : angle;
            if (colorFlag == 2) {
                if (cr != kSame) s.r = cr;
                if (cg != kSame) s.g = cg;
                if (cb != kSame) s.b = cb;
            }
            if (freePos)
                for (int k = 0; k < 8; k++) {
                    int32_t cv = k < 2 ? (k == 0 ? x : y) : val(size_t(19 + k - 2), kSame);
                    if (cv != kSame) s.corners[k] = cv;
                }
            if (pattern != kSame && pattern > 0) p.pattern = pattern;
            // Moves keep the anchor; a blend code above 3 means "unchanged".
            if (blend < 4) p.blend = blend;
            p.freePos = freePos;
            p.from = p.cur;
            p.to = s;
            if (time > 0 || delay > 0) {
                p.moveTotal = p.moveFrames = std::max(time, 1);
                p.delay = delay;
            } else {
                p.cur = s;
                p.moveFrames = 0;
            }
        }
    }
}

void Game::execEffect(const Command& c, Frame& f) {
    int v = c.arg(0);
    int target = v & 0x0F, type = v & 0xF0;
    int time = getValue(c.arg(1), &f);
    if (target == 0) {
        int first = getValue(c.arg(2), &f), last = getValue(c.arg(3), &f);
        if (last < first) last = first;
        int a1 = getValue(c.arg(4), &f), a2 = getValue(c.arg(5), &f), a3 = getValue(c.arg(6), &f);
        for (int n = first; n <= last; n++) {
            auto it = pictures_.find(n);
            if (it == pictures_.end()) continue;
            Picture& p = it->second;
            switch (type) {
                case 0x00:  // flash
                    p.flashR = a1; p.flashG = a2; p.flashB = a3;
                    p.flashTotal = p.flashFrames = std::max(time, 1);
                    break;
                case 0x10:  // color change
                    p.from = p.cur;
                    p.to = p.moveFrames > 0 ? p.to : p.cur;
                    p.to.r = a1; p.to.g = a2; p.to.b = a3;
                    p.moveTotal = p.moveFrames = std::max(time, 1);
                    break;
                case 0x20:  // draw position shift
                    p.shakeX = a1; p.shakeY = a2;
                    break;
                case 0x30:  // shake
                    p.effect = 0x30; p.effArgs[0] = a1; p.effArgs[1] = a2; p.effArgs[2] = a3;
                    p.effectTotal = p.effectFrames = time;
                    break;
                case 0x40:  // zoom
                    p.from = p.cur;
                    p.to = p.moveFrames > 0 ? p.to : p.cur;
                    p.to.zoomW = a1; p.to.zoomH = a2 > 0 ? a2 : a1;
                    p.moveTotal = p.moveFrames = std::max(time, 1);
                    break;
                case 0x50:  // flicker switch
                    p.effect = time > 0 || a1 > 0 ? 0x50 : -1; p.effArgs[0] = a1; p.effArgs[1] = a2; p.effArgs[2] = a3;
                    break;
                case 0x60:  // auto flash
                    p.effect = 0x60; p.effArgs[0] = a1; p.effArgs[1] = a2; p.effArgs[2] = a3;
                    p.effectTotal = time;
                    break;
                case 0x70:  // auto zoom
                    p.effect = 0x70; p.effArgs[0] = a1; p.effArgs[1] = a2; p.effArgs[2] = a3;
                    p.effectTotal = time;
                    break;
                case 0x80: case 0x90: case 0xA0:  // automatic pattern changes
                    p.autoPatternMode = (type - 0x70) >> 4;
                    p.autoPatternFirst = a1 > 0 ? a1 : 1;
                    p.autoPatternLast = a2 > 0 ? a2 : p.divW * p.divH;
                    p.autoPatternWait = std::max(time, 1);
                    p.autoPatternCounter = 0;
                    p.autoPatternDir = 1;
                    p.pattern = p.autoPatternFirst;
                    break;
            }
        }
    } else if (target == 1) {
        int who = c.arg(2);
        if (who == -2) who = f.eventId;
        Character* ch = character(who, &f);
        if (!ch) return;
        if (type == 0x00 || type == 0x30) {
            ch->flashColor = Color{uint8_t(std::clamp(getValue(c.arg(4), &f) * 255 / 100, 0, 255)),
                                   uint8_t(std::clamp(getValue(c.arg(5), &f) * 255 / 100, 0, 255)),
                                   uint8_t(std::clamp(getValue(c.arg(6), &f) * 255 / 100, 0, 255)), 255};
            ch->flashTotal = ch->flashFrames = std::max(time, 1);
        } else if (type == 0x10) {
            ch->shakeFrames = time;
            ch->shakePower = std::max(getValue(c.arg(4), &f), 1);
        } else if (type == 0x20) {
            ch->flickerMode = time > 0 ? 1 : 0;
        }
    } else if (target == 2) {
        fx_.zoomFrom = fx_.zoom;
        fx_.zoomTo = getValue(c.arg(6), &f);
        fx_.zoomCX = getValue(c.arg(4), &f);
        fx_.zoomCY = getValue(c.arg(5), &f);
        fx_.zoomTotal = fx_.zoomFrames = std::max(time, 0);
        if (time <= 0) fx_.zoom = fx_.zoomTo;
    }
}

void Game::updatePictures() {
    for (auto it = pictures_.begin(); it != pictures_.end();) {
        Picture& p = it->second;
        if (p.delay > 0) {
            p.delay--;
            ++it;
            continue;
        }
        if (p.moveFrames > 0) {
            p.moveFrames--;
            double t = 1.0 - double(p.moveFrames) / std::max(p.moveTotal, 1);
            auto lerp = [&](double a, double b) { return a + (b - a) * t; };
            p.cur.x = lerp(p.from.x, p.to.x);
            p.cur.y = lerp(p.from.y, p.to.y);
            p.cur.zoomW = lerp(p.from.zoomW, p.to.zoomW);
            p.cur.zoomH = lerp(p.from.zoomH, p.to.zoomH);
            p.cur.angle = lerp(p.from.angle, p.to.angle);
            p.cur.opacity = lerp(p.from.opacity, p.to.opacity);
            p.cur.r = lerp(p.from.r, p.to.r);
            p.cur.g = lerp(p.from.g, p.to.g);
            p.cur.b = lerp(p.from.b, p.to.b);
            for (int k = 0; k < 8; k++) p.cur.corners[k] = lerp(p.from.corners[k], p.to.corners[k]);
            if (p.moveFrames == 0 && p.effect == -2) {
                it = pictures_.erase(it);
                continue;
            }
        }
        if (p.flashFrames > 0) p.flashFrames--;
        if (p.effect == 0x30 && p.effectFrames > 0) {
            p.effectFrames--;
            double power = p.effArgs[0] > 0 ? p.effArgs[0] : 4;
            p.shakeX = std::sin(frameCount_ * (0.5 + p.effArgs[1] * 0.1)) * power;
            if (p.effectFrames == 0) { p.shakeX = p.shakeY = 0; p.effect = -1; }
        }
        if (p.autoPatternMode) {
            if (++p.autoPatternCounter >= p.autoPatternWait) {
                p.autoPatternCounter = 0;
                if (p.autoPatternMode == 3) {
                    if (p.pattern + p.autoPatternDir > p.autoPatternLast || p.pattern + p.autoPatternDir < p.autoPatternFirst)
                        p.autoPatternDir = -p.autoPatternDir;
                    p.pattern += p.autoPatternDir;
                } else if (p.pattern >= p.autoPatternLast) {
                    if (p.autoPatternMode == 2) p.pattern = p.autoPatternFirst;
                    else p.autoPatternMode = 0;
                } else {
                    p.pattern++;
                }
            }
        }
        if (p.type == 2 && !p.textDone) {
            int speed = std::max(sysVar(11), 1);
            p.textProgress += double(speed) / fps_;
            p.textShown = int(p.textProgress);
            int w, h;
            p.texture = renderRichText(p.text, p.textShown, w, h, true, sysVar(8) > 0 ? sysVar(8) : 16, &p);
            // Done when nothing more appears.
            int fw, fh;
            TexturePtr full = nullptr;
            (void)full;
            if (p.textShown > int(p.text.size())) {
                p.textDone = true;
                p.texture = renderRichText(p.text, -1, fw, fh, true, sysVar(8) > 0 ? sysVar(8) : 16, &p);
            }
        }
        ++it;
    }
}

void Game::drawPicture(Picture& p) {
    if (!p.used || !p.texture || p.cur.opacity <= 0) return;
    if (p.effect == 0x50 && (frameCount_ / std::max(p.effArgs[0], 1)) % 2) return;
    const TexturePtr& t = p.texture;
    RectI src{0, 0, t->width(), t->height()};
    if (p.type == 0 && (p.divW > 1 || p.divH > 1)) {
        int fw = t->width() / p.divW, fh = t->height() / p.divH;
        int idx = std::max(p.pattern - 1, 0) % (p.divW * p.divH);
        src = RectI{(idx % p.divW) * fw, (idx / p.divW) * fh, fw, fh};
    }
    double w = src.w * p.cur.zoomW / 100.0, h = src.h * p.cur.zoomH / 100.0;
    double x = p.cur.x + p.shakeX, y = p.cur.y + p.shakeY;
    if (p.scroll) { x -= camX_; y -= camY_; }
    double ox = 0, oy = 0;  // anchor offset inside the picture
    switch (p.anchor) {
        case 1: ox = w / 2; oy = h / 2; break;
        case 2: oy = h; break;
        case 3: ox = w; break;
        case 4: ox = w; oy = h; break;
    }
    PointF q[4];
    if (p.freePos) {
        for (int k = 0; k < 4; k++) q[k] = PointF{float(p.cur.corners[k * 2]), float(p.cur.corners[k * 2 + 1])};
        // Corners are top-left, top-right, bottom-left, bottom-right in the command.
        std::swap(q[2], q[3]);
    } else {
        double rad = p.cur.angle * M_PI / 180.0;
        double cs = std::cos(rad), sn = std::sin(rad);
        double corners[4][2] = {{-ox, -oy}, {w - ox, -oy}, {w - ox, h - oy}, {-ox, h - oy}};
        for (int k = 0; k < 4; k++) {
            double cx = corners[k][0], cy = corners[k][1];
            q[k] = PointF{float(x + cx * cs - cy * sn), float(y + cx * sn + cy * cs)};
        }
    }
    auto ch = [](double v) { return uint8_t(std::clamp(v * 255.0 / 100.0, 0.0, 255.0)); };
    Color mod{ch(p.cur.r), ch(p.cur.g), ch(p.cur.b), uint8_t(std::clamp(p.cur.opacity, 0.0, 255.0))};
    gfx_.drawQuad(t, src, q, mod, blendOf(p.blend));
    // Above 100%: brighten with an additive pass.
    if (p.cur.r > 100 || p.cur.g > 100 || p.cur.b > 100) {
        auto extra = [](double v) { return uint8_t(std::clamp((v - 100.0) * 255.0 / 100.0, 0.0, 255.0)); };
        Color add{extra(p.cur.r), extra(p.cur.g), extra(p.cur.b), uint8_t(std::clamp(p.cur.opacity, 0.0, 255.0))};
        gfx_.drawQuad(t, src, q, add, Blend::Add);
    }
    if (p.flashFrames > 0 && p.flashTotal > 0) {
        uint8_t a = uint8_t(255 * p.flashFrames / p.flashTotal);
        Color fc{ch(p.flashR), ch(p.flashG), ch(p.flashB), a};
        gfx_.drawQuad(t, src, q, fc, Blend::Add);
    }
}

void Game::drawPictures(bool belowMessage) {
    (void)belowMessage;
    for (auto& [n, p] : pictures_) drawPicture(p);
}

// ---------------------------------------------------------------------------------------------
// Messages and choices

void Game::showMessage(const std::string& text, Context& ctx) {
    msg_.open = true;
    msg_.text = text;
    msg_.shown = 0;
    msg_.progress = 0;
    msg_.done = false;
    msg_.waitingKey = false;
    msg_.choosing = false;
    msg_.renderedChars = -1;
    msg_.faceId = sysVar(0);
    msg_.pos = 0;
    msg_.speed = 0;
    msg_.instant = false;
    msg_.pauseFrames = 0;
    msg_.keyPause = false;
    msg_.pauseAnim = 0;
    sysStr_[25] = text;
    // "\^": continue without waiting for a key.
    msg_.autoClose = text.find("\\^") != std::string::npos;
    // A choice right after the message appears without a key press.
    const Frame& f = ctx.frames.back();
    size_t pc = f.pc;
    while (pc < f.commands->size() && ((*f.commands)[pc].code == 0 || (*f.commands)[pc].code == 103)) pc++;
    if (pc < f.commands->size() && (*f.commands)[pc].code == 102) msg_.autoClose = true;
}

void Game::showChoices(const Command& c, Context& ctx) {
    (void)ctx;
    int v = c.arg(0);
    int count = v & 0x0F;
    int cancel = v & 0xF0;
    int forks = (v >> 8) & 0xFF;
    msg_.choices.clear();
    for (int i = 0; i < count && size_t(i) < c.strings.size(); i++) msg_.choices.push_back(expandText(c.string(size_t(i)), &ctx.frames.back()));
    for (size_t i = 0; i < 10; i++) sysStr_[40 + i] = i < msg_.choices.size() ? msg_.choices[i] : std::string();
    msg_.choosing = true;
    msg_.open = msg_.open || !msg_.text.empty();
    int start = sysVar(7);
    msg_.cursor = std::clamp(start, 0, std::max(count - 1, 0));
    sys_[7] = 0;
    msg_.allowCancel = cancel != 0x10;
    msg_.cancelCase = cancel == 0x00 ? -2 : cancel >= 0x20 ? ((cancel >> 4) - 2) : -1;
    msg_.leftBranch = (forks & 0x01) != 0;
    msg_.rightBranch = (forks & 0x02) != 0;
    msg_.result = -1;
    sys_[20] = msg_.cursor;
}

void Game::updateMessage() {
    if (msg_.choosing) {
        int n = int(msg_.choices.size());
        if (n == 0) { msg_.choosing = false; msg_.result = -2; return; }
        int se = -1;
        if (systemRepeated(KeyDown)) { msg_.cursor = (msg_.cursor + 1) % n; se = sysVar(18); }
        if (systemRepeated(KeyUp)) { msg_.cursor = (msg_.cursor + n - 1) % n; se = sysVar(18); }
        sys_[20] = msg_.cursor;
        if (systemPressed(KeyOK)) {
            msg_.result = msg_.cursor;
            msg_.choosing = false;
            se = sysVar(17);
        } else if (systemPressed(KeyCancel) && msg_.allowCancel) {
            msg_.result = msg_.cancelCase == -2 ? -2 : std::clamp(msg_.cancelCase, 0, n - 1);
            msg_.choosing = false;
            se = sysVar(19);
        } else if (msg_.leftBranch && systemPressed(KeyLeft)) {
            msg_.result = -3;
            msg_.choosing = false;
        } else if (msg_.rightBranch && systemPressed(KeyRight)) {
            msg_.result = -4;
            msg_.choosing = false;
        }
        if (se > 0) playSound(Channel::SE, se, "", 100, 100, 0, 0, 0);
        if (!msg_.choosing) {
            sys_[20] = -1;
            msg_.text.clear();
        }
        return;
    }
    if (!msg_.open) return;
    if (!msg_.done) {
        if (msg_.keyPause) {
            msg_.pauseAnim++;
            if (systemPressed(KeyOK)) msg_.keyPause = false;
            return;
        }
        if (msg_.pauseFrames > 0) {
            msg_.pauseFrames--;
            if (!systemPressed(KeyOK)) return;
            msg_.pauseFrames = 0;
        }
        int speed = msg_.speed != 0 ? msg_.speed : sysVar(9);
        bool all = speed <= 0 || msg_.instant || systemPressed(KeyOK);
        msg_.progress += all ? 1e9 : double(speed) / fps_;
        const std::string& t = msg_.text;
        while (msg_.pos < t.size() && (msg_.progress >= 1 || msg_.instant)) {
            char ch = t[msg_.pos];
            if (ch == '\\' && msg_.pos + 1 < t.size()) {
                char n = t[msg_.pos + 1];
                if (n == '\\') { msg_.shown++; msg_.progress -= 1; msg_.pos += 2; continue; }
                size_t j = msg_.pos + 1;
                if (!std::isalpha(static_cast<unsigned char>(n))) j++;
                else while (j < t.size() && std::isalpha(static_cast<unsigned char>(t[j]))) j++;
                std::string code = t.substr(msg_.pos + 1, j - msg_.pos - 1);
                std::string arg;
                if (j < t.size() && t[j] == '[') {
                    size_t close = t.find(']', j);
                    if (close != std::string::npos) { arg = t.substr(j + 1, close - j - 1); j = close + 1; }
                }
                if (code.size() > 1 && (code[0] == 'E' || code[0] == 'N') && arg.empty()) {
                    j = msg_.pos + 2;
                    code = code.substr(0, 1);
                }
                msg_.pos = j;
                if (code == ".") { msg_.pauseFrames = fps_ / 4; msg_.progress = 0; if (!all) break; }
                else if (code == "!") { msg_.keyPause = true; msg_.progress = 0; break; }
                else if (code == ">") msg_.instant = true;
                else if (code == "<") msg_.instant = false;
                else if (code == "sp") msg_.speed = std::atoi(arg.c_str()) <= 0 ? -1 : std::atoi(arg.c_str());
                else if (code == "i" || code == "img" || code == "r") { msg_.shown++; msg_.progress -= 1; }
                continue;
            }
            msg_.pos += utf8Len(static_cast<unsigned char>(ch));
            if (ch == '\n' || ch == '\r') continue;
            msg_.shown++;
            msg_.progress -= 1;
        }
        if (msg_.pos >= t.size()) {
            msg_.done = true;
            msg_.shown = 1 << 30;
            msg_.waitingKey = !msg_.autoClose;
            msg_.pauseAnim = 0;
            if (!msg_.waitingKey) msg_.open = false;
        }
        return;
    }
    if (msg_.waitingKey) {
        msg_.pauseAnim++;
        if (systemPressed(KeyOK)) {
            msg_.waitingKey = false;
            msg_.open = false;
        }
    }
}

// The engine draws only the text, its pause cursor and the choice window. The message window
// itself and faces are pictures drawn by the game's own common events (the Basic System's
// "X[共]メッセージウィンドウ"), positioned with Sys1/Sys2 as the text's top-left corner.
void Game::drawMessage() {
    bool showText = msg_.open && !msg_.text.empty();
    if (!showText && !msg_.choosing) return;
    int base = sysVar(8) > 0 ? sysVar(8) : 16;
    TextStyle st;
    st.size = base;
    int lineH = gfx_.lineHeight(st);
    int defaultX = screenW_ / 16, defaultY = screenH_ - lineH * 4 - screenH_ / 24;
    if (showText) {
        int x = sysVar(1) >= 0 ? sysVar(1) : defaultX;
        int y = sysVar(2) >= 0 ? sysVar(2) : defaultY;
        if (msg_.renderedChars != msg_.shown || !msg_.rendered) {
            msg_.rendered = renderRichText(msg_.text, msg_.shown >= (1 << 29) ? -1 : msg_.shown, msg_.textW, msg_.textH, false, base);
            msg_.renderedChars = msg_.shown;
        }
        if (msg_.rendered) {
            // renderRichText pads by 2 pixels.
            float rw = float(msg_.rendered->width()), rh = float(msg_.rendered->height());
            float tx = float(x - 2), ty = float(y - 2);
            PointF p[4] = {{tx, ty}, {tx + rw, ty}, {tx + rw, ty + rh}, {tx, ty + rh}};
            gfx_.drawQuad(msg_.rendered, RectI{0, 0, int(rw), int(rh)}, p, Color{}, Blend::Normal);
        }
        if (msg_.waitingKey || msg_.keyPause) {
            std::string file = sdbFile(10, 0);
            TexturePtr pause = loadImage(file.empty() ? "SystemFile/Text_Pause.png" : file);
            if (pause) {
                int frames = std::max(dbInt(2, 10, 0, 1), 1);
                int fh = pause->height() / frames, fw = pause->width();
                int idx = (msg_.pauseAnim / 6) % frames;
                float px = float(sysVar(5) >= 0 ? sysVar(5) : x + std::max(msg_.textW, fw * 4) / 2 - fw / 2);
                float py = float(sysVar(6) >= 0 ? sysVar(6) : y + std::max(msg_.textH, lineH));
                PointF p[4] = {{px, py}, {px + fw, py}, {px + fw, py + fh}, {px, py + fh}};
                gfx_.drawQuad(pause, RectI{0, idx * fh, fw, fh}, p, Color{}, Blend::Normal);
            }
        }
    }
    if (msg_.choosing) {
        int pad = std::max(base / 2, 6);
        int maxW = 0;
        std::vector<TexturePtr> rows;
        for (const auto& c : msg_.choices) {
            int tw, th;
            rows.push_back(renderRichText(c, -1, tw, th, false, base));
            maxW = std::max(maxW, tw);
        }
        int w = maxW + pad * 4, h = int(rows.size()) * lineH + pad * 2;
        int tx = sysVar(3) >= 0 ? sysVar(3) : screenW_ - w - pad;
        int ty = sysVar(4) >= 0 ? sysVar(4) : std::max(defaultY - h - pad, 0);
        int x = tx - pad * 2, y = ty - pad;
        if (sysVar(14) != 0) {
            std::string windowFile = sdbFile(10, 1);
            if (windowFile.empty()) windowFile = "SystemFile/WindowBase.png";
            TexturePtr win = windowTexture(windowFile, w, h);
            PointF p[4] = {{float(x), float(y)}, {float(x + w), float(y)}, {float(x + w), float(y + h)}, {float(x), float(y + h)}};
            if (win) gfx_.drawQuad(win, RectI{0, 0, w, h}, p, Color{}, Blend::Normal);
        }
        std::string cursorFile = sdbFile(10, 2);
        if (cursorFile.empty()) cursorFile = "SystemFile/CursorBase.png";
        TexturePtr cur = windowTexture(cursorFile, w - pad * 2, lineH);
        int cy = ty + msg_.cursor * lineH;
        if (cur) {
            float a = float(0.6 + 0.4 * std::sin(frameCount_ * 0.1));
            PointF q[4] = {{float(x + pad), float(cy)}, {float(x + w - pad), float(cy)}, {float(x + w - pad), float(cy + lineH)},
                           {float(x + pad), float(cy + lineH)}};
            gfx_.drawQuad(cur, RectI{0, 0, cur->width(), cur->height()}, q, Color{255, 255, 255, uint8_t(255 * a)},
                          sysVar(22) == 1 ? Blend::Add : Blend::Normal);
        }
        for (size_t i = 0; i < rows.size(); i++) {
            if (!rows[i]) continue;
            float rx = float(tx - 2), ry = float(ty - 2 + int(i) * lineH);
            float rw = float(rows[i]->width()), rh = float(rows[i]->height());
            PointF q[4] = {{rx, ry}, {rx + rw, ry}, {rx + rw, ry + rh}, {rx, ry + rh}};
            gfx_.drawQuad(rows[i], RectI{0, 0, int(rw), int(rh)}, q, Color{}, Blend::Normal);
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Screen effects and the frame

void Game::updateScreenEffects() {
    if (fx_.colorFrames > 0) {
        fx_.colorFrames--;
        double t = 1.0 - double(fx_.colorFrames) / std::max(fx_.colorTotal, 1);
        fx_.r = fx_.fromR + (fx_.toR - fx_.fromR) * t;
        fx_.g = fx_.fromG + (fx_.toG - fx_.fromG) * t;
        fx_.b = fx_.fromB + (fx_.toB - fx_.fromB) * t;
    }
    if (fx_.flashFrames > 0) fx_.flashFrames--;
    if (fx_.shakeFrames > 0 || fx_.shakeType != 2) {
        if (fx_.shakeFrames > 0) {
            fx_.shakeFrames--;
            fx_.shakeTime++;
            double power = (fx_.shakePower + 1) * 2;
            double speed = (fx_.shakeSpeed + 1) * 0.15;
            fx_.shakeOffset = std::sin(fx_.shakeTime * speed) * power;
        } else {
            fx_.shakeOffset = 0;
        }
    }
    if (fx_.zoomFrames > 0) {
        fx_.zoomFrames--;
        double t = 1.0 - double(fx_.zoomFrames) / std::max(fx_.zoomTotal, 1);
        fx_.zoom = fx_.zoomFrom + (fx_.zoomTo - fx_.zoomFrom) * t;
    }
    if (fx_.transFrames > 0) {
        fx_.transFrames--;
        if (fx_.transFrames == 0) fx_.frozen.reset();
    }
}

void Game::drawScreenEffects() {
    // Flash over everything below the message window.
    if (fx_.flashFrames > 0 && fx_.flashTotal > 0) {
        Color c = fx_.flash;
        c.a = uint8_t(std::clamp(255 * fx_.flashFrames / fx_.flashTotal, 0, 255));
        gfx_.fillRect(RectI{0, 0, screenW_, screenH_}, c, Blend::Normal);
    }
}

// The color tone (151) applies to the map only; pictures keep their colors.
void Game::drawMapTone() {
    if (std::abs(fx_.r - 100) > 0.5 || std::abs(fx_.g - 100) > 0.5 || std::abs(fx_.b - 100) > 0.5) {
        // Darken with multiply below 100%, brighten with add above.
        auto mul = [](double v) { return uint8_t(std::clamp(v * 255.0 / 100.0, 0.0, 255.0)); };
        gfx_.fillRect(RectI{0, 0, screenW_, screenH_}, Color{mul(fx_.r), mul(fx_.g), mul(fx_.b), 255}, Blend::Multiply);
        auto add = [](double v) { return uint8_t(std::clamp((v - 100.0) * 255.0 / 100.0, 0.0, 255.0)); };
        if (fx_.r > 100 || fx_.g > 100 || fx_.b > 100)
            gfx_.fillRect(RectI{0, 0, screenW_, screenH_}, Color{add(fx_.r), add(fx_.g), add(fx_.b), 255}, Blend::Add);
    }
}

void Game::draw() {
    gfx_.setTarget(nullptr);
    if (fx_.prepared && fx_.frozen) {
        // The screen stays as it was until the transition runs.
        PointF p[4] = {{0, 0}, {float(screenW_), 0}, {float(screenW_), float(screenH_)}, {0, float(screenH_)}};
        gfx_.clear(Color{0, 0, 0, 255});
        gfx_.drawQuad(fx_.frozen, RectI{0, 0, fx_.frozen->width(), fx_.frozen->height()}, p, Color{}, Blend::Normal);
        return;
    }
    gfx_.clear(Color{0, 0, 0, 255});
    drawMap();
    drawMapTone();
    drawPictures(true);
    drawScreenEffects();
    drawMessage();
    if (fx_.prepared && !fx_.frozen) fx_.frozen = gfx_.copyScreen();
    if (fx_.transFrames > 0 && fx_.frozen) {
        uint8_t a = uint8_t(std::clamp(255 * fx_.transFrames / std::max(fx_.transTotal, 1), 0, 255));
        PointF p[4] = {{0, 0}, {float(screenW_), 0}, {float(screenW_), float(screenH_)}, {0, float(screenH_)}};
        gfx_.drawQuad(fx_.frozen, RectI{0, 0, fx_.frozen->width(), fx_.frozen->height()}, p, Color{255, 255, 255, a},
                      Blend::Normal);
    }
}

}  // namespace wolf
