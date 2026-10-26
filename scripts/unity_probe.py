#!/usr/bin/env python3
"""What a Unity Windows game is made of, for docs/UNITY.md: Unity version, Mono or IL2CPP, which GPU APIs its
shaders were compiled for, and native plugins. Reads file names and data headers only; nothing of the game runs.

    python3 -I scripts/unity_probe.py path/to/GameFolder

The shader count needs UnityPy (pip install UnityPy); without it the rest is still printed.
"""
import pathlib
import re
import sys

VERSION = re.compile(rb"(\d{4}\.\d+\.\d+[abfpx]\d+)")
# Unity's ShaderCompilerPlatform values as stored in a Shader's "platforms" list.
GPU = {4: "D3D11", 5: "GLES20", 9: "GLES3x", 14: "Metal", 15: "OpenGLCore", 18: "Vulkan", 25: "D3D12"}


def data_folder(game):
    folders = [p for p in game.rglob("*_Data") if p.is_dir()]
    return min(folders, key=lambda p: len(p.parts)) if folders else None


def unity_version(data):
    for name in ("globalgamemanagers", "mainData", "data.unity3d"):
        path = data / name
        if path.is_file():
            match = VERSION.search(path.open("rb").read(4096))
            if match:
                return match.group(1).decode()
    return None


def shader_platforms(data):
    try:
        import UnityPy
    except ImportError:
        return "UnityPy not installed"
    files = [str(p) for p in data.iterdir() if p.is_file() and
             (p.name == "globalgamemanagers" or p.suffix == ".assets" or p.name.startswith("level"))]
    counts = {}
    for obj in UnityPy.load(*files).objects:
        if obj.type.name != "Shader":
            continue
        try:
            for platform in obj.read_typetree().get("platforms", []):
                key = GPU.get(platform, str(platform))
                counts[key] = counts.get(key, 0) + 1
        except Exception as error:  # a layout UnityPy does not know
            counts["unreadable"] = counts.get("unreadable", 0) + 1
    return counts


def main():
    game = pathlib.Path(sys.argv[1])
    data = data_folder(game)
    if not data:
        sys.exit("No <Name>_Data folder found.")
    root = data.parent
    if (data / "Managed" / "Assembly-CSharp.dll").is_file() or (root / "MonoBleedingEdge").is_dir():
        backend = "Mono"
    elif (root / "GameAssembly.dll").is_file() or (data / "il2cpp_data" / "Metadata" / "global-metadata.dat").is_file():
        backend = "IL2CPP"
    else:
        backend = "unknown"
    plugins = sorted(p.relative_to(data).as_posix() for p in (data / "Plugins").rglob("*.dll")) if (data / "Plugins").is_dir() else []
    print("game:", data.name[:-5])
    print("unity:", unity_version(data) or "unknown")
    print("backend:", backend)
    print("native plugins:", ", ".join(plugins) or "none")
    print("shader GPU programs:", shader_platforms(data))


if __name__ == "__main__":
    main()
