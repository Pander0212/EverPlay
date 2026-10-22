#!/usr/bin/env python3
"""Rebuild the trusted 8.2.0 runtime prerequisite for the Contract Demon test.

Accepts no game input: the host SDK executes only our reviewed probe. Third-party
game data must subsequently be attached using passive archive operations.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RELEASE = '8.2.0.24012702'
BASE = f'https://github.com/renpy/renpy/releases/download/{RELEASE}'
HASHES = {
    'renpy-8.2.0-sdk.tar.bz2': 'e79ec1014bad6adba69336f90802e89ae7a70172c1bb9c15301267390e9d7b38',
    'renpy-8.2.0-web.zip': '6db580f557bd77d403b9c29b84e33ec2fe9fc154e5d38056d976703093dae92f',
}


def main():
    cache = Path(os.environ.get('EVERPLAY_RENPY82_CACHE', ROOT / '.build-tools/renpy-8.2')).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    for name, expected in HASHES.items():
        archive = cache / name
        if not archive.exists():
            subprocess.run(['curl', '--fail', '--location', '--show-error', '--retry', '2',
                            '--max-time', '300', f'{BASE}/{name}', '--output', str(archive)], check=True)
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != expected:
            raise SystemExit(f'Checksum mismatch: {name}; inspect the download before retrying')

    # Fresh extraction of verified archives avoids reusing an altered SDK/template.
    with tempfile.TemporaryDirectory(prefix='trusted-820-', dir=cache) as temporary:
        work = Path(temporary)
        subprocess.run(['tar', '-xjf', str(cache / 'renpy-8.2.0-sdk.tar.bz2'), '-C', str(work)], check=True)
        sdk = work / 'renpy-8.2.0-sdk'
        with zipfile.ZipFile(cache / 'renpy-8.2.0-web.zip') as archive:
            archive.extractall(sdk)
        project = work / 'trusted-probe'
        (project / 'game').mkdir(parents=True)
        shutil.copy2(ROOT / 'Experiments/RenPyProbe/game/script.rpy', project / 'game/script.rpy')
        webroot = work / 'web'
        subprocess.run([str(sdk / 'renpy.sh'), str(sdk / 'launcher'), 'web_build',
                        str(project), '--destination', str(webroot)], check=True,
                       env=dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy'))
        shutil.copy2(sdk / 'LICENSE.txt', webroot / 'RENPY-LICENSE.txt')
        shutil.copy2(ROOT / 'LICENSE', webroot / 'EVERPLAY-FIXTURE-LICENSE.txt')
        (webroot / 'ENGINE-SOURCE.txt').write_text(
            f'Unmodified RenPyWeb {RELEASE}; original EverPlay trusted template.\n'
            f'Engine/component source: {BASE}/renpy-8.2.0-source.tar.bz2\n'
            f'Build sources: https://github.com/renpy/renpy/tree/{RELEASE}\n'
            'See RENPY-LICENSE.txt for MIT/LGPL and dependency notices.\n'
            'This is a test prerequisite, not a general desktop-game converter.\n')
        for required in ['index.html', 'game.zip', 'renpy.wasm']:
            if not (webroot / required).is_file():
                raise SystemExit(f'Web build did not produce {required}')
        output = ROOT / 'artifacts/EverPlayRenPy820Template.zip'
        output.parent.mkdir(parents=True, exist_ok=True)
        staging = work / 'template.zip'
        with zipfile.ZipFile(staging, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(webroot.rglob('*')):
                if file.is_file():
                    archive.write(file, file.relative_to(webroot).as_posix())
        shutil.copyfile(staging, output)
        print(f'Built trusted RenPy {RELEASE} template: {output.name}')


if __name__ == '__main__':
    main()
