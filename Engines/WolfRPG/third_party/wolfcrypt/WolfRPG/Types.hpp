// Minimal replacement for WolfTL's WolfRPG/Types.hpp: only what WolfCrypt needs.
#pragma once
#include <array>
#include <cstdint>
#include <vector>

using SeedIncides = std::array<uint8_t, 3>;

enum class WolfFileType
{
	GameDat,
	CommonEvent,
	DataBase,
	Project,
	Map,
	TileSetData,
	None
};
