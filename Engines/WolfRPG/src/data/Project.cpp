#include "Project.hpp"

namespace wolf {

namespace {

Bytes need(const Vfs& vfs, const std::string& path) {
    auto b = vfs.read(path);
    if (!b) throw DataError("missing " + path);
    return std::move(*b);
}

}  // namespace

Project::Project(const std::string& gameFolder) : vfs(gameFolder) {
    for (auto& p : vfs.problems()) warnings.push_back(p);
    game = parseGameDat(need(vfs, "Data/BasicData/Game.dat"));
    const char* names[3] = {"DataBase", "CDataBase", "SysDatabase"};
    Database* dbs[3] = {&udb, &cdb, &sdb};
    for (int i = 0; i < 3; i++) {
        std::string base = std::string("Data/BasicData/") + names[i];
        *dbs[i] = parseDatabase(need(vfs, base + ".project"), need(vfs, base + ".dat"));
    }
    commons = parseCommonEvents(need(vfs, "Data/BasicData/CommonEvent.dat"));
    tilesets = parseTileSets(need(vfs, "Data/BasicData/TileSetData.dat"));
}

std::string Project::mapFile(int id) const {
    if (sdb.types.empty() || id < 0 || size_t(id) >= sdb.types[0].records.size()) return {};
    const DBRecord& r = sdb.types[0].records[size_t(id)];
    // System DB type 0 (マップ設定): the first string field is the map file.
    for (const auto& f : sdb.types[0].fields)
        if (f.isString && size_t(f.index) < r.strings.size()) return r.strings[size_t(f.index)];
    return {};
}

int Project::mapCount() const { return sdb.types.empty() ? 0 : int(sdb.types[0].records.size()); }

std::shared_ptr<const Map> Project::map(int id) {
    auto it = maps_.find(id);
    if (it != maps_.end()) return it->second;
    std::string file = mapFile(id);
    std::shared_ptr<const Map> m;
    if (!file.empty()) {
        auto data = vfs.read("Data/" + file);
        if (!data) data = vfs.read(file);
        if (data) {
            try {
                m = std::make_shared<Map>(parseMap(std::move(*data)));
            } catch (const std::exception& e) {
                warnings.push_back("map " + file + ": " + e.what());
            }
        } else {
            warnings.push_back("missing map " + file);
        }
    }
    maps_[id] = m;
    return m;
}

}  // namespace wolf
