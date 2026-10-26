// Tests of the data readers, the interpreter and saves, on synthetic data only (no game files).
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include "data/Project.hpp"
#include "data/WolfData.hpp"
#include "engine/Game.hpp"
#include "engine/Platform.hpp"

using namespace wolf;

namespace {

int failures = 0;

void check(bool ok, const std::string& what) {
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", what.c_str());
        failures++;
    }
}

// Writes WOLF's little-endian layout.
struct Writer {
    Bytes data;
    void u8(uint8_t v) { data.push_back(v); }
    void i32(int32_t v) {
        for (int i = 0; i < 4; i++) data.push_back(uint8_t(uint32_t(v) >> (8 * i)));
    }
    void str(const std::string& s) {
        i32(int32_t(s.size() + 1));
        data.insert(data.end(), s.begin(), s.end());
        data.push_back(0);
    }
    void command(int32_t code, std::vector<int32_t> args, uint8_t indent = 0, std::vector<std::string> strings = {}) {
        u8(uint8_t(args.size() + 1));
        i32(code);
        for (int32_t a : args) i32(a);
        u8(indent);
        u8(uint8_t(strings.size()));
        for (auto& s : strings) str(s);
        u8(0);
    }
};

Command cmd(int32_t code, std::vector<int32_t> args, uint8_t indent = 0, std::vector<std::string> strings = {}) {
    Command c;
    c.code = code;
    c.args = std::move(args);
    c.indent = indent;
    c.strings = std::move(strings);
    return c;
}

// A CommonEvent.dat (v2 layout, not encrypted) with one common event.
Bytes commonEventFile(const std::string& name) {
    Writer w;
    w.u8(0);  // indicator byte
    for (uint8_t b : {0x57, 0x00, 0x00, 0x4F, 0x4C, 0x00, 0x46, 0x43, 0x00}) w.u8(b);
    w.u8(0x90);  // version
    w.i32(1);    // one common
    w.u8(0x8E);
    w.i32(0);           // id
    w.u8(0x20 | 0x01);  // "==", auto
    w.i32(2000000);
    w.i32(0);
    w.u8(1);  // number arguments
    w.u8(0);  // string arguments
    w.str(name);
    w.i32(2);  // commands
    w.command(121, {2000001, 5, 0, 0});
    w.command(0, {});
    w.str("");
    w.str("");
    w.u8(0x8F);
    w.i32(0);  // argument names
    w.i32(0);  // argument types
    w.i32(0);  // choice strings
    w.i32(0);  // choice values
    w.i32(1);  // argument defaults
    w.i32(7);
    w.u8(0x90);
    w.i32(0);
    for (int i = 0; i < 100; i++) w.str("");
    w.u8(0x91);
    w.str("");
    w.u8(0x91);
    return w.data;
}

class NullTexture : public Texture {
public:
    NullTexture(int w, int h) : w_(w), h_(h) {}
    int width() const override { return w_; }
    int height() const override { return h_; }

private:
    int w_, h_;
};

class NullGfx : public Gfx {
public:
    TexturePtr loadTexture(const std::vector<uint8_t>&) override { return std::make_shared<NullTexture>(1, 1); }
    TexturePtr createTarget(int w, int h) override { return std::make_shared<NullTexture>(w, h); }
    void setTarget(const TexturePtr&) override {}
    void clear(Color) override {}
    void drawQuad(const TexturePtr&, RectI, const PointF*, Color, Blend) override {}
    void fillRect(RectI, Color, Blend) override {}
    TexturePtr renderText(const std::string& s, const TextStyle& st) override {
        return s.empty() ? nullptr : std::make_shared<NullTexture>(int(s.size()) * st.size / 2, st.size);
    }
    int textWidth(const std::string& s, const TextStyle& st) override { return int(s.size()) * st.size / 2; }
    int lineHeight(const TextStyle& st) override { return st.size; }
    void addFont(const std::string&, const std::vector<uint8_t>&) override {}
    void setFonts(const std::vector<std::string>&) override {}
    TexturePtr copyScreen() override { return std::make_shared<NullTexture>(1, 1); }
    std::vector<uint8_t> readScreen(int& w, int& h) override {
        w = h = 1;
        return {0, 0, 0, 255};
    }
};

class NullAudio : public Audio {
public:
    void play(Channel, const std::string&, const std::vector<uint8_t>&, int, int, int, int, int) override {}
    void stop(Channel, int) override {}
    int positionMs(Channel) override { return 0; }
    int lengthMs(Channel) override { return 0; }
    void setMasterVolume(Channel, int) override {}
};

void testReader() {
    Writer w;
    w.i32(-2);
    w.str("abc");
    Reader r(w.data);
    check(r.i32() == -2, "i32");
    check(r.str() == "abc", "str");
    check(r.eof(), "eof");
    const uint8_t sjis[] = {0x83, 0x65, 0x83, 0x58, 0x83, 0x67};  // テスト
    check(sjisToUtf8(sjis, sizeof sjis) == "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88", "Shift-JIS to UTF-8");
}

