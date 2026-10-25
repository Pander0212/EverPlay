#include "Archive.hpp"

namespace wolf {

std::unique_ptr<Archive> Archive::open(const std::string& path, std::string& error) {
    (void)path;
    error = "archives are not supported yet";
    return nullptr;
}

}  // namespace wolf
