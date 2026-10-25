#include "SdlGfx.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_HDR
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_PSD
#include "../../third_party/stb/stb_image.h"

namespace wolf {

namespace {

std::string lowerAscii(const std::string& s) {
    std::string o = s;
    for (auto& c : o) c = char(std::tolower(static_cast<unsigned char>(c)));
    return o;
}

// Font names compared without spaces, case or full-width forms of ASCII.
std::string fontKey(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == 0xEF && i + 2 < s.size()) {
            // U+FF01..U+FF5E full-width ASCII
            unsigned char c1 = static_cast<unsigned char>(s[i + 1]), c2 = static_cast<unsigned char>(s[i + 2]);
            unsigned cp = ((c & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F);
            if (cp >= 0xFF01 && cp <= 0xFF5E) {
                out += char(std::tolower(int(cp - 0xFEE0)));
                i += 3;
                continue;
            }
        }
        if (c == ' ' || c == '\t' || c == '-' || c == '_') { i++; continue; }
        if (c == 0xE3 && i + 2 < s.size() && static_cast<unsigned char>(s[i + 1]) == 0x80 &&
            static_cast<unsigned char>(s[i + 2]) == 0x80) { i += 3; continue; }  // ideographic space
        out += char(std::tolower(c));
        i++;
    }
    return out;
}

}  // namespace

SdlGfx::SdlGfx(SDL_Renderer* renderer, int screenW, int screenH, std::string fallbackFont)
    : r_(renderer), fallbackFont_(std::move(fallbackFont)) {
    if (!TTF_WasInit()) TTF_Init();
    SDL_Texture* t = SDL_CreateTexture(r_, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, screenW, screenH);
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    screen_ = std::make_shared<SdlTexture>(t, screenW, screenH);
    subtract_ = SDL_ComposeCustomBlendMode(SDL_BLENDFACTOR_SRC_ALPHA, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_REV_SUBTRACT,
                                           SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);
    multiply_ = SDL_BLENDMODE_MOD;
    slotFile_.assign(4, -1);
    if (!fallbackFont_.empty()) {
        if (FILE* f = std::fopen(fallbackFont_.c_str(), "rb")) {
            std::fseek(f, 0, SEEK_END);
            long n = std::ftell(f);
            std::fseek(f, 0, SEEK_SET);
            fallbackData_.resize(size_t(std::max(n, 0L)));
            size_t got = std::fread(fallbackData_.data(), 1, fallbackData_.size(), f);
            fallbackData_.resize(got);
            std::fclose(f);
        }
    }
}

SdlGfx::~SdlGfx() {
    textCache_.clear();
    for (auto& [k, f] : fonts_) TTF_CloseFont(f);
}

TexturePtr SdlGfx::loadTexture(const std::vector<uint8_t>& data) {
    int w, h, n;
    unsigned char* px = stbi_load_from_memory(data.data(), int(data.size()), &w, &h, &n, 4);
    if (!px) return nullptr;
    SDL_Texture* t = SDL_CreateTexture(r_, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STATIC, w, h);
    if (!t) {
        stbi_image_free(px);
        return nullptr;
    }
    SDL_UpdateTexture(t, nullptr, px, w * 4);
    stbi_image_free(px);
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    return std::make_shared<SdlTexture>(t, w, h);
}

TexturePtr SdlGfx::createTarget(int w, int h) {
    SDL_Texture* t = SDL_CreateTexture(r_, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, std::max(w, 1), std::max(h, 1));
    if (!t) return nullptr;
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    return std::make_shared<SdlTexture>(t, w, h);
}

void SdlGfx::setTarget(const TexturePtr& target) {
    current_ = target;
    SDL_Texture* t = target ? static_cast<SdlTexture*>(target.get())->tex : screen_->tex;
    SDL_SetRenderTarget(r_, t);
}

void SdlGfx::clear(Color c) {
    SDL_SetRenderDrawBlendMode(r_, SDL_BLENDMODE_NONE);
    SDL_SetRenderDrawColor(r_, c.r, c.g, c.b, c.a);
    SDL_RenderClear(r_);
}

void SdlGfx::applyBlend(SDL_Texture* t, Blend b) {
    SDL_BlendMode mode = SDL_BLENDMODE_BLEND;
    if (b == Blend::Add) mode = SDL_BLENDMODE_ADD;
    else if (b == Blend::Subtract) mode = subtract_;
    else if (b == Blend::Multiply) mode = multiply_;
    if (SDL_SetTextureBlendMode(t, mode) != 0) SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
}

