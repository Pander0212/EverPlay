// The WOLF RPG Editor runtime: game state, the event interpreter, the map, pictures, messages,
// sound and saves. Platform-independent; see Platform.hpp for what it draws and plays with.
#pragma once

#include <array>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

#include "../data/Project.hpp"
#include "Platform.hpp"

namespace wolf {

class Game;

// ---------------------------------------------------------------------------------------------
// Characters: the hero, party members and map events.

struct Character {
    int eventId = -1;            // map event ID; -1 hero, -2..-6 party members
    bool exists = true;
    bool erased = false;
    // Position in half tiles (Wolf's "precise" coordinates). Tile = precise / 2.
    int px = 0, py = 0;
    // Drawing position in pixels of the top-left of the tile the character stands on.
    double realX = 0, realY = 0;
    int direction = 2;           // numpad directions: 2 down, 4 left, 6 right, 8 up, 1/3/7/9 diagonal
    int pattern = 1;             // animation frame (0..patterns-1); 1 = standing in 3-frame sheets
    std::string graphic;
    int tileId = -1;             // a tile instead of a character sheet
    int opacity = 255;
    int blend = 0;
    int height = 0;              // elevation in pixels
    int moveSpeed = 3, moveFrequency = 3, animSpeed = 3;
    int moveType = 0;            // 0 none, 1 custom route, 2 random, 3 toward hero
    bool waitAnim = false, moveAnim = true, fixedDir = false, through = false, above = false;
    bool halfStep = false;       // moves half a tile per step
    bool snake = false;          // zigzag diagonal moves
    int shadow = 0;
    int rangeX = 0, rangeY = 0;  // touch range extension
    bool moving = false;
    double moveRemaining = 0;    // pixels left in the current step
    double dx = 0, dy = 0;       // pixel delta per frame of the current step
    int animCounter = 0;
    int idleCounter = 0;
    int stopCounter = 0;
    int jumpPeak = 0, jumpTotal = 0, jumpCount = 0;
    bool jumping = false;
    // Custom route (the page's or a "Move route" command's).
    std::vector<RouteCommand> route;
    size_t routeIndex = 0;
    bool routeRepeat = false, routeSkip = false, routeFromCommand = false;
    int routeWait = 0;
    bool routeDone = true;
    // Map events only.
    int page = -1;               // active page, -1 none
    int selfVars[10] = {};
    std::vector<int> pageHistory;
    // Effects.
    int flashFrames = 0, flashTotal = 0; Color flashColor;
    int shakeFrames = 0, shakePower = 0;
    int flickerMode = 0;
};

// ---------------------------------------------------------------------------------------------
// Pictures

struct Picture {
    bool used = false;
    int type = 0;               // 0 image, 2 text, 3 window image
    std::string file;           // image or window file
    std::string text;
    TexturePtr texture;         // the image, or the rendered text/window
    int divW = 1, divH = 1, pattern = 1;
    int anchor = 0;             // 0 top-left, 1 center, 2 bottom-left, 3 top-right, 4 bottom-right
    int blend = 0;
    bool scroll = false;        // moves with the map
    bool freePos = false;
    // Current and target values for timed moves.
    struct State {
        double x = 0, y = 0, zoomW = 100, zoomH = 100, angle = 0, opacity = 255;
        double r = 100, g = 100, b = 100;
        double corners[8] = {};
    } cur, from, to;
    int moveFrames = 0, moveTotal = 0, delay = 0;
    int windowW = 0, windowH = 0;
    // Effects
    int effect = -1, effectFrames = 0, effectTotal = 0;
    int effArgs[3] = {};
    double shakeX = 0, shakeY = 0;
    int autoPatternMode = 0, autoPatternWait = 0, autoPatternCounter = 0, autoPatternDir = 1;
    int autoPatternFirst = 1, autoPatternLast = 1;
    int flashR = 0, flashG = 0, flashB = 0, flashFrames = 0, flashTotal = 0;
    // WOLF 3 zoom correction (effect 0xC0): a further zoom in percent on top of the picture's own.
    double corrW = 100, corrH = 100, corrFromW = 100, corrFromH = 100, corrToW = 100, corrToH = 100;
    int corrFrames = 0, corrTotal = 0;
    bool flipX = false, flipY = false;  // WOLF 3 mirror (effect 0xE0)
    int z = 0;                          // WOLF 3 Z order (effect 0x1C0)
    bool textDone = true;
    int textChars = 0, textShown = 0;   // gradual text display
    double textProgress = 0;
    int textW = 0, textH = 0;
};

// ---------------------------------------------------------------------------------------------
// The interpreter

struct Frame {
    const CommandList* commands = nullptr;
    size_t pc = 0;
    int commonId = -1;          // for commons: their ID (self variables, returns)
    int32_t returnTo = 0;       // variable that receives the return value (0: none)
    struct Loop { size_t start; int remaining; bool infinite; };
    std::vector<Loop> loops;
    int eventId = -1;           // the map event this frame belongs to (map events, and commons called from them)
};

struct Context {
    std::vector<Frame> frames;
    enum class Kind { Main, Parallel, ParallelAlways } kind = Kind::Main;
    int mapEventId = -1;        // the map event (-1: a common event)
    int commonId = -1;          // the common event it started from
    int waitFrames = 0;
    enum class Wait { None, Message, Choice, MoveRoute, KeyInput, Transition, PictureText, StringInput, Erase } wait = Wait::None;
    int waitArg = 0;
    bool finished() const { return frames.empty(); }
    int32_t keyTarget = 0;      // KeyInput (123) while waiting
    const Command* waitCmd = nullptr;
};

// ---------------------------------------------------------------------------------------------
// Message window

struct MessageWindow {
    bool open = false;
    std::string text;           // expanded text being shown
    int shown = 0;              // characters shown so far
    double progress = 0;
    bool done = false;          // all text shown
    bool waitingKey = false;
    bool autoClose = false;     // "\^": continue without a key
    int waitAfter = 0;
    int faceId = 0;
    // Choices
    bool choosing = false;
    std::vector<std::string> choices;
    int cursor = 0;
    int cancelCase = -1;        // case index chosen on cancel (-1: none / not allowed, -2: cancel branch)
    bool allowCancel = false;
    int result = -1;            // chosen index, or -2 cancel, -3 left, -4 right
    bool leftBranch = false, rightBranch = false;
    TexturePtr rendered;
    int renderedChars = -1;
    int pauseAnim = 0;
    // Gradual display: position in `text`, characters per second, timing codes.
    size_t pos = 0;
    int speed = 0;              // 0: Sys9
    bool instant = false;       // between "\>" and "\<"
    int pauseFrames = 0;        // "\." waits
    bool keyPause = false;      // "\!" waits for a key
    int textW = 0, textH = 0;
};

// ---------------------------------------------------------------------------------------------

struct ScreenEffects {
    // Screen color change (151): R,G,B in percent (100 = unchanged) and timed transitions.
    double r = 100, g = 100, b = 100, fromR = 100, fromG = 100, fromB = 100, toR = 100, toG = 100, toB = 100;
    int colorFrames = 0, colorTotal = 0;
    // Flash
    Color flash; int flashFrames = 0, flashTotal = 0;
    // Shake (280)
    int shakeType = 2, shakePower = 0, shakeSpeed = 0, shakeFrames = 0; double shakeOffset = 0; int shakeTime = 0;
    // Scroll (281)
    bool scrollLocked = false;
    double scrollX = 0, scrollY = 0;         // pixel offset of the camera from following the hero
    double scrollTargetX = 0, scrollTargetY = 0, scrollSpeed = 0;
    bool scrolling = false, scrollBack = false;
    // Map zoom (290 map)
    double zoom = 100, zoomFrom = 100, zoomTo = 100; int zoomFrames = 0, zoomTotal = 0; double zoomCX = 0, zoomCY = 0;
    // Transitions (160-162)
    bool prepared = false;      // screen frozen, waiting for 162
    TexturePtr frozen;
    int transFrames = 0, transTotal = 0, transType = 0;
    TexturePtr transMask;
    bool fadeOut = false;       // screen is faded out (transition with no target)
};

struct AudioState {
    std::string bgmFile, bgsFile;
    int bgmId = -1, bgsId = -1;
    int bgmVolume = 100, bgmPitch = 100, bgsVolume = 100, bgsPitch = 100;
    int bgmLoop = 0, bgsLoop = 0;
};

// Everything a save holds.
struct SaveState {
    int mapId = 0;
    Character hero;
    std::vector<Character> events;
    std::vector<int32_t> vars, sys;
    std::array<std::vector<int32_t>, 10> spare;
    std::vector<std::string> strs, sysStr;
    std::map<int, std::array<int32_t, 100>> cself;
    std::map<int, std::array<std::string, 5>> cselfStr;
    std::map<int, std::map<int, std::array<int, 10>>> mapSelf;
    std::vector<std::vector<DBRecord>> cdb, udb;
    AudioState audio;
    double r = 100, g = 100, b = 100;
    uint64_t frames = 0;
    std::map<int, Picture> pictures;
};

// What the platform layer asks for besides drawing and sound.
struct HostCallbacks {
    std::function<void(const std::string&)> log;
    std::function<void()> quit;                                  // "End game"
    std::function<std::string(const std::string&, int)> textInput;  // keyboard input (prompt, max chars)
};

class Game {
public:
    Game(std::unique_ptr<Project> project, Gfx& gfx, Audio& audio, std::string saveFolder, HostCallbacks host);
    ~Game();

