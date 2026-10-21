#!/usr/bin/env python3
"""Build ONLY our trusted fixture through a Windows/Linux distribution into a web ZIP.

Ren'Py's builder executes game Python. This is not a converter for user-supplied games.
Engine downloads stay outside tracked source; release SHA-256 values are pinned.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '8.5.3'
RELEASE = '8.5.3.26051504'
BASE = f'https://github.com/renpy/renpy/releases/download/{RELEASE}'
HASHES = {
    f'renpy-{VERSION}-sdk.tar.bz2': 'eb0a9be7f0fb13632fe25ceade9a8bed5a1b4d6b6e83bd19eeeb29e1a1bb4a45',
    f'renpy-{VERSION}-web.zip': '954db897e65f51ea63cb2fb7b203d02be0447f4e22069514020bbe6c6691fdfc',
}
cache = Path(os.environ.get('EVERPLAY_RENPY_CACHE', ROOT / '.build-tools/renpy'))
cache.mkdir(parents=True, exist_ok=True)
for name, expected in HASHES.items():
    target = cache / name
    if not target.exists():
        subprocess.run(['curl', '--fail', '--location', '--show-error', '--retry', '2',
                        '--max-time', '300', f'{BASE}/{name}', '--output', str(target)], check=True)
    with target.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise SystemExit(f'Checksum mismatch: {name}; inspect/remove the failed download before retrying')
sdk = cache / f'renpy-{VERSION}-sdk'
if not sdk.exists():
    subprocess.run(['tar', '-xjf', str(cache / f'renpy-{VERSION}-sdk.tar.bz2'), '-C', str(cache)], check=True)
with zipfile.ZipFile(cache / f'renpy-{VERSION}-web.zip') as web:
    web.extractall(sdk)
env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
(ROOT / '.build').mkdir(exist_ok=True)
(ROOT / 'artifacts').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='renpy-probe-', dir=ROOT / '.build') as temporary:
    work = Path(temporary)
    original = work / 'original'
    (original / 'game').mkdir(parents=True)
    shutil.copy2(ROOT / 'Experiments/RenPyProbe/game/script.rpy', original / 'game/script.rpy')
    def run(*args):
        subprocess.run([str(sdk / 'renpy.sh'), *map(str, args)], env=env, check=True)
    run(original, 'lint')
    run(sdk / 'launcher', 'distribute', original, '--package', 'pc', '--no-update', '--destination', work / 'desktop')
    desktop = work / 'desktop/EverPlayRenPyProbe-0.1-pc.zip'
    converted = work / 'desktop-data'
    (converted / 'game').mkdir(parents=True)
    with zipfile.ZipFile(desktop) as package:
        entries = package.namelist()
        assert any(n.endswith('.exe') for n in entries), 'Windows launcher missing'
        assert any(n.endswith('.sh') for n in entries), 'Linux launcher missing'
        assert not any('/game/' in n and n.endswith('.rpy') for n in entries), 'Source scripts leaked into desktop fixture'
        prefix = 'EverPlayRenPyProbe-0.1-pc/game/'
        for name in ['story.rpa', 'script_version.txt']:
            (converted / 'game' / name).write_bytes(package.read(prefix + name))
    run(sdk / 'launcher', 'web_build', converted, '--destination', work / 'web')
    webroot = work / 'web'
    story = (converted / 'game/story.rpa').read_bytes()
    with zipfile.ZipFile(webroot / 'game.zip') as game:
        assert game.read('game/story.rpa') == story, 'Desktop archive changed during export'
        assert not any(n.startswith('game/') and n.endswith('.rpy') for n in game.namelist())
    shutil.copy2(sdk / 'LICENSE.txt', webroot / 'RENPY-LICENSE.txt')
    shutil.copy2(ROOT / 'LICENSE', webroot / 'EVERPLAY-FIXTURE-LICENSE.txt')
    (webroot / 'ENGINE-SOURCE.txt').write_text(
        f'Unmodified RenPyWeb {RELEASE}. Original EverPlay fixture.\n'
        f'Engine release and component source: {BASE}/renpy-{VERSION}-source.tar.bz2\n'
        f'Build sources/instructions: https://github.com/renpy/renpy/tree/{RELEASE}\n'
        'See RENPY-LICENSE.txt for MIT/LGPL and dependency notices.\n'
        'This generated test package is not an iPhone release or a general desktop-game converter.\n')
    output = ROOT / 'App/Resources/EverPlayRenPyProbe.zip'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as result:
        for path in sorted(webroot.rglob('*')):
            if path.is_file():
                result.write(path, path.relative_to(webroot).as_posix())
    evidence = f'RenPy {RELEASE}\nDesktop archive SHA256: {hashlib.sha256(story).hexdigest()}\nDesktop story.rpa preserved byte-for-byte; no original .rpy source used for conversion.\n'
    (ROOT / 'artifacts/renpy-build-evidence.txt').write_text(evidence)
    print(evidence + f'Generated {output.name}: {output.stat().st_size} bytes')
