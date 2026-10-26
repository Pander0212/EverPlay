// DXArchive (.wolf) reading: WOLF RPG Editor packs Data/<Folder> into Data/<Folder>.wolf with
// DxLib's archiver, XOR-encrypted with a key that differs per editor version.
#pragma once

#include <memory>
#include <string>
#include <vector>

#include "WolfData.hpp"

namespace wolf {

class Archive {
public:
    struct Entry {
        std::string path;  // inside the archive, '/'-separated, as stored
        uint64_t offset = 0;
        uint64_t size = 0;       // uncompressed size
        uint64_t packedSize = 0; // compressed size (== size if stored)
        bool compressed = false;
        bool huffman = false;
    };

    // Opens an archive file; nullptr and `error` set if it cannot be read with any known key.
    // `proKeyFile`: the contents of a WOLF RPG Editor Pro game's key file (Data/Game.wolf, List.wolf, …),
    // from which the key of its archives is derived.
    static std::unique_ptr<Archive> open(const std::string& path, std::string& error, const Bytes* proKeyFile = nullptr);
    // The names a Pro game gives its key file, below Data (lowercase).
    static const std::vector<std::string>& proKeyFileNames();
    // The extensions WOLF games use for archives (lowercase, with the dot).
    static const std::vector<std::string>& extensions();
    virtual ~Archive() = default;
    const std::vector<Entry>& entries() const { return entries_; }
    virtual Bytes read(size_t entry) const = 0;

protected:
    std::vector<Entry> entries_;
};

}  // namespace wolf