    void start();
    // One frame: logic from `input`, then drawing to the game screen.
    void frame(const InputState& input);
    void draw();
    int screenWidth() const { return screenW_; }
    int screenHeight() const { return screenH_; }
    int fps() const { return fps_; }
    bool quitRequested() const { return quit_; }
    Project& project() { return *project_; }

    // Variables (also used by cheats). Addresses as in event commands.
    int32_t getValue(int32_t address, const Frame* frame = nullptr);
    void setValue(int32_t address, int32_t value, const Frame* frame = nullptr);
    std::string getString(int32_t address, const Frame* frame = nullptr);
    void setString(int32_t address, const std::string& value, const Frame* frame = nullptr);
    bool isStringAddress(int32_t address) const;

    // Cheats
    int speed = 1;              // frames of logic per drawn frame
    bool cheatThrough = false;
    std::vector<int32_t>& normalVars() { return vars_; }
    const std::vector<std::string>& stringVars() const { return strs_; }
    std::string variableName(int index);
    // A cheat request from EverPlay; returns the JSON reply (Cheats.cpp).
    std::string cheat(const std::string& method, const std::vector<std::string>& args);
    int32_t moneyAddress();

    // Saves: slot 1..; SaveData<NN>.sav in the save folder.
    bool save(int slot);
    bool load(int slot);
    std::string saveFolder() const { return saveFolder_; }

