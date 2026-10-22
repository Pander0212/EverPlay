#!/usr/bin/env python3
"""Attach an existing Ren'Py desktop game's data to a matching trusted web runtime.

ZIP operations only: nothing from the desktop package is executed, compiled,
imported or unpickled on the host. Game code first runs inside the WebAssembly
runtime. The runtime version must match the package exactly. Intended for
owner-supplied test packages; the output contains the game and must stay private.

    python3 -I scripts/assemble-renpy-desktop-data.py \
      --template artifacts/EverPlayRenPy820Template.zip --desktop game-pc.zip \
      --output App/Resources/EverPlayRenPyDesktopGame.zip
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

MAX_ENTRIES = 50_000
MAX_TOTAL_BYTES = 4 * 1024 ** 3
MAX_GAME_BYTES = 1536 * 1024 ** 2
# Desktop caches hold pickled bytecode; saves belong to the desktop install.
EXCLUDED_GAME_DIRS = {'cache', 'saves'}


def fail(message):
    raise SystemExit(f'Refusing package: {message}')


def checked_names(archive):
    infos = archive.infolist()
    if len(infos) > MAX_ENTRIES:
        fail('too many entries')
    if sum(info.file_size for info in infos) > MAX_TOTAL_BYTES:
        fail('declared uncompressed size too large')
    seen = set()
    for info in infos:
        name = info.filename
        path = PurePosixPath(name)
        if ('\\' in name or '\0' in name or '//' in name or name.startswith('/') or ':' in path.parts[0]
                or any(part in ('', '.', '..') for part in path.parts)):
            fail(f'unsafe path {name!r}')
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            fail(f'symbolic link {name!r}')
        if info.flag_bits & 0x1:
            fail('encrypted entries')
        if name.casefold() in seen:
            fail(f'duplicate path {name!r}')
        seen.add(name.casefold())
    return infos


def desktop_layout(archive):
    infos = checked_names(archive)
    versions = [info for info in infos if PurePosixPath(info.filename).parts[1:] == ('renpy', 'vc_version.py')]
    if len(versions) != 1:
        fail('expected exactly one <game>/renpy/vc_version.py')
    top = PurePosixPath(versions[0].filename).parts[0]
    if versions[0].file_size > 4096:
        fail('version marker too large')
    # Read the marker as text; it is never imported.
    match = re.search(r"^version = '([0-9.]+)'$", archive.read(versions[0]).decode('ascii', 'strict'), re.MULTILINE)
    if not match:
        fail('version marker unreadable')
    game = [info for info in infos if info.filename.startswith(f'{top}/game/') and not info.is_dir()]
    selected = [info for info in game
                if PurePosixPath(info.filename).parts[2] not in EXCLUDED_GAME_DIRS]
    if not any(info.filename == f'{top}/game/script_version.txt' for info in selected):
        fail('game/script_version.txt missing')
    if not any(info.filename.endswith(('.rpa', '.rpyc')) for info in selected):
        fail('no compiled game data (.rpa/.rpyc)')
    if sum(info.file_size for info in selected) > MAX_GAME_BYTES:
        fail('game data larger than the current in-memory web runtime limit')
    return top, match.group(1), selected, len(game) - len(selected)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--template', required=True, type=Path)
    parser.add_argument('--desktop', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()

    with zipfile.ZipFile(args.template) as template:
        release = re.search(r'RenPyWeb ([0-9.]+);', template.read('ENGINE-SOURCE.txt').decode())
        if not release:
            fail('template has no recorded runtime release')
        with zipfile.ZipFile(args.desktop) as desktop:
            top, version, selected, skipped = desktop_layout(desktop)
            if version != release.group(1):
                fail(f'package needs Ren\'Py {version}, template is {release.group(1)}')
            hashes = {}
            blob = io.BytesIO()
            with zipfile.ZipFile(io.BytesIO(template.read('game.zip'))) as engine, \
                    zipfile.ZipFile(blob, 'w', zipfile.ZIP_DEFLATED) as game:
                for info in engine.infolist():
                    if not info.filename.startswith('game/') and not info.is_dir():
                        game.writestr(info, engine.read(info))
                for info in selected:
                    name = info.filename[len(top) + 1:]
                    data = desktop.read(info)  # CRC-checked by zipfile
                    if name.endswith('.rpa'):
                        hashes[name] = hashlib.sha256(data).hexdigest()
                    game.writestr(zipfile.ZipInfo(name, info.date_time), data,
                                  zipfile.ZIP_STORED if name.endswith('.rpa') else zipfile.ZIP_DEFLATED)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as result:
                for info in template.infolist():
                    if info.filename == 'game.zip':
                        result.writestr(info, blob.getvalue(), zipfile.ZIP_STORED)
                    else:
                        result.writestr(info, template.read(info))
    digest = hashlib.sha256(args.desktop.read_bytes()).hexdigest()
    evidence = {
        'runtime': release.group(1), 'package_version': version, 'package_sha256': digest,
        'game_files': len(selected), 'excluded_cache_or_save_files': skipped,
        'archive_sha256': hashes, 'game_code_executed_during_assembly': False,
    }
    if args.evidence:
        args.evidence.write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'Assembled Ren\'Py {version} desktop data ({len(selected)} game files, '
          f'{skipped} cache/save files excluded)')


if __name__ == '__main__':
    main()
