cmake_minimum_required(VERSION 3.20)
project(WolfRPG C CXX)

# WOLF RPG Editor engine for EverPlay. On Linux this builds the data library, its tests and
# a headless runner; on iOS (scripts/build-wolfrpg-ios.sh) the WolfRPG framework.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(wolfdata STATIC
  src/data/WolfData.cpp
  src/data/Vfs.cpp
  src/data/Archive.cpp
  src/data/Project.cpp
  third_party/lz4/lz4.c)
target_include_directories(wolfdata PUBLIC src)
if(APPLE)
  target_link_libraries(wolfdata PUBLIC iconv)
endif()

add_library(wolfengine STATIC
  src/engine/Game.cpp
  src/engine/Interpreter.cpp
  src/engine/Map.cpp
  src/engine/Picture.cpp
  src/engine/Save.cpp
  src/engine/Cheats.cpp)
target_link_libraries(wolfengine PUBLIC wolfdata)

option(WOLF_TESTS "Build the tests" ON)
if(WOLF_TESTS)
  enable_testing()
  add_executable(wolftests tests/EngineTests.cpp)
  target_link_libraries(wolftests wolfengine)
  add_test(NAME wolftests COMMAND wolftests)
endif()

option(WOLF_SDL "Build the SDL platform layer" ON)
if(WOLF_SDL)
  # iOS: the static SDL2 and SDL2_ttf from scripts/build-wolfrpg-ios.sh; Linux: pkg-config.
  find_package(SDL2 CONFIG QUIET)
  find_package(SDL2_ttf CONFIG QUIET)
  if(TARGET SDL2::SDL2-static AND TARGET SDL2_ttf::SDL2_ttf-static)
    set(WOLF_SDL_LIBS SDL2::SDL2-static SDL2_ttf::SDL2_ttf-static)
  else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2 SDL2_ttf)
    set(WOLF_SDL_LIBS PkgConfig::SDL2)
  endif()
  add_library(wolfsdl STATIC
    src/platform/SdlGfx.cpp
    src/platform/SdlAudio.cpp
    src/platform/Runner.cpp)
  target_link_libraries(wolfsdl PUBLIC wolfengine ${WOLF_SDL_LIBS})
  # The single-header libraries warn a lot; they are not ours to fix.
  set_source_files_properties(src/platform/SdlAudio.cpp src/platform/SdlGfx.cpp src/platform/Runner.cpp
    PROPERTIES COMPILE_OPTIONS "-w")
endif()

option(WOLF_TOOLS "Build the development tools" ON)
if(WOLF_TOOLS)
  add_executable(wolfdump tools/wolfdump.cpp)
  target_link_libraries(wolfdump wolfdata)
  if(WOLF_SDL)
    add_executable(wolfrun tools/wolfrun.cpp)
    target_link_libraries(wolfrun wolfsdl)
  endif()
endif()
