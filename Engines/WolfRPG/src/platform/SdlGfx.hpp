// Gfx with SDL2's renderer (Metal on iOS) and SDL_ttf for text.
#pragma once

#include <SDL.h>
#include <SDL_ttf.h>

#include <list>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

#include "../engine/Platform.hpp"

namespace wolf {

class SdlTexture : public Texture {
public:
    SdlTexture(SDL_Texture* t, int w, int h) : tex(t), w_(w), h_(h) {}
    ~SdlTexture() override { if (tex) SDL_DestroyTexture(tex); }
    int width() const override { return w_; }
    int height() const override { return h_; }
    SDL_Texture* tex;

private:
    int w_, h_;
};

class SdlGfx : public Gfx {
public:
    SdlGfx(SDL_Renderer* renderer, int screenW, int screenH, std::string fallbackFont);
    ~SdlGfx() override;

    TexturePtr loadTexture(const std::vector<uint8_t>& data) override;
    TexturePtr createTarget(int w, int h) override;
    void setTarget(const TexturePtr& target) override;
    void clear(Color c) override;
    void drawQuad(const TexturePtr& tex, RectI src, const PointF p[4], Color mod, Blend blend) override;
    void fillRect(RectI r, Color c, Blend blend) override;
    TexturePtr renderText(const std::string& utf8, const TextStyle& style) override;
    int textWidth(const std::string& utf8, const TextStyle& style) override;
    int lineHeight(const TextStyle& style) override;
    void addFont(const std::string& file, const std::vector<uint8_t>& data) override;
    void setFonts(const std::vector<std::string>& families) override;
    TexturePtr copyScreen() override;
    std::vector<uint8_t> readScreen(int& w, int& h) override;

    SDL_Texture* screen() const { return screen_->tex; }
    // Lost render targets (iOS after the app was in the background) must be redrawn.
    void dropTextCache();

private:
    TTF_Font* font(int index, int size);
    void applyBlend(SDL_Texture* t, Blend b);

    SDL_Renderer* r_;
    std::shared_ptr<SdlTexture> screen_;
    TexturePtr current_;
    std::string fallbackFont_;
    std::vector<uint8_t> fallbackData_;
    // Font files of the game: data kept alive for SDL_ttf, by family name.
    struct FontFile { std::string family; std::vector<uint8_t> data; };
    std::vector<FontFile> files_;
    std::vector<int> slotFile_;  // font slot (0 main, 1-3 sub) -> index into files_, -1 fallback
    std::map<std::pair<int, int>, TTF_Font*> fonts_;
    // Rendered text, least recently used first.
    struct CacheEntry { TexturePtr tex; std::list<std::string>::iterator order; };
    std::unordered_map<std::string, CacheEntry> textCache_;
    std::list<std::string> textOrder_;
    SDL_BlendMode subtract_, multiply_;
};

}  // namespace wolf
