#!/usr/bin/env python3
"""Publish a bounded build diagnostic through standard GitHub annotations as well as raw logs."""
from pathlib import Path
import os
import re
import sys

phase = re.sub(r'[^a-z-]', '', sys.argv[1])
code = sys.argv[2]
path = Path('artifacts') / f'{phase}.log'
text = path.read_text(errors='replace') if path.exists() else 'No phase log was produced.'
text = re.sub(r'\x1b\[[0-9;]*m', '', text)
lines = text.splitlines()
important = [line for line in lines if re.search(r'error:|XCTAssert|fatal error|Test (?:Case|Suite).*failed|Testing failed|TEST FAILED', line, re.IGNORECASE)]
if not important:
    important = [line for line in lines if re.search(r'failed|timed out|TimeoutExpired', line, re.IGNORECASE)]
diagnostic = '\n'.join((important or lines[-25:])[-45:])[-10000:]
if phase == 'ios-build-test':
    passed = sorted({name for line in lines if re.search(r'^Test case .*\bpassed\b', line, re.IGNORECASE)
                     for name in re.findall(r'\btest[A-Z]\w+', line)})
    if passed:
        print('::notice title=Completed iOS test cases::' + ', '.join(passed))
message = diagnostic.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print(f'::error title=EverPlay {phase} failed (exit {code})::{message}')
summary = os.environ.get('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a') as output:
        output.write(f'### {phase} failed (exit {code})\n\nSee `{path}` for the complete log.\n\n')
        output.write('```text\n' + diagnostic.replace('```', '~~~') + '\n```\n')
