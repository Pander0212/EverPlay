#!/usr/bin/env python3
"""Reject an apparently successful xcodebuild invocation that did not execute the acceptance tests."""
from pathlib import Path
import re
import sys

required = [
    'testRealHTTPTransportServesImportedGameAndRanges',
    'testGameStorageIsolationAndSessionReopen',
    'testDemoZIPImportLaunchTouchAndPersistentReopen',
    'testVirtualControlLayoutPersistsAndGameRemainsUsableInLandscape',
]
log = Path(sys.argv[1]).read_text(errors='replace')
missing = [name for name in required if not re.search(
    rf'^Test case [^\r\n]*\b{re.escape(name)}\b[^\r\n]*\bpassed\b', log, re.MULTILINE | re.IGNORECASE)]
if missing:
    print('::error title=Native acceptance tests were not verified::' + ', '.join(missing))
    raise SystemExit(1)
print(f'::notice title=EverPlay CI::{len(required)} required native HTTP, WebKit and UI acceptance tests passed.')
