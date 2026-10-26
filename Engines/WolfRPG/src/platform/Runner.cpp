#include "Runner.hpp"

#include <SDL.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>

#include <dirent.h>
#include <unistd.h>

#include "../engine/Game.hpp"
#include "SdlAudio.hpp"
#include "SdlGfx.hpp"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../third_party/stb/stb_image_write.h"

namespace wolf {

namespace {

FILE* g_log = nullptr;

void logLine(const std::string& s) {
    FILE* f = g_log ? g_log : stderr;
    std::fprintf(f, "%s\n", s.c_str());
    std::fflush(f);
}

int keyFromName(const std::string& n) {
    if (n == "down") return KeyDown;
    if (n == "left") return KeyLeft;
    if (n == "right") return KeyRight;
    if (n == "up") return KeyUp;
    if (n == "ok") return KeyOK;
    if (n == "cancel") return KeyCancel;
    if (n == "sub") return KeySub;
    return -1;
}

// WOLF's keyboard codes: 100 + the DirectInput (PC/AT set 1) scan code.
int wolfKeyCode(SDL_Scancode k) {
    static const std::pair<SDL_Scancode, int> table[] = {
        {SDL_SCANCODE_ESCAPE, 1}, {SDL_SCANCODE_1, 2}, {SDL_SCANCODE_2, 3}, {SDL_SCANCODE_3, 4}, {SDL_SCANCODE_4, 5},
        {SDL_SCANCODE_5, 6}, {SDL_SCANCODE_6, 7}, {SDL_SCANCODE_7, 8}, {SDL_SCANCODE_8, 9}, {SDL_SCANCODE_9, 10},
        {SDL_SCANCODE_0, 11}, {SDL_SCANCODE_MINUS, 12}, {SDL_SCANCODE_EQUALS, 13}, {SDL_SCANCODE_BACKSPACE, 14},
        {SDL_SCANCODE_TAB, 15}, {SDL_SCANCODE_Q, 16}, {SDL_SCANCODE_W, 17}, {SDL_SCANCODE_E, 18}, {SDL_SCANCODE_R, 19},
        {SDL_SCANCODE_T, 20}, {SDL_SCANCODE_Y, 21}, {SDL_SCANCODE_U, 22}, {SDL_SCANCODE_I, 23}, {SDL_SCANCODE_O, 24},
        {SDL_SCANCODE_P, 25}, {SDL_SCANCODE_LEFTBRACKET, 26}, {SDL_SCANCODE_RIGHTBRACKET, 27}, {SDL_SCANCODE_RETURN, 28},
        {SDL_SCANCODE_LCTRL, 29}, {SDL_SCANCODE_A, 30}, {SDL_SCANCODE_S, 31}, {SDL_SCANCODE_D, 32}, {SDL_SCANCODE_F, 33},
        {SDL_SCANCODE_G, 34}, {SDL_SCANCODE_H, 35}, {SDL_SCANCODE_J, 36}, {SDL_SCANCODE_K, 37}, {SDL_SCANCODE_L, 38},
        {SDL_SCANCODE_SEMICOLON, 39}, {SDL_SCANCODE_APOSTROPHE, 40}, {SDL_SCANCODE_GRAVE, 41}, {SDL_SCANCODE_LSHIFT, 42},
        {SDL_SCANCODE_BACKSLASH, 43}, {SDL_SCANCODE_Z, 44}, {SDL_SCANCODE_X, 45}, {SDL_SCANCODE_C, 46}, {SDL_SCANCODE_V, 47},
        {SDL_SCANCODE_B, 48}, {SDL_SCANCODE_N, 49}, {SDL_SCANCODE_M, 50}, {SDL_SCANCODE_COMMA, 51}, {SDL_SCANCODE_PERIOD, 52},
        {SDL_SCANCODE_SLASH, 53}, {SDL_SCANCODE_RSHIFT, 54}, {SDL_SCANCODE_KP_MULTIPLY, 55}, {SDL_SCANCODE_LALT, 56},
        {SDL_SCANCODE_SPACE, 57}, {SDL_SCANCODE_CAPSLOCK, 58}, {SDL_SCANCODE_F1, 59}, {SDL_SCANCODE_F2, 60},
        {SDL_SCANCODE_F3, 61}, {SDL_SCANCODE_F4, 62}, {SDL_SCANCODE_F5, 63}, {SDL_SCANCODE_F6, 64}, {SDL_SCANCODE_F7, 65},
        {SDL_SCANCODE_F8, 66}, {SDL_SCANCODE_F9, 67}, {SDL_SCANCODE_F10, 68}, {SDL_SCANCODE_KP_7, 71}, {SDL_SCANCODE_KP_8, 72},
        {SDL_SCANCODE_KP_9, 73}, {SDL_SCANCODE_KP_MINUS, 74}, {SDL_SCANCODE_KP_4, 75}, {SDL_SCANCODE_KP_5, 76},
        {SDL_SCANCODE_KP_6, 77}, {SDL_SCANCODE_KP_PLUS, 78}, {SDL_SCANCODE_KP_1, 79}, {SDL_SCANCODE_KP_2, 80},
        {SDL_SCANCODE_KP_3, 81}, {SDL_SCANCODE_KP_0, 82}, {SDL_SCANCODE_KP_PERIOD, 83}, {SDL_SCANCODE_F11, 87},
        {SDL_SCANCODE_F12, 88}, {SDL_SCANCODE_KP_ENTER, 156}, {SDL_SCANCODE_RCTRL, 157}, {SDL_SCANCODE_KP_DIVIDE, 181},
        {SDL_SCANCODE_RALT, 184}, {SDL_SCANCODE_HOME, 199}, {SDL_SCANCODE_UP, 200}, {SDL_SCANCODE_PAGEUP, 201},
        {SDL_SCANCODE_LEFT, 203}, {SDL_SCANCODE_RIGHT, 205}, {SDL_SCANCODE_END, 207}, {SDL_SCANCODE_DOWN, 208},
        {SDL_SCANCODE_PAGEDOWN, 209}, {SDL_SCANCODE_INSERT, 210}, {SDL_SCANCODE_DELETE, 211},
    };
    for (const auto& [sc, code] : table)
        if (sc == k) return 100 + code;
    return -1;
}

void applyKey(InputState& in, SDL_Keycode k, SDL_Scancode sc, bool down) {
    switch (k) {
        case SDLK_UP: case SDLK_KP_8: in.down[KeyUp] = down; break;
        case SDLK_DOWN: case SDLK_KP_2: in.down[KeyDown] = down; break;
        case SDLK_LEFT: case SDLK_KP_4: in.down[KeyLeft] = down; break;
        case SDLK_RIGHT: case SDLK_KP_6: in.down[KeyRight] = down; break;
        case SDLK_z: case SDLK_SPACE: case SDLK_RETURN: case SDLK_KP_ENTER: in.down[KeyOK] = down; break;
        case SDLK_x: case SDLK_ESCAPE: case SDLK_BACKSPACE: in.down[KeyCancel] = down; break;
        case SDLK_LSHIFT: case SDLK_RSHIFT: in.down[KeySub] = down; break;
    }
    int code = wolfKeyCode(sc);
    if (code >= 0 && code < 512) in.keyboard[code] = down;
}

// EverPlay's cheat screen writes "request-<id>" files ("call\t<id>\t<method>\t<typed args>…",
// args as n:/s:/b: values) and waits for "reply-<id>.json".
void serveCheats(Game& game, const std::string& folder) {
    DIR* d = opendir(folder.c_str());
    if (!d) return;
    std::vector<std::string> requests;
    while (dirent* e = readdir(d)) {
        std::string name = e->d_name;
        if (name.rfind("request-", 0) == 0) requests.push_back(name);
    }
    closedir(d);
    for (const auto& name : requests) {
        std::string path = folder + "/" + name;
        std::ifstream in(path);
        std::stringstream ss;
        ss << in.rdbuf();
        in.close();
        unlink(path.c_str());
        std::vector<std::string> parts;
        std::string part;
        std::istringstream fields(ss.str());
        while (std::getline(fields, part, '\t')) parts.push_back(part);
        if (parts.size() < 3 || parts[0] != "call") continue;
        std::vector<std::string> args;
        for (size_t i = 3; i < parts.size(); i++) args.push_back(parts[i].size() > 2 ? parts[i].substr(2) : std::string());
        std::string reply = game.cheat(parts[2], args);
        std::string out = folder + "/reply-" + parts[1] + ".json";
        std::string temp = out + ".tmp";
        if (FILE* f = std::fopen(temp.c_str(), "w")) {
            std::fputs(reply.c_str(), f);
            std::fclose(f);
            std::rename(temp.c_str(), out.c_str());
        }
    }
}

}  // namespace

int runGame(const RunOptions& o) {
    if (!o.log.empty()) g_log = std::fopen(o.log.c_str(), "w");
    logLine("WolfRPG: starting " + o.game);
    std::unique_ptr<Project> project;
    try {
        project = std::make_unique<Project>(o.game);
    } catch (const std::exception& e) {
        logLine(std::string("WolfRPG: cannot read the game data: ") + e.what());
        return 2;
    }
    for (const auto& w : project->warnings) logLine("WolfRPG: " + w);

    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
#ifdef __APPLE__
    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
#endif
    Uint32 flags = SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_TIMER;
    if (o.headless) SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);
    if (SDL_Init(flags) != 0) {
        logLine(std::string("WolfRPG: SDL_Init failed: ") + SDL_GetError());
        return 3;
    }
    // Screen size from Game.dat (temporary Game for the numbers is not needed: read them here).
    int gw = project->game.setting16(16), gh = project->game.setting16(17);
    if (gw <= 0 || gh <= 0) {
        int ts = project->game.setting(0);
        gw = ts > 0 && ts <= 16 ? 320 : 640;
        gh = ts > 0 && ts <= 16 ? 240 : 480;
    }
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Surface* headlessSurface = nullptr;
    if (o.headless) {
        headlessSurface = SDL_CreateRGBSurfaceWithFormat(0, gw, gh, 32, SDL_PIXELFORMAT_ARGB8888);
        renderer = SDL_CreateSoftwareRenderer(headlessSurface);
    } else {
        Uint32 wflags = SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE;
#if defined(__APPLE__) && TARGET_OS_IPHONE
        wflags |= SDL_WINDOW_FULLSCREEN | SDL_WINDOW_BORDERLESS;
#endif
        std::string title = project->game.title();
        window = SDL_CreateWindow(title.c_str(), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, gw, gh, wflags);
        if (!window) {
            logLine(std::string("WolfRPG: no window: ") + SDL_GetError());
            SDL_Quit();
            return 4;
        }
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | (o.fastForward ? 0 : SDL_RENDERER_PRESENTVSYNC));
        if (!renderer) renderer = SDL_CreateRenderer(window, -1, 0);
    }
    if (!renderer) {
        logLine(std::string("WolfRPG: no renderer: ") + SDL_GetError());
        SDL_Quit();
        return 5;
    }
    SDL_RendererInfo info{};
    SDL_GetRendererInfo(renderer, &info);
    logLine(std::string("WolfRPG: renderer ") + (info.name ? info.name : "?") + ", screen " + std::to_string(gw) + "x" +
            std::to_string(gh));

    SdlGfx gfx(renderer, gw, gh, o.fallbackFont);
    SdlAudio audio(o.headless ? std::string() : o.soundFont);
    bool quit = false;
    HostCallbacks host;
    host.log = [](const std::string& s) { logLine("WolfRPG: " + s); };
    host.quit = [&quit]() { quit = true; };
    Game game(std::move(project), gfx, audio, o.saves, host);
    game.trace = std::getenv("WOLF_TRACE") != nullptr;
    if (const char* from = std::getenv("WOLF_TRACE_FROM")) game.traceFrom = std::atoi(from);
    game.start();

    InputState input;
    // Headless script: frame -> actions
    std::multimap<int, std::string> script;
    if (o.headless && !o.script.empty()) {
        std::istringstream lines(o.script);
        std::string line;
        while (std::getline(lines, line)) {
            std::istringstream ls(line);
            int frame;
            if (ls >> frame) {
                std::string rest;
                std::getline(ls, rest);
                script.emplace(frame, rest);
            }
        }
    }
    auto shot = [&](const std::string& name) {
        int w, h;
        auto px = gfx.readScreen(w, h);
        std::string path = o.shotDir + "/" + name + ".png";
        stbi_write_png(path.c_str(), w, h, 4, px.data(), w * 4);
        logLine("WolfRPG: screenshot " + path);
    };

    bool paused = false;
    double accumulator = 0;
    auto last = std::chrono::steady_clock::now();
    int frame = 0;
    while (!quit && !game.quitRequested()) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
                case SDL_QUIT: quit = true; break;
                case SDL_APP_WILLENTERBACKGROUND:
                case SDL_APP_DIDENTERBACKGROUND:
                    // iOS forbids drawing in the background: stop until the app is back.
                    paused = true;
                    audio.pause(true);
                    break;
                case SDL_APP_WILLENTERFOREGROUND:
                case SDL_APP_DIDENTERFOREGROUND:
                    paused = false;
                    audio.pause(false);
                    last = std::chrono::steady_clock::now();
                    break;
                case SDL_KEYDOWN:
                case SDL_KEYUP:
                    applyKey(input, e.key.keysym.sym, e.key.keysym.scancode, e.type == SDL_KEYDOWN);
                    if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F12) {
                        // F12: back to the title, as in WOLF.
                    }
                    break;
                case SDL_MOUSEMOTION:
                case SDL_MOUSEBUTTONDOWN:
                case SDL_MOUSEBUTTONUP: {
                    int x = e.type == SDL_MOUSEMOTION ? e.motion.x : e.button.x;
                    int y = e.type == SDL_MOUSEMOTION ? e.motion.y : e.button.y;
                    if (window) {
                        int ww, wh;
                        SDL_GetWindowSize(window, &ww, &wh);
                        double scale = std::min(double(ww) / gw, double(wh) / gh);
                        double ox = (ww - gw * scale) / 2, oy = (wh - gh * scale) / 2;
                        input.mouseX = int((x - ox) / scale);
                        input.mouseY = int((y - oy) / scale);
                    }
                    if (e.type != SDL_MOUSEMOTION) {
                        bool down = e.type == SDL_MOUSEBUTTONDOWN;
                        if (e.button.button == SDL_BUTTON_LEFT) input.mouseLeft = down;
                        else if (e.button.button == SDL_BUTTON_RIGHT) input.mouseRight = down;
                        else if (e.button.button == SDL_BUTTON_MIDDLE) input.mouseMiddle = down;
                    }
                    break;
                }
                case SDL_MOUSEWHEEL: input.wheel = e.wheel.y; break;
                case SDL_RENDER_TARGETS_RESET:
                case SDL_RENDER_DEVICE_RESET:
                    gfx.dropTextCache();
                    break;
            }
        }
        if (paused) {
            SDL_WaitEventTimeout(nullptr, 100);
            continue;
        }
        int steps = 1;
        if (!o.headless) {
            auto now = std::chrono::steady_clock::now();
            accumulator += std::chrono::duration<double>(now - last).count();
            last = now;
            double step = 1.0 / std::max(game.fps(), 1);
            if (o.fastForward) accumulator = step;
            steps = int(accumulator / step);
            accumulator -= steps * step;
            if (steps > 4) { steps = 4; accumulator = 0; }
            if (steps == 0) {
                SDL_Delay(1);
                continue;
            }
        }
        for (int s = 0; s < steps; s++) {
            if (o.headless) {
                auto range = script.equal_range(frame);
                for (auto it = range.first; it != range.second; ++it) {
                    std::istringstream ls(it->second);
                    std::string what, arg;
                    ls >> what >> arg;
                    if (what == "shot") continue;
                    int k = keyFromName(what);
                    if (k >= 0) input.down[k] = arg != "up";
                }
            }
            game.frame(input);
            input.wheel = 0;
            frame++;
        }
        if (!o.cheats.empty() && frame % 10 == 0) serveCheats(game, o.cheats);
        game.draw();
        if (o.headless) {
            auto range = script.equal_range(frame - 1);
            for (auto it = range.first; it != range.second; ++it) {
                std::istringstream ls(it->second);
                std::string what, arg;
                ls >> what >> arg;
                if (what == "shot") shot(arg.empty() ? "frame" + std::to_string(frame) : arg);
                if (what == "state" || what == "shot") logLine(game.debugState());
            }
            if (frame >= o.frames) break;
            continue;
        }
        // Present: the game screen, scaled to fit, centered.
        SDL_SetRenderTarget(renderer, nullptr);
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);
        int ow, oh;
        SDL_GetRendererOutputSize(renderer, &ow, &oh);
        double scale = std::min(double(ow) / gw, double(oh) / gh);
        SDL_FRect dst{float((ow - gw * scale) / 2), float((oh - gh * scale) / 2), float(gw * scale), float(gh * scale)};
        SDL_SetTextureBlendMode(gfx.screen(), SDL_BLENDMODE_NONE);
        SDL_RenderCopyF(renderer, gfx.screen(), nullptr, &dst);
        SDL_SetTextureBlendMode(gfx.screen(), SDL_BLENDMODE_BLEND);
        SDL_RenderPresent(renderer);
    }
    logLine("WolfRPG: finished after " + std::to_string(frame) + " frames");
    SDL_DestroyRenderer(renderer);
    if (headlessSurface) SDL_FreeSurface(headlessSurface);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    if (g_log) std::fclose(g_log);
    g_log = nullptr;
    return 0;
}

}  // namespace wolf
