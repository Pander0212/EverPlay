// Cheats for EverPlay's cheat screen (App/Views/CheatsView.swift): the same methods and JSON
// replies as RPG Maker games where WOLF has an equivalent. Switches and items are not WOLF
// concepts; variables are the normal variables with their names from the system database.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>

#include "Game.hpp"

namespace wolf {

namespace {

std::string jsonString(const std::string& s) {
    std::string out = "\"";
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof buf, "\\u%04x", c);
                    out += buf;
                } else {
                    out += char(c);
                }
        }
    }
    return out + "\"";
}

std::string lower(std::string s) {
    for (auto& c : s) c = char(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

}  // namespace

// Money of the Basic System: a variable or database field named like it, if the game has one.
int32_t Game::moneyAddress() {
    static const char* names[] = {"所持金", "お金", "money", "gold"};
    DBType* vars = dbType(2, 14);
    if (vars)
        for (size_t i = 0; i < vars->records.size(); i++) {
            std::string n = lower(vars->records[i].name);
            for (const char* want : names)
                if (n.find(want) != std::string::npos) return int32_t(2000000 + i);
        }
    return 0;
}

std::string Game::cheat(const std::string& method, const std::vector<std::string>& args) {
    auto num = [&](size_t i) { return i < args.size() ? std::atof(args[i].c_str()) : 0.0; };
    auto flag = [&](size_t i) { return i < args.size() && (args[i] == "1" || args[i] == "true"); };
    if (method == "setSpeed") speed = std::clamp(int(num(0)), 1, 8);
    else if (method == "setThrough") cheatThrough = flag(0);
    else if (method == "addGold" || method == "setGold") {
        int32_t a = moneyAddress();
        if (a) setValue(a, int32_t(method == "addGold" ? getValue(a) + num(0) : num(0)));
    } else if (method == "setVariable") {
        int id = int(num(0));
        if (id >= 0) setValue(2000000 + id, int32_t(std::clamp(num(1), -999999999.0, 999999999.0)));
        return "true";
    } else if (method == "variables") {
        std::string query = lower(args.empty() ? std::string() : args[0]);
        std::string out = "[";
        bool first = true;
        DBType* names = dbType(2, 14);
        size_t count = std::max<size_t>(names ? names->records.size() : 0, 1);
        count = std::min(count, vars_.size());
        int shown = 0;
        for (size_t i = 0; i < count && shown < 500; i++) {
            std::string name = names && i < names->records.size() ? names->records[i].name : std::string();
            int32_t value = vars_[i];
            if (!query.empty()) {
                if (query[0] == '#') { if (std::to_string(i) != query.substr(1)) continue; }
                else if (query[0] == '=') { if (std::to_string(value) != query.substr(1)) continue; }
                else if (lower(name).find(query) == std::string::npos) continue;
            } else if (name.empty() && value == 0) {
                continue;
            }
            if (!first) out += ",";
            first = false;
            out += "{\"id\":" + std::to_string(i) + ",\"name\":" + jsonString(name) + ",\"value\":" + std::to_string(value) +
                   ",\"number\":true}";
            shown++;
        }
        return out + "]";
    } else if (method == "switches" || method == "items") {
        return "[]";
    } else if (method == "gainItem" || method == "setSwitch") {
        return "true";
    }
    // status (and the reply of every setter)
    int32_t money = moneyAddress();
    std::string out = "{\"engine\":\"wolf\",\"ready\":" + std::string(started_ ? "true" : "false");
    if (money) out += ",\"gold\":" + std::to_string(getValue(money)) + ",\"maxGold\":999999999";
    out += ",\"party\":[],\"speed\":" + std::to_string(speed) + ",\"through\":" + (cheatThrough ? "true" : "false") + "}";
    return out;
}

}  // namespace wolf
