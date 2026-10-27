#!/usr/bin/env python3
"""Packs a folder of Godot project files (text scenes and scripts) into a .pck as the given Godot
version writes it, without a Godot editor; usage: make-pck.py <folder> <out.pck> [engine version].
Godot 3: pack format 1; 4.0-4.4: format 2; 4.5+: format 3. With --embed <exe>, appends the pack to
a copy of an executable instead (Godot's "embed pck"). For EverPlay's own test games
(Tests/Fixtures/GodotProbe, GodotProbe3)."""
import hashlib
import pathlib
import struct
import sys

args = sys.argv[1:]
embed = None
if '--embed' in args:
    index = args.index('--embed')
    embed = pathlib.Path(args[index + 1])
    del args[index:index + 2]
folder, out = pathlib.Path(args[0]), pathlib.Path(args[1])
major, minor, patch = (int(part) for part in (args[2] if len(args) > 2 else '4.5.0').split('.'))
pack_format = 1 if major == 3 else 2 if minor <= 4 else 3

files = sorted(p for p in folder.rglob('*') if p.is_file() and not p.name.startswith('.'))
PACK_REL_FILEBASE = 2


def align(value, to=16):
    return (value + to - 1) // to * to


def directory(entries, base):
    """count, then per file: path length, path, offset (from `base`), size, md5 (format 2+: flags)."""
    out = struct.pack('<I', len(entries))
    for name, offset, content in entries:
        # Godot 3 names files with res://; 4.x without.
        encoded = (('res://' + name) if pack_format == 1 else name).encode('utf-8')
        out += struct.pack('<I', len(encoded)) + encoded
        out += struct.pack('<QQ', base + offset, len(content)) + hashlib.md5(content).digest()
        if pack_format >= 2:
            out += struct.pack('<I', 0)
    return out


# Godot 3 reads embedded packs' offsets from the start of the whole .exe.
exe = bytearray(embed.read_bytes()) if embed else bytearray()
exe += b'\0' * (align(len(exe)) - len(exe))
prefix = len(exe) if pack_format == 1 else 0

data = bytearray()
entries = []
for path in files:
    content = path.read_bytes()
    entries.append((path.relative_to(folder).as_posix(), len(data), content))
    data += content
    data += b'\0' * (align(len(data)) - len(data))

pack = bytearray(b'GDPC') + struct.pack('<IIII', pack_format, major, minor, patch)
if pack_format == 3:
    # flags, file base, directory offset, reserved; files; directory (offsets relative to the base).
    header = len(pack) + 4 + 8 + 8 + 16 * 4
    file_base = align(header)
    pack += struct.pack('<IQQ', PACK_REL_FILEBASE, file_base, file_base + len(data)) + b'\0' * (16 * 4)
    pack += b'\0' * (file_base - len(pack)) + data + directory(entries, 0)
else:
    # Format 1 (Godot 3): reserved, directory, files; offsets from the pack's start (the .exe's if embedded).
    # Format 2 (4.0-4.4): flags, file base, reserved, directory, files; offsets from the base.
    header = len(pack) + (4 + 8 if pack_format == 2 else 0) + 16 * 4
    size = len(directory(entries, 0))
    file_base = align(header + size)
    if pack_format == 2:
        pack += struct.pack('<IQ', PACK_REL_FILEBASE, file_base)
    pack += b'\0' * (16 * 4)
    pack += directory(entries, file_base + prefix if pack_format == 1 else 0)
    pack += b'\0' * (file_base - len(pack)) + data

if embed:
    out.write_bytes(bytes(exe) + bytes(pack) + struct.pack('<Q', len(pack)) + b'GDPC')
else:
    out.write_bytes(bytes(pack))
print(f'{out}: {len(entries)} files, Godot {major}.{minor}.{patch} pack format {pack_format}')
