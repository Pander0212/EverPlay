#!/usr/bin/env python3
"""Reproducible, original fixture bundled into the iOS app and consumed by integration tests."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
target = root / 'App/Resources/EverPlayDemo.zip'
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted((root / 'DemoGame').rglob('*')):
        if file.is_file():
            info = zipfile.ZipInfo('LanternGarden/' + file.relative_to(root / 'DemoGame').as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, file.read_bytes())
print(target.relative_to(root))