void SdlGfx::drawQuad(const TexturePtr& tex, RectI src, const PointF p[4], Color mod, Blend blend) {
    if (!tex) return;
    auto* t = static_cast<SdlTexture*>(tex.get());
    float tw = float(t->width()), th = float(t->height());
    applyBlend(t->tex, blend);
    SDL_Color col{mod.r, mod.g, mod.b, mod.a};
    float u0 = src.x / tw, v0 = src.y / th, u1 = (src.x + src.w) / tw, v1 = (src.y + src.h) / th;
    SDL_Vertex v[4] = {
        {{p[0].x, p[0].y}, col, {u0, v0}},
        {{p[1].x, p[1].y}, col, {u1, v0}},
        {{p[2].x, p[2].y}, col, {u1, v1}},
        {{p[3].x, p[3].y}, col, {u0, v1}},
    };
    static const int indices[6] = {0, 1, 2, 0, 2, 3};
    // Axis-aligned unscaled quads are cheaper as plain copies (and exact on every renderer).
    bool axis = p[0].y == p[1].y && p[1].x == p[2].x && p[2].y == p[3].y && p[3].x == p[0].x && p[1].x > p[0].x &&
                p[3].y > p[0].y;
    if (axis) {
        SDL_SetTextureColorMod(t->tex, mod.r, mod.g, mod.b);
        SDL_SetTextureAlphaMod(t->tex, mod.a);
        SDL_Rect s{src.x, src.y, src.w, src.h};
        SDL_FRect d{p[0].x, p[0].y, p[1].x - p[0].x, p[3].y - p[0].y};
        SDL_RenderCopyF(r_, t->tex, &s, &d);
        SDL_SetTextureColorMod(t->tex, 255, 255, 255);
        SDL_SetTextureAlphaMod(t->tex, 255);
        return;
    }
    SDL_RenderGeometry(r_, t->tex, v, 4, indices, 6);
}

