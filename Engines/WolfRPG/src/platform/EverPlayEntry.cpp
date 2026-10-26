// The one function WolfRPG.framework exports; EverPlay's WolfLauncher.swift calls it with dlsym.
#include <SDL.h>

#include <csignal>
#include <cstdio>
#include <cstring>
#include <execinfo.h>
#include <unistd.h>

#include "Runner.hpp"

extern "C" {
void everplay_attach_sdl_windows(void);
void everplay_install_wolf_gamepad(void);
}

namespace {

// On a crash: the signal and stack go to the log, which EverPlay shows at its next start.
void crashed(int signalNumber) {
    char line[64];
    int length = std::snprintf(line, sizeof line, "\nEverPlay: WolfRPG crashed with signal %d\n", signalNumber);
    write(STDERR_FILENO, line, size_t(length));
    void* frames[64];
    int count = backtrace(frames, 64);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    std::signal(signalNumber, SIG_DFL);
    std::raise(signalNumber);
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int everplay_wolf_main(const char* game, const char* saves,
                                                                         const char* font, const char* soundFont,
                                                                         const char* cheats, const char* log) {
    if (log && *log && std::freopen(log, "w", stderr)) {
        dup2(fileno(stderr), STDOUT_FILENO);
        setvbuf(stderr, nullptr, _IONBF, 0);
    }
    int signals[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP};
    for (int s : signals) std::signal(s, crashed);
    wolf::RunOptions o;
    o.game = game ? game : "";
    o.saves = saves ? saves : "";
    o.fallbackFont = font ? font : "";
    o.soundFont = soundFont ? soundFont : "";
    o.cheats = cheats ? cheats : "";
    // EverPlay owns UIApplicationMain; SDL runs inside it.
    SDL_SetMainReady();
#if defined(__APPLE__)
    everplay_attach_sdl_windows();
    everplay_install_wolf_gamepad();
#endif
    return wolf::runGame(o);
}
