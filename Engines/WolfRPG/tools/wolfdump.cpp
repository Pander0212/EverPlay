// Prints a summary of a WOLF RPG game's data (for development; never ships).
//   wolfdump <game folder> [summary|commands|map <id>|common <id>|db <u|c|s> <type>]
//   wolfdump --archive <file.wolf> [output folder]   lists (and extracts) a .wolf archive
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

#include <filesystem>
#include <fstream>

#include "../src/data/Archive.hpp"
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
    if (std::strcmp(argv[1], "--archive") == 0 && argc > 2) {
        std::string error;
        auto archive = Archive::open(argv[2], error);
        if (!archive) { std::fprintf(stderr, "%s: %s\n", argv[2], error.c_str()); return 1; }
        int failed = 0;
        for (size_t i = 0; i < archive->entries().size(); i++) {
            const auto& e = archive->entries()[i];
            Bytes data = archive->read(i);
            bool ok = data.size() == e.size || (e.size >= 62 && data.size() == e.size - 62);
            if (!ok) failed++;
            std::printf("%s %10llu %s%s%s\n", ok ? "ok  " : "FAIL", (unsigned long long)e.size, e.path.c_str(),
                        e.compressed ? " [lz]" : "", e.huffman ? " [huffman]" : "");
            if (argc > 3 && ok) {
                std::filesystem::path out = std::filesystem::path(argv[3]) / e.path;
                std::filesystem::create_directories(out.parent_path());
                std::ofstream(out, std::ios::binary).write(reinterpret_cast<const char*>(data.data()), std::streamsize(data.size()));
            }
        }
        std::printf("%zu entries, %d failed\n", archive->entries().size(), failed);
        return failed ? 1 : 0;
    }
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
            for (int l = 0; l < m->layers; l++) {
                std::printf("layer %d row 0-1:", l);
                for (int y = 0; y < 2 && y < m->height; y++)
                    for (int x = 0; x < 8 && x < m->width; x++) std::printf(" %d", m->tile(l, x, y));
                std::printf("\n");
            }
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
        } else if (mode == "tiles" && argc > 3) {  // every tile of a map: layer x y chip
            auto m = p.map(std::atoi(argv[3]));
            if (!m) return 1;
            std::printf("size %d %d tileset %d\n", m->width, m->height, m->tileset);
            for (int l = 0; l < m->layers; l++)
                for (int y = 0; y < m->height; y++)
                    for (int x = 0; x < m->width; x++) std::printf("%d %d %d %d\n", l, x, y, m->tile(l, x, y));
        } else if (mode == "tilestats") {
            for (int i = 0; i < p.mapCount(); i++) {
                auto m = p.map(i);
                if (!m) continue;
                std::printf("map %d ts %d:", i, m->tileset);
                for (int l = 0; l < m->layers; l++) {
                    int zero = 0, raw = 0, conn = 0, n = m->width * m->height;
                    for (int x = 0; x < m->width; x++)
                        for (int y = 0; y < m->height; y++) {
                            int v = m->tile(l, x, y);
                            if (v == 0) zero++;
                            else if (v >= 100000 && v % 100000 == 0) raw++;
                            else if (v >= 100000) conn++;
                        }
                    std::printf(" L%d n%d zero%d raw%d conn%d", l, n, zero, raw, conn);
                }
                std::printf("\n");
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
                    std::printf("%4d trig %d op %02x %d %d %-40s %zu cmds\n", c.id, c.trigger, c.op, c.left, c.right,
                                c.name.c_str(), c.commands.size());
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
                for (size_t i = 0; i < t.autotileFiles.size(); i++) std::printf("   auto %zu %s\n", i, t.autotileFiles[i].c_str());
            }
        }
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
    return 0;
}
