#!/usr/bin/env python3
"""Controlled proof: attach a DIFFERENT original Windows game's archive to a fixed runtime.

Build tools execute only our reviewed fixture. The repack stage uses ZIP operations
only and never invokes RenPy or Python code from the desktop archive. This is not
an importer/converter for arbitrary user packages.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / 'scripts/build-renpy-probe.py')], cwd=ROOT, check=True)
cache = Path(os.environ.get('EVERPLAY_RENPY_CACHE', ROOT / '.build-tools/renpy'))
sdk = cache / 'renpy-8.5.3-sdk'
with tempfile.TemporaryDirectory(prefix='renpy-data-only-', dir=ROOT / '.build') as directory:
    work = Path(directory)
    project = work / 'different-game'
    (project / 'game').mkdir(parents=True)
    source = (ROOT / 'Experiments/RenPyProbe/game/script.rpy').read_text()
    assert source.count('default gold = 10') == 1
    (project / 'game/script.rpy').write_text(source.replace('default gold = 10', 'default gold = 37'))
    subprocess.run([str(sdk / 'renpy.sh'), str(sdk / 'launcher'), 'distribute', str(project),
                    '--package', 'win', '--no-update', '--destination', str(work / 'desktop')],
                   env=dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy'), check=True)
    with zipfile.ZipFile(work / 'desktop/EverPlayRenPyProbe-0.1-win.zip') as desktop:
        names = desktop.namelist()
        assert any(n.endswith('.exe') for n in names)
        assert not any(n.endswith('.sh') or ('/game/' in n and n.endswith('.rpy')) for n in names)
        files = {name: desktop.read('EverPlayRenPyProbe-0.1-win/game/' + name)
                 for name in ['story.rpa', 'script_version.txt']}

    # Conversion begins here: no game execution, source recompilation or archive
    # unpickling. Keep the template's engine/common code; replace all game files.
    with zipfile.ZipFile(ROOT / 'App/Resources/EverPlayRenPyProbe.zip') as template:
        blob = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(template.read('game.zip'))) as original:
            assert original.read('game/story.rpa') != files['story.rpa']
            with zipfile.ZipFile(blob, 'w', zipfile.ZIP_DEFLATED) as game:
                for name in original.namelist():
                    if not name.startswith('game/') and not name.endswith('/'):
                        game.writestr(name, original.read(name))
                for name, data in files.items():
                    game.writestr('game/' + name, data)
        output = ROOT / 'artifacts/EverPlayRenPyDataOnly.zip'
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as result:
            for name in template.namelist():
                result.writestr(name, blob.getvalue() if name == 'game.zip' else template.read(name))
    (ROOT / 'artifacts/renpy-data-only-evidence.json').write_text(json.dumps({
        'runtime': 'RenPy 8.5.3.26051504', 'template_initial_gold': 10,
        'windows_game_initial_gold': 37, 'source_scripts_in_input': False,
        'game_code_executed_during_repack': False,
        'windows_archive_sha256': hashlib.sha256(files['story.rpa']).hexdigest(),
    }, indent=2))
subprocess.run(['node', 'scripts/test-renpy-browser.mjs', '--data-only'], cwd=ROOT, check=True)