    void log(const std::string& message);
    // A summary of what is running, for diagnostics.
    std::string debugState();
    bool trace = false;          // log every command executed
    int traceFrom = 0;           // … from this frame on

private:
    friend struct MapScene;

    // ---- data helpers
    int dbInt(int db, int type, int record, int field);
    std::string dbString(int db, int type, int record, int field);
    void dbSetInt(int db, int type, int record, int field, int32_t value);
    void dbSetString(int db, int type, int record, int field, const std::string& value);
    DBType* dbType(int db, int type);
    DBRecord* dbRecord(int db, int type, int record, bool create);
    const DBField* dbField(int db, int type, int field);
    std::string sdbFile(int type, int record);
    int sysVar(int i) const { return i >= 0 && size_t(i) < sys_.size() ? sys_[size_t(i)] : 0; }

    // ---- interpreter (Interpreter.cpp)
    void runContext(Context& ctx);
    bool step(Context& ctx);   // false: wait/yield
    void callCommon(Context& ctx, int commonId, const Command* call, int32_t returnTo, const std::vector<int32_t>& numArgs,
                    const std::vector<std::string>& strArgs, bool hasStrArgs);
    void callMapEventPage(Context& ctx, int eventId, int page);
    void startCommonContext(int commonId, Context::Kind kind);
    int resolveCommonId(int32_t id, const std::string& name, const Frame& frame);
    int32_t value(int32_t v, const Frame& f) { return getValue(v, &f); }
    std::string expandText(const std::string& text, const Frame* frame, int depth = 0);
    void execSetVariable(const Command& c, Frame& f);
    void execSetString(Context& ctx, const Command& c, Frame& f);
    void execSetVariablePlus(const Command& c, Frame& f);
    void execDatabase(const Command& c, Frame& f);
    bool execCondition(const Command& c, Frame& f);
    bool execStringCondition(const Command& c, Frame& f);
    void execPicture(const Command& c, Frame& f);
    void execEffect(const Command& c, Frame& f);
    void execSound(const Command& c, Frame& f);
    void execTransfer(const Command& c, Frame& f);
    void execParty(const Command& c, Frame& f);
    bool execKeyInput(Context& ctx, const Command& c, Frame& f, bool first);
    void execMoveRoute(Context& ctx, const Command& c, Frame& f);
    void skipToBranchEnd(Frame& f, size_t from);
    void skipToNextCase(Frame& f, int indent, int caseNumber);
    int32_t charInfo(int target, int info, const Frame* frame);
    Character* character(int target, const Frame* frame);

