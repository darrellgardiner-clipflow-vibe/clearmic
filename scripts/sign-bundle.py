#!/usr/bin/env python3
"""Sign nested Mach-O code inside-out, preserving Sparkle helper entitlements."""
import os
from pathlib import Path
import subprocess
import sys

bundle = Path(sys.argv[1])
identity = os.environ.get('CLEARMIC_SIGN_IDENTITY', '-')
flags = ['--timestamp', '--options', 'runtime'] if identity != '-' else []
# Sign individual binaries first, then enclosing bundles; never follow symlinks.
magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
files, bundles = [], []
for parent, directories, names in os.walk(bundle):
    directories[:] = [name for name in directories if not (Path(parent) / name).is_symlink()]
    for name in directories:
        path = Path(parent) / name
        if path.suffix in {'.framework', '.app', '.xpc', '.bundle'}:
            bundles.append(path)
    for name in names:
        path = Path(parent) / name
        if not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in magic:
                    files.append(path)
for path in files + sorted(bundles, key=lambda p: len(p.parts), reverse=True) + [bundle]:
    entitlements = ['--preserve-metadata=entitlements']
    if path == bundle and bundle.suffix == '.app':
        entitlements = ['--entitlements', str(Path(__file__).resolve().parents[1] / 'Release/ClearMic.entitlements')]
    subprocess.run(['codesign', '--force', '--sign', identity, *flags,
                    *entitlements, str(path)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
