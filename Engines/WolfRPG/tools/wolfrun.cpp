// Runs a WOLF RPG game on the desktop, or headless for tests:
//   wolfrun <game> [--saves DIR] [--font FILE] [--soundfont FILE]
//   wolfrun <game> --headless FRAMES --script FILE --shots DIR [--saves DIR] [--font FILE]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>

#include "../src/platform/Runner.hpp"

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: wolfrun <game> [options]\n");
        return 2;
    }
    wolf::RunOptions o;
    o.game = argv[1];
    o.saves = "/tmp/wolfrun-saves";
    o.shotDir = ".";
    for (int i = 2; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "--saves") o.saves = next();
        else if (a == "--font") o.fallbackFont = next();
        else if (a == "--soundfont") o.soundFont = next();
        else if (a == "--headless") { o.headless = true; o.frames = std::atoi(next().c_str()); }
        else if (a == "--script") {
            std::ifstream f(next());
            std::stringstream ss;
            ss << f.rdbuf();
            o.script = ss.str();
        } else if (a == "--shots") o.shotDir = next();
        else if (a == "--fast") o.fastForward = true;
        else if (a == "--log") o.log = next();
    }
    return wolf::runGame(o);
}
