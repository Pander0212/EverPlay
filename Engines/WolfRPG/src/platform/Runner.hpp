#pragma once

#include <string>
#include <vector>

namespace wolf {

struct RunOptions {
    std::string game;           // the game folder (with Game.exe / Data)
    std::string saves;          // where saves go
    std::string soundFont;      // .sf2 for MIDI music (optional)
    std::string fallbackFont;   // a Japanese font for games whose fonts are missing
    std::string log;            // log file (empty: stderr)
    std::string cheats;         // folder with cheat requests from EverPlay (empty: none)
    // Headless (tests): no window, software rendering, scripted input, screenshots.
    bool headless = false;
    int frames = 0;             // headless: frames to run
    std::string script;         // headless: "frame key down|up" lines, "frame shot name"
    std::string shotDir;        // headless: where screenshots go
    bool fastForward = false;   // desktop: run as fast as possible
};

int runGame(const RunOptions& options);

}  // namespace wolf