void testCommonEvents() {
    auto commons = parseCommonEvents(commonEventFile("start"));
    check(commons.size() == 1, "one common event");
    if (commons.empty()) return;
    const CommonEvent& c = commons[0];
    check(c.valid && c.name == "start", "common name");
    check(c.trigger == 1 && c.op == 0x20 && c.left == 2000000, "common trigger");
    check(c.commands.size() == 2 && c.commands[0].code == 121 && c.commands[0].arg(0) == 2000001, "common commands");
    check(c.argDefaults.size() == 1 && c.argDefaults[0] == 7, "argument defaults");
}

struct TestGame {
    std::filesystem::path folder;
    NullGfx gfx;
    NullAudio audio;
    std::unique_ptr<Game> game;

    explicit TestGame(std::vector<Command> commands) {
        folder = std::filesystem::temp_directory_path() / ("wolf-test-" + std::to_string(::getpid()));
        std::filesystem::create_directories(folder / "Saves");
        auto project = std::make_unique<Project>(folder.string(), Project::Empty{});
        project->game.u8.assign(32, 0);
        CommonEvent c;
        c.valid = true;
        c.name = "test";
        c.trigger = 1;  // auto while V[0] == 0
        c.op = 0x20;
        c.left = 2000000;
        c.commands = std::move(commands);
        c.commands.push_back(cmd(0, {}));
        c.selfVarNames.resize(100);
        project->commons.push_back(c);
        HostCallbacks host;
        host.log = [](const std::string&) {};
        game = std::make_unique<Game>(std::move(project), gfx, audio, (folder / "Saves").string(), host);
        game->start();
    }
    ~TestGame() {
        game.reset();
        std::error_code ignored;
        std::filesystem::remove_all(folder, ignored);
    }
    void frames(int n) {
        InputState input;
        for (int i = 0; i < n; i++) game->frame(input);
    }
};

void testInterpreter() {
    TestGame t({
        cmd(121, {2000001, 5, 0, 0}),                // V1 = 5
        cmd(121, {2000002, 2000001, 3, 0}),          // V2 = V1 + 3
        cmd(121, {2000003, 4, 0, 0x0300}),           // V3 *= 4 (V3 starts at 0)
        cmd(111, {0x11, 2000002, 8, 0x12}),          // if V2 == 8, else
        cmd(401, {1}),
        cmd(121, {2000004, 1, 0, 0}, 1),             //   V4 = 1
        cmd(0, {}, 1),
        cmd(420, {0}),
        cmd(121, {2000004, 2, 0, 0}, 1),             //   V4 = 2
        cmd(0, {}, 1),
        cmd(499, {}),
        cmd(170, {}),                                // loop
        cmd(121, {2000005, 1, 0, 0x0100}, 1),        //   V5 += 1
        cmd(111, {0x01, 2000005, 3, 0x11}, 1),       //   if V5 >= 3: break
        cmd(401, {1}, 1),
        cmd(171, {}, 2),
        cmd(0, {}, 2),
        cmd(499, {}, 1),
        cmd(0, {}, 1),
        cmd(498, {}),
        cmd(122, {3000000, 0, 0}, 0, {"V2=\\v[2]"}), // S0 = "V2=\v[2]"
        cmd(121, {2000000, 1, 0, 0}),                // V0 = 1: the common stops
    });
    t.frames(3);
    Game& g = *t.game;
    check(g.getValue(2000001) == 5, "set variable");
    check(g.getValue(2000002) == 8, "addition");
    check(g.getValue(2000003) == 0, "multiply-assign");
    check(g.getValue(2000004) == 1, "conditional branch");
    check(g.getValue(2000005) == 3, "loop with break");
    check(g.getString(3000000) == "V2=8", "string with variable code, got '" + g.getString(3000000) + "'");
    check(g.getValue(2000000) == 1, "common ran to the end");
    check(g.getValue(9000000 + 0) == g.getValue(9000000), "system variables readable");
}

void testSaves() {
    TestGame t({cmd(121, {2000000, 1, 0, 0})});
    t.frames(2);
    Game& g = *t.game;
    g.setValue(2000010, 42);
    g.setString(3000001, "hello");
    check(g.save(1), "save");
    g.setValue(2000010, 0);
    g.setString(3000001, "");
    check(g.load(1), "load");
    t.frames(1);  // a load applies between frames
    check(g.getValue(2000010) == 42, "number restored by load");
    check(g.getString(3000001) == "hello", "string restored by load");
}

void testCheats() {
    TestGame t({cmd(121, {2000000, 1, 0, 0})});
    t.frames(1);
    std::string status = t.game->cheat("status", {});
    check(!status.empty() && status.front() == '{', "cheat status is JSON");
    t.game->cheat("setVariable", {"7", "99"});
    check(t.game->getValue(2000007) == 99, "cheat sets a variable");
}

}  // namespace

int main() {
    testReader();
    testCommonEvents();
    testInterpreter();
    testSaves();
    testCheats();
    if (failures) {
        std::fprintf(stderr, "%d failures\n", failures);
        return 1;
    }
    std::printf("all tests passed\n");
    return 0;
}
