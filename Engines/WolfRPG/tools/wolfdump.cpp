// Prints a summary of a WOLF RPG game's data (for development; never ships).
//   wolfdump <game folder> [summary|commands|map <id>|common <id>|db <u|c|s> <type>]
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

#include "../src/data/Project.hpp"

using namespace wolf;

static void printCommands(const CommandList& list) {
    for (const auto& c : list) {
        std::printf("%*s%d", c.indent * 2, "", c.code);
        for (auto a : c.args) std::printf(" %d", a);
        for (auto& s : c.strings) std::printf(" \"%s\"", s.c_str());
        if (c.route) std::printf(" [route %zu]", c.route->commands.size());
        std::printf("\n");
    }
}

int main(int argc, char** argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: wolfdump <game> [mode]\n"); return 2; }
    try {
        Project p(argv[1]);
        std::string mode = argc > 2 ? argv[2] : "summary";
        if (mode == "summary") {
            std::printf("title: %s  utf8:%d  font:%s\n", p.game.title().c_str(), p.game.utf8, p.game.font().c_str());
            std::printf("u8:");
            for (auto b : p.game.u8) std::printf(" %d", b);
            std::printf("\nu16:");
            for (auto b : p.game.u16) std::printf(" %d", b);
            std::printf("\nstrings:");
            for (auto& s : p.game.strings) std::printf(" [%s]", s.c_str());
            std::printf("\nUDB %zu types, CDB %zu, SDB %zu, commons %zu, tilesets %zu, maps %d\n", p.udb.types.size(),
                        p.cdb.types.size(), p.sdb.types.size(), p.commons.size(), p.tilesets.size(), p.mapCount());
            int ok = 0, bad = 0;
            for (int i = 0; i < p.mapCount(); i++) {
                if (p.mapFile(i).empty()) continue;
                if (p.map(i)) ok++; else bad++;
            }
            std::printf("maps parsed: %d ok, %d failed\n", ok, bad);
            for (auto& w : p.warnings) std::printf("warning: %s\n", w.c_str());
        } else if (mode == "commands") {
            std::map<int, int> counts;
            for (auto& c : p.commons) for (auto& cmd : c.commands) counts[cmd.code]++;
            for (int i = 0; i < p.mapCount(); i++)
                if (auto m = p.map(i))
                    for (auto& e : m->events) for (auto& pg : e.pages) for (auto& cmd : pg.commands) counts[cmd.code]++;
            for (auto& [code, n] : counts) std::printf("%4d %d\n", code, n);
        } else if (mode == "map" && argc > 3) {
            auto m = p.map(std::atoi(argv[3]));
            if (!m) { std::printf("no map\n"); return 1; }
            std::printf("map %s %dx%d tileset %d layers %d events %zu version %x\n", p.mapFile(std::atoi(argv[3])).c_str(),
                        m->width, m->height, m->tileset, m->layers, m->events.size(), m->version);
            for (auto& e : m->events) {
                std::printf("event %d '%s' at %d,%d pages %zu\n", e.id, e.name.c_str(), e.x, e.y, e.pages.size());
                for (auto& pg : e.pages) {
                    std::printf(" page trig %d gfx '%s' tile %d dir %d move %d/%d/%d/%d opt %02x\n", pg.trigger,
                                pg.graphic.c_str(), pg.tileId, pg.direction, pg.moveType, pg.moveSpeed, pg.moveFrequency,
                                pg.animSpeed, pg.options);
                    if (argc > 4) printCommands(pg.commands);
                }
            }
        } else if (mode == "common" && argc > 3) {
            auto& c = p.commons.at(std::atoi(argv[3]));
            std::printf("common %d '%s' trigger %d op %x %d %d args %d/%d ret %d\n", c.id, c.name.c_str(), c.trigger, c.op,
                        c.left, c.right, c.numArgs, c.strArgs, c.returnVar);
            printCommands(c.commands);
        } else if (mode == "allcommons") {
            for (auto& c : p.commons) {
                std::printf("common %d '%s' trigger %d args %d/%d ret %d\n", c.id, c.name.c_str(), c.trigger, c.numArgs,
                            c.strArgs, c.returnVar);
                printCommands(c.commands);
            }
        } else if (mode == "allmaps") {
            for (int i = 0; i < p.mapCount(); i++) {
                auto m = p.map(i);
                if (!m) continue;
                for (auto& e : m->events)
                    for (size_t pi = 0; pi < e.pages.size(); pi++) {
                        std::printf("map %d event %d '%s' page %zu\n", i, e.id, e.name.c_str(), pi);
                        printCommands(e.pages[pi].commands);
                    }
            }
        } else if (mode == "commons") {
            for (auto& c : p.commons)
                if (!c.name.empty() || !c.commands.empty())
                    std::printf("%4d trig %d %-40s %zu cmds\n", c.id, c.trigger, c.name.c_str(), c.commands.size());
        } else if (mode == "db" && argc > 3) {
            const Database& db = argv[3][0] == 'u' ? p.udb : argv[3][0] == 'c' ? p.cdb : p.sdb;
            if (argc == 4) {
                for (size_t i = 0; i < db.types.size(); i++)
                    std::printf("%zu %s (%zu fields, %zu records)\n", i, db.types[i].name.c_str(), db.types[i].fields.size(),
                                db.types[i].records.size());
            } else {
                auto& t = db.types.at(std::atoi(argv[4]));
                for (size_t ri = 0; ri < t.records.size(); ri++) {
                    auto& r = t.records[ri];
                    std::printf("[%zu] %s:", ri, r.name.c_str());
                    for (auto& f : t.fields) {
                        if (f.isString) std::printf(" %s=\"%s\"", f.name.c_str(), size_t(f.index) < r.strings.size() ? r.strings[f.index].c_str() : "?");
                        else std::printf(" %s=%d", f.name.c_str(), size_t(f.index) < r.ints.size() ? r.ints[f.index] : 0);
                    }
                    std::printf("\n");
                }
            }
        } else if (mode == "tilesets") {
            for (auto& t : p.tilesets) {
                std::printf("'%s' base '%s' tags %zu passage %zu\n", t.name.c_str(), t.baseFile.c_str(), t.tags.size(), t.passage.size());
                for (auto& a : t.autotileFiles) if (!a.empty()) std::printf("   auto %s\n", a.c_str());
            }
        }
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
    return 0;
}
