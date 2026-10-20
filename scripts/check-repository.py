#!/usr/bin/env python3
"""Basic accident prevention, not a replacement for GitHub secret scanning or security review."""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
failures = []
patterns = [
    rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    rb'gh[pousr]_[A-Za-z0-9]{30,}',
    rb'AKIA[0-9A-Z]{16}',
]
for name in filter(None, files):
    path = root / name
    if path.suffix in {'.p12', '.mobileprovision', '.p8'} or path.name == '.env':
        failures.append(name + ': credential file must not be tracked')
    if path.is_file() and path.suffix != '.zip':
        data = path.read_bytes()
        if any(re.search(pattern, data) for pattern in patterns):
            failures.append(name + ': possible credential (value suppressed)')
        if name.startswith('.github/workflows/'):
            for action in re.findall(rb'uses:\s*([^\s#]+)', data):
                if not re.fullmatch(rb'[\w.-]+/[\w./-]+@[a-f0-9]{40}', action):
                    failures.append(name + ': unpinned workflow action')
if failures:
    raise SystemExit('\n'.join(failures))
print('Tracked-file credential patterns and workflow action pins checked.')
