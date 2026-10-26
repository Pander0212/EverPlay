// What the engine needs from the platform: drawing, text, sound, input and files for saves.
// SdlPlatform implements it with SDL2 (iOS: Metal, Linux: any renderer or headless).
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace wolf {

struct Color {
    uint8_t r = 255, g = 255, b = 255, a = 255;
};

struct PointF {
    float x = 0, y = 0;
};

struct RectI {
    int x = 0, y = 0, w = 0, h = 0;
};

enum class Blend { Normal, Add, Subtract, Multiply };

class Texture {
public:
    virtual ~Texture() = default;
    virtual int width() const = 0;
    virtual int height() const = 0;
    // Whether the pixel at (x, y) is not fully transparent (for picking pictures under the mouse).
    virtual bool opaqueAt(int x, int y) const { (void)x; (void)y; return true; }
};
using TexturePtr = std::shared_ptr<Texture>;

// Glyphs of one font at one pixel size.
struct TextStyle {
    int font = 0;          // 0 main font, 1-3 sub fonts
    int size = 16;
    bool antialias = true;
    bool bold = false;
};

class Gfx {
public:
    virtual ~Gfx() = default;
    // Decodes an image file (PNG, BMP, JPG). Pure black/magenta keys are not applied here.
    virtual TexturePtr loadTexture(const std::vector<uint8_t>& data) = 0;
    virtual TexturePtr createTarget(int w, int h) = 0;
    virtual void setTarget(const TexturePtr& target) = 0;  // nullptr: the game screen
    virtual void clear(Color c) = 0;
    // Draws `src` of `tex` onto the quad p[0..3] (top-left, top-right, bottom-right, bottom-left).
    virtual void drawQuad(const TexturePtr& tex, RectI src, const PointF p[4], Color mod, Blend blend) = 0;
    virtual void fillRect(RectI r, Color c, Blend blend) = 0;
    // A texture with one line of text in white (tinted when drawn); nullptr for empty text.
    virtual TexturePtr renderText(const std::string& utf8, const TextStyle& style) = 0;
    virtual int textWidth(const std::string& utf8, const TextStyle& style) = 0;
    virtual int lineHeight(const TextStyle& style) = 0;
    // Registers a font file (from the game folder) by family name; returns false if unusable.
    virtual void addFont(const std::string& family, const std::vector<uint8_t>& data) = 0;
    virtual void setFonts(const std::vector<std::string>& families) = 0;
    // The game screen as a texture (to freeze it for transitions); copyTexture makes a snapshot.
    virtual TexturePtr copyScreen() = 0;
    // RGBA pixels of the game screen, for save thumbnails and tests.
    virtual std::vector<uint8_t> readScreen(int& w, int& h) = 0;
};

enum class Channel { BGM, BGS, SE };

class Audio {
public:
    virtual ~Audio() = default;
    // volume and pitch in percent; startMs: where to begin; loopMs: loop start for BGM/BGS.
    virtual void play(Channel ch, const std::string& name, const std::vector<uint8_t>& data, int volume, int pitch,
                      int startMs, int loopMs, int fadeMs) = 0;
    virtual void stop(Channel ch, int fadeMs) = 0;
    virtual int positionMs(Channel ch) = 0;
    virtual int lengthMs(Channel ch) = 0;
    virtual void setMasterVolume(Channel ch, int percent) = 0;
};

// Wolf's keys. Arrow keys, OK (Z/Space/Enter), Cancel (X/Esc), Sub (Shift).
enum Key : int { KeyDown = 0, KeyLeft, KeyRight, KeyUp, KeyOK, KeyCancel, KeySub, KeyCount };

struct InputState {
    bool down[KeyCount] = {};
    // Raw keyboard state by WOLF's keyboard codes (100 + DirectInput scan code), for "Key input".
    bool keyboard[512] = {};
    int mouseX = 0, mouseY = 0;
    bool mouseLeft = false, mouseRight = false, mouseMiddle = false;
    int wheel = 0;
};

}  // namespace wolf