    // ---- map (Map.cpp)
    void loadMap(int mapId);
    void refreshPages();
    int activePage(const MapEvent& e, const Character& ch);
    void setupPage(Character& ch, const MapEvent& e, int page);
    void updateMap();
    void updateCharacter(Character& ch);
    bool canPass(const Character& ch, int dir, int fromPx, int fromPy, bool forEvent);
    bool tilePassable(int px, int py, int dir, bool entering);
    int tileTag(int x, int y, int layer);
    bool moveCharacter(Character& ch, int dir, bool turn = true);
    void startJump(Character& ch, int dx, int dy);
    void processRoute(Character& ch);
    void updateHeroInput();
    void checkTouch(int px, int py, bool heroMoved);
    void checkAction();
    void startMapEvent(int eventId, bool asMain);
    void drawMap();
    void drawCharacter(const Character& ch, double camX, double camY);
    void drawTiles(int layerMask, double camX, double camY, bool upper);
    void updateCamera();
    int stepFrames(const Character& ch) const;
    void setDirection(Character& ch, int dir);
    std::pair<int, int> dirDelta(int dir) const;
    Character* eventChar(int id);

    // ---- pictures, messages, screen (Picture.cpp, Message.cpp)
    void updatePictures();
    void drawPictures(bool belowMessage);
    void drawPicture(Picture& p);
    TexturePtr renderRichText(const std::string& text, int maxChars, int& w, int& h, bool picture, int baseSize,
                              const Picture* pic = nullptr);
    TexturePtr loadImage(const std::string& path);
    TexturePtr windowTexture(const std::string& file, int w, int h);
    TexturePtr squareTexture(const std::string& file, int w, int h);  // WOLF 3's "<SQUARE>" pictures
    int pictureAt(int x, int y);  // the topmost picture with a visible pixel there, or -1
    void showMessage(const std::string& text, Context& ctx);
    void showChoices(const Command& c, Context& ctx);
    void updateMessage();
    void drawMessage();
    void updateScreenEffects();
    void drawScreenEffects();
    void drawMapTone();

    // ---- audio
    void playSound(Channel ch, int id, const std::string& file, int volume, int pitch, int startMs, int loopMs, int fade);
    void stopSound(Channel ch, int fade);

    // ---- saves (Save.cpp)
    std::vector<uint8_t> serialize();
    void captureState(SaveState& s);
    std::vector<uint8_t> encodeState(const SaveState& s);
    bool decodeState(const std::vector<uint8_t>& data, SaveState& s);
    void applyState(SaveState& s);
    bool stateValue(SaveState& s, int32_t address, int32_t* number, std::string* text, bool write);
    bool readSave(int slot, std::vector<uint8_t>& data) const;
    std::string savePath(int slot) const;
    std::vector<int32_t>& spare(int set);

