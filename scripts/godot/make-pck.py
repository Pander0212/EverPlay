#!/usr/bin/env python3
"""Packs a folder of Godot project files (text scenes and scripts) into a .pck as Godot 4.5+
writes it (format 3), without a Godot editor; usage: make-pck.py <folder> <out.pck> [engine version].
With --embed <exe>, appends the pack to a copy of an executable instead (Godot's "embed pck").
For EverPlay's own test game (Tests/Fixtures/GodotProbe)."""
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

files = sorted(p for p in folder.rglob('*') if p.is_file() and not p.name.startswith('.'))
HEADER = 4 + 4 * 4 + 4 + 8 + 8 + 16 * 4  # magic, format, version, flags, file base, directory offset, reserved


def align(value, to=16):
    return (value + to - 1) // to * to


data = bytearray()
entries = []
for path in files:
    content = path.read_bytes()
    entries.append((path.relative_to(folder).as_posix(), len(data), content))
    data += content
    data += b'\0' * (align(len(data)) - len(data))

file_base = align(HEADER)
directory_offset = file_base + len(data)
directory = struct.pack('<I', len(entries))
for name, offset, content in entries:
    encoded = name.encode('utf-8')
    directory += struct.pack('<I', len(encoded)) + encoded
    directory += struct.pack('<QQ', offset, len(content)) + hashlib.md5(content).digest() + struct.pack('<I', 0)

PACK_REL_FILEBASE = 2
pack = bytearray(b'GDPC')
pack += struct.pack('<IIII', 3, major, minor, patch)
pack += struct.pack('<IQQ', PACK_REL_FILEBASE, file_base, directory_offset)
pack += b'\0' * (16 * 4)
pack += b'\0' * (file_base - len(pack))
pack += data + directory

if embed:
    exe = bytearray(embed.read_bytes())
    exe += b'\0' * (align(len(exe)) - len(exe))
    out.write_bytes(bytes(exe) + bytes(pack) + struct.pack('<Q', len(pack)) + b'GDPC')
else:
    out.write_bytes(bytes(pack))
print(f'{out}: {len(entries)} files, Godot {major}.{minor}.{patch} pack format 3')