void SdlGfx::fillRect(RectI rect, Color c, Blend blend) {
    SDL_BlendMode mode = SDL_BLENDMODE_BLEND;
    if (blend == Blend::Add) mode = SDL_BLENDMODE_ADD;
    else if (blend == Blend::Multiply) mode = SDL_BLENDMODE_MOD;
    else if (blend == Blend::Subtract) mode = subtract_;
    if (SDL_SetRenderDrawBlendMode(r_, mode) != 0) SDL_SetRenderDrawBlendMode(r_, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(r_, c.r, c.g, c.b, c.a);
    SDL_Rect sr{rect.x, rect.y, rect.w, rect.h};
    SDL_RenderFillRect(r_, &sr);
}

void SdlGfx::addFont(const std::string& file, const std::vector<uint8_t>& data) {
    // Read the family name now; the data stays alive for every size opened later.
    SDL_RWops* rw = SDL_RWFromConstMem(data.data(), int(data.size()));
    TTF_Font* f = rw ? TTF_OpenFontRW(rw, 1, 16) : nullptr;
    if (!f) return;
    const char* family = TTF_FontFaceFamilyName(f);
    const char* styleName = TTF_FontFaceStyleName(f);
    std::string name = family ? family : file;
    std::string full = name + (styleName && std::strcmp(styleName, "Regular") != 0 ? std::string(" ") + styleName : "");
    TTF_CloseFont(f);
    files_.push_back({full, data});
    // The base name of the file also identifies it.
    size_t slash = file.find_last_of('/');
    std::string base = file.substr(slash == std::string::npos ? 0 : slash + 1);
    base = base.substr(0, base.find_last_of('.'));
    files_.push_back({base, {}});
    files_.back().data = data;
    files_.push_back({name, {}});
    files_.back().data = data;
}

void SdlGfx::setFonts(const std::vector<std::string>& families) {
    for (size_t slot = 0; slot < 4; slot++) {
        slotFile_[slot] = -1;
        if (slot >= families.size() || families[slot].empty()) continue;
        std::string want = fontKey(families[slot]);
        for (size_t i = 0; i < files_.size(); i++)
            if (fontKey(files_[i].family) == want) { slotFile_[slot] = int(i); break; }
        if (slotFile_[slot] < 0)
            for (size_t i = 0; i < files_.size(); i++) {
                std::string have = fontKey(files_[i].family);
                if (!have.empty() && (want.find(have) != std::string::npos || have.find(want) != std::string::npos)) {
                    slotFile_[slot] = int(i);
                    break;
                }
            }
    }
    // Sub fonts without a file use the main font.
    for (size_t slot = 1; slot < 4; slot++)
        if (slotFile_[slot] < 0) slotFile_[slot] = slotFile_[0];
    for (auto& [k, f] : fonts_) TTF_CloseFont(f);
    fonts_.clear();
    dropTextCache();
}

TTF_Font* SdlGfx::font(int index, int size) {
    index = std::clamp(index, 0, 3);
    size = std::clamp(size, 4, 400);
    auto key = std::make_pair(index, size);
    auto it = fonts_.find(key);
    if (it != fonts_.end()) return it->second;
    TTF_Font* f = nullptr;
    int file = slotFile_[size_t(index)];
    const std::vector<uint8_t>* data = file >= 0 ? &files_[size_t(file)].data : &fallbackData_;
    if (data->empty() && !fallbackData_.empty()) data = &fallbackData_;
    if (!data->empty()) {
        SDL_RWops* rw = SDL_RWFromConstMem(data->data(), int(data->size()));
        // WOLF's font sizes are em heights in pixels, like Windows' character height.
        f = rw ? TTF_OpenFontRW(rw, 1, size) : nullptr;
    }
    fonts_[key] = f;
    return f;
}

TexturePtr SdlGfx::renderText(const std::string& utf8, const TextStyle& style) {
    if (utf8.empty()) return nullptr;
    std::string key = std::to_string(style.font) + "/" + std::to_string(style.size) + "/" + (style.antialias ? "a" : "n") +
                      "/" + utf8;
    auto it = textCache_.find(key);
    if (it != textCache_.end()) {
        textOrder_.splice(textOrder_.end(), textOrder_, it->second.order);
        return it->second.tex;
    }
    TTF_Font* f = font(style.font, style.size);
    if (!f) return nullptr;
    SDL_Color white{255, 255, 255, 255};
    SDL_Surface* s = style.antialias ? TTF_RenderUTF8_Blended(f, utf8.c_str(), white)
                                     : TTF_RenderUTF8_Solid(f, utf8.c_str(), white);
    if (!s) return nullptr;
    SDL_Texture* t = SDL_CreateTextureFromSurface(r_, s);
    int w = s->w, h = s->h;
    SDL_FreeSurface(s);
    if (!t) return nullptr;
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    TexturePtr tex = std::make_shared<SdlTexture>(t, w, h);
    textOrder_.push_back(key);
    textCache_[key] = CacheEntry{tex, std::prev(textOrder_.end())};
    while (textCache_.size() > 1500) {
        textCache_.erase(textOrder_.front());
        textOrder_.pop_front();
    }
    return tex;
}

int SdlGfx::textWidth(const std::string& utf8, const TextStyle& style) {
    TTF_Font* f = font(style.font, style.size);
    if (!f) return int(utf8.size()) * style.size / 2;
    int w = 0, h = 0;
    TTF_SizeUTF8(f, utf8.c_str(), &w, &h);
    return w;
}

int SdlGfx::lineHeight(const TextStyle& style) {
    TTF_Font* f = font(style.font, style.size);
    if (!f) return style.size + 2;
    return std::max(TTF_FontHeight(f), style.size + 2);
}

TexturePtr SdlGfx::copyScreen() {
    TexturePtr copy = createTarget(screen_->width(), screen_->height());
    if (!copy) return nullptr;
    SDL_Texture* prev = SDL_GetRenderTarget(r_);
    SDL_SetRenderTarget(r_, static_cast<SdlTexture*>(copy.get())->tex);
    SDL_SetTextureBlendMode(screen_->tex, SDL_BLENDMODE_NONE);
    SDL_RenderCopy(r_, screen_->tex, nullptr, nullptr);
    SDL_SetTextureBlendMode(screen_->tex, SDL_BLENDMODE_BLEND);
    SDL_SetRenderTarget(r_, prev);
    return copy;
}

std::vector<uint8_t> SdlGfx::readScreen(int& w, int& h) {
    w = screen_->width();
    h = screen_->height();
    std::vector<uint8_t> px(size_t(w * h * 4));
    SDL_Texture* prev = SDL_GetRenderTarget(r_);
    SDL_SetRenderTarget(r_, screen_->tex);
    SDL_RenderReadPixels(r_, nullptr, SDL_PIXELFORMAT_ABGR8888, px.data(), w * 4);
    SDL_SetRenderTarget(r_, prev);
    return px;
}

void SdlGfx::dropTextCache() {
    textCache_.clear();
    textOrder_.clear();
}

}  // namespace wolf