    // ---- frame logic
    void updateEvents();
    void updateCommonTriggers();
    bool commonCondition(const CommonEvent& c);
    bool mainEventRunning() const;
    void initSystemValues();
    void returnToTitle();

    std::unique_ptr<Project> project_;
    Gfx& gfx_;
    Audio& audio_;
    std::string saveFolder_;
    HostCallbacks host_;

    int screenW_ = 640, screenH_ = 480, tileSize_ = 16, fps_ = 60;
    int charDirs_ = 4, charPatterns_ = 3;
    bool quit_ = false;
    std::mt19937 rng_;

    // Variables
    std::vector<int32_t> vars_;                       // V[n]
    std::array<std::vector<int32_t>, 10> spare_;      // spare variable sets 1-9 (index 0 unused)
    std::vector<std::string> strs_;                   // S[n]
    std::vector<int32_t> sys_;                        // Sys[n]
    std::vector<std::string> sysStr_;                 // SysS[n]
    std::map<int, std::array<int32_t, 100>> commonSelf_;     // persistent common self variables
    std::map<int, std::array<std::string, 5>> commonSelfStr_;
    std::map<int, std::map<int, std::array<int, 10>>> mapSelf_;  // [map][event] self vars

    // Map
    int mapId_ = -1;
    std::shared_ptr<const Map> mapData_;
    Map map_;                                         // the current map, with overwritten chips
    const TileSet* tileset_ = nullptr;
    std::vector<int32_t> passageOverride_;
    TexturePtr baseTiles_;
    std::vector<TexturePtr> autoTiles_;
    std::vector<Character> events_;                   // map events by index
    std::unordered_map<int, size_t> eventIndex_;      // event ID -> index
    Character hero_;
    std::vector<Character> party_;                    // followers
    std::vector<std::string> partyGraphics_;
    bool partyVisible_ = true;
    bool heroVisible_ = true;
    double camX_ = 0, camY_ = 0;
    int pendingMap_ = -1, pendingX = 0, pendingY = 0, pendingDir = 0;
    bool pendingTransfer_ = false;
    int transferFade_ = 0;
    bool moveDuringEvents_ = false;
    bool needRefresh_ = true;
    TexturePtr panorama_, fog_;
    std::vector<std::pair<int, int>> touchedThisFrame_;

    // Events
    std::vector<std::unique_ptr<Context>> contexts_;  // running main and parallel events
    std::map<int, std::unique_ptr<Context>> commonContexts_;    // parallel commons by ID
    std::map<int, std::unique_ptr<Context>> mapParallel_;       // parallel map events by ID
    std::vector<int> reservedCommons_;                // "Reserve common event"
    bool autoCommonRunning_ = false;
    int frameCount_ = 0;
    uint64_t playFrames_ = 0;

    // Display
    std::array<Picture, 1> pictureDummy_;
    std::map<int, Picture> pictures_;
    MessageWindow msg_;
    ScreenEffects fx_;
    AudioState audioState_;
    InputState input_, prevInput_;
    int repeatCounter_[KeyCount] = {};
    int inputBanned_[KeyCount] = {};  // 0 allowed, 1 not for walking, 2 not at all
    bool pictureOnly_ = false;                        // "Stop non-picture updates"
    std::map<std::string, TexturePtr> imageCache_;
    std::vector<std::string> debugLines_;
    std::string savedPositionDummy_;
    bool started_ = false;
    int titleMap_ = 0;
    int loadRequest_ = -1;
    bool titleRequest_ = false;

    bool pressed(int key) const { return input_.down[key] && !prevInput_.down[key]; }
    bool repeated(int key) const;
    // The engine's own use of a key (messages, choices) unless "basic key input control" denies it.
    bool systemPressed(int key) const { return inputBanned_[key] < 2 && pressed(key); }
    bool systemRepeated(int key) const { return inputBanned_[key] < 2 && repeated(key); }
};

}  // namespace wolf
