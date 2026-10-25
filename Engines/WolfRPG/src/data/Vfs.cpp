#include "Vfs.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <dirent.h>
#include <sys/stat.h>

#include "Archive.hpp"

namespace wolf {

namespace {

bool readFile(const std::string& path, Bytes& out) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    std::fseek(f, 0, SEEK_END);
    long size = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    out.resize(size > 0 ? size_t(size) : 0);
    size_t n = out.empty() ? 0 : std::fread(out.data(), 1, out.size(), f);
    std::fclose(f);
    return n == out.size();
}

bool isDir(const std::string& path) {
    struct stat st{};
    return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

}  // namespace

std::string Vfs::normalize(const std::string& path) {
    std::string out;
    out.reserve(path.size());
    for (char c : path) {
        if (c == '\\') c = '/';
        if (c == '/' && (out.empty() || out.back() == '/')) continue;
        out.push_back(char(std::tolower(static_cast<unsigned char>(c))));
    }
    while (!out.empty() && out.back() == '/') out.pop_back();
    // "./" prefixes
    while (out.rfind("./", 0) == 0) out.erase(0, 2);
    return out;
}

Vfs::Vfs(std::string gameFolder) : root_(std::move(gameFolder)) {
    while (root_.size() > 1 && root_.back() == '/') root_.pop_back();
    scan(root_, "");
    mountArchives();
}

Vfs::~Vfs() = default;

void Vfs::scan(const std::string& dir, const std::string& rel) {
    DIR* d = opendir(dir.c_str());
    if (!d) return;
    while (dirent* e = readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..") continue;
        std::string full = dir + "/" + name;
        std::string r = rel.empty() ? name : rel + "/" + name;
        if (isDir(full)) {
            if (rel.empty() && (name == "Save" || name == "save")) {
                // Saves are handled by the save manager, not as game data.
            }
            scan(full, r);
        } else {
            files_[normalize(r)] = r;
        }
    }
    closedir(d);
}

void Vfs::mountArchives() {
    // Data.wolf holds the whole Data folder; Data/<Name>.wolf holds Data/<Name>.
    std::vector<std::pair<std::string, std::string>> found;  // archive rel path, mount prefix
    for (auto& [norm, real] : files_) {
        if (norm.size() < 5 || norm.compare(norm.size() - 5, 5, ".wolf") != 0) continue;
        std::string base = norm.substr(0, norm.size() - 5);
        if (base == "data") found.push_back({real, "data"});
        else if (base.rfind("data/", 0) == 0 && base.find('/', 5) == std::string::npos) found.push_back({real, base});
    }
    for (auto& [rel, prefix] : found) {
        std::string error;
        auto archive = Archive::open(root_ + "/" + rel, error);
        if (!archive) {
            problems_.push_back(rel + ": " + error);
            continue;
        }
        size_t index = archives_.size();
        const auto& entries = archive->entries();
        for (size_t i = 0; i < entries.size(); i++) {
            std::string p = prefix + "/" + normalize(entries[i].path);
            // Loose files win: a translation patch replaces files of the archive.
            if (!files_.count(p) && !packed_.count(p)) packed_[p] = {index, i};
        }
        archives_.push_back(std::move(archive));
    }
}

std::optional<Bytes> Vfs::read(const std::string& path) const {
    std::string n = normalize(path);
    auto it = files_.find(n);
    if (it != files_.end()) {
        Bytes b;
        if (readFile(root_ + "/" + it->second, b)) return b;
    }
    auto p = packed_.find(n);
    if (p != packed_.end()) {
        try {
            return archives_[p->second.archive]->read(p->second.entry);
        } catch (const std::exception&) {
            return std::nullopt;
        }
    }
    return std::nullopt;
}

bool Vfs::exists(const std::string& path) const {
    std::string n = normalize(path);
    return files_.count(n) || packed_.count(n);
}

std::string Vfs::realPath(const std::string& path) const {
    auto it = files_.find(normalize(path));
    return it == files_.end() ? std::string() : root_ + "/" + it->second;
}

std::vector<std::string> Vfs::list(const std::string& folder) const {
    std::string prefix = normalize(folder) + "/";
    std::vector<std::string> out;
    for (auto& [n, real] : files_)
        if (n.rfind(prefix, 0) == 0) out.push_back(real);
    for (auto& [n, p] : packed_)
        if (n.rfind(prefix, 0) == 0 && !files_.count(n)) out.push_back(n);
    std::sort(out.begin(), out.end());
    return out;
}

}  // namespace wolf
