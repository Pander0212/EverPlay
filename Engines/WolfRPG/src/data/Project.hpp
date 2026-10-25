// All of a game's data, loaded from its folder.
#pragma once

#include <map>
#include <memory>
#include <string>

#include "Vfs.hpp"
#include "WolfData.hpp"

namespace wolf {

struct Project {
    explicit Project(const std::string& gameFolder);

    Vfs vfs;
    GameDat game;
    Database udb, cdb, sdb;  // user, changeable and system databases
    std::vector<CommonEvent> commons;
    std::vector<TileSet> tilesets;

    // The map with this ID (System DB type 0), parsed on first use; nullptr if missing.
    std::shared_ptr<const Map> map(int id);
    std::string mapFile(int id) const;
    int mapCount() const;

    // Database access by type and record; field values as numbers or strings.
    const Database& db(int which) const { return which == 0 ? udb : which == 1 ? cdb : sdb; }

    std::vector<std::string> warnings;

private:
    std::map<int, std::shared_ptr<const Map>> maps_;
};

}  // namespace wolf
