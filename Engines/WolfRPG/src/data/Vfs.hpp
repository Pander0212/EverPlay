// The game's files: the loose Data folder and the packed .wolf archives next to it.
// Paths are relative to the game folder ("Data/BasicData/Game.dat"), use '/' and are matched
// without regard to case, as on Windows.
#pragma once

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "WolfData.hpp"

namespace wolf {

class Archive;

class Vfs {
public:
    explicit Vfs(std::string gameFolder);
    ~Vfs();
    const std::string& root() const { return root_; }

    // The contents of a game file, from the folder or else from an archive.
    std::optional<Bytes> read(const std::string& path) const;
    bool exists(const std::string& path) const;
    // The real path on disk of a loose file (empty if it is only in an archive or missing).
    std::string realPath(const std::string& path) const;
    // Files below a folder ("Data/MapData"), by their relative paths.
    std::vector<std::string> list(const std::string& folder) const;

    // Archive mounts that failed (missing key, unknown format), for the log.
    const std::vector<std::string>& problems() const { return problems_; }

    static std::string normalize(const std::string& path);

private:
    void scan(const std::string& dir, const std::string& rel);
    void mountArchives();

    std::string root_;
    // normalized relative path -> real relative path, for loose files
    std::map<std::string, std::string> files_;
    // normalized relative path -> archive index and entry
    struct Packed { size_t archive; size_t entry; };
    std::map<std::string, Packed> packed_;
    std::vector<std::unique_ptr<Archive>> archives_;
    std::vector<std::string> problems_;
};

}  // namespace wolf
