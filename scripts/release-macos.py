#!/usr/bin/env python3
"""Prepare a notarized macOS release locally. Never installs or publishes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.check_output([str(arg) for arg in args], cwd=ROOT, **kwargs).decode().strip()

def preflight(env):
    for name, prefix in [('CLEARMIC_SIGN_IDENTITY', 'Developer ID Application:'),
                         ('CLEARMIC_INSTALLER_IDENTITY', 'Developer ID Installer:')]:
        if not env.get(name, '').startswith(prefix):
            raise RuntimeError(f'Set {name} to a {prefix} identity in your keychain.')
    if not env.get('CLEARMIC_NOTARY_PROFILE'):
        raise RuntimeError('Set CLEARMIC_NOTARY_PROFILE to a notarytool keychain profile.')
    key = Path(env.get('CLEARMIC_UPDATE_KEY', str(Path.home() / '.local/share/clearmic-signing/ed25519.key')))
    if not key.is_file():
        raise RuntimeError('Update signing key missing. Set CLEARMIC_UPDATE_KEY; never replace a published key.')
    if run('git', 'status', '--porcelain', '--untracked-files=normal'):
        raise RuntimeError('Commit source changes and remove untracked files before preparing a release.')
    release = json.loads((ROOT / 'Release/version.json').read_text())
    if not re.fullmatch(r'\d+\.\d+\.\d+', release['version']) or not re.fullmatch(r'[1-9]\d*', release['build']):
        raise RuntimeError('Release/version.json needs numeric x.y.z and a positive integer build.')
    versions = ET.parse(ROOT / 'Release/appcast.xml').findall('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
    if any(int(node.text) >= int(release['build']) for node in versions):
        raise RuntimeError('Increment version/build beyond the published appcast before release preparation.')
    identities = run('security', 'find-identity', '-v', '-p', 'basic')
    for name in ['CLEARMIC_SIGN_IDENTITY', 'CLEARMIC_INSTALLER_IDENTITY']:
        if env[name] not in identities:
            raise RuntimeError(f'{name} is not available in the current keychain.')
    run('xcrun', 'notarytool', 'history', '--keychain-profile', env['CLEARMIC_NOTARY_PROFILE'], '--output-format', 'json')
    return release, key

def notarize(path, profile):
    result = json.loads(run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile, '--wait', '--output-format', 'json'))
    if result.get('status') != 'Accepted':
        raise RuntimeError('Notarization was not accepted: ' + str(result.get('id', 'unknown submission')))
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate prerequisites only; no build or upload')
    args = parser.parse_args()
    env = dict(os.environ)
    release, key = preflight(env)
    if args.check:
        print('Release prerequisites available. No artifacts built or uploaded.')
        return
    version = release['version']
    output = ROOT / 'build/releases' / version
    output.mkdir(parents=True, exist_ok=False)
    env.update(CLEARMIC_UNIVERSAL='1', CLEARMIC_VERSION=version, CLEARMIC_BUILD=release['build'])
    subprocess.run(['scripts/build-app.sh'], cwd=ROOT, env=env, check=True)
    app = ROOT / 'build/ClearMic.app'
    for binary in [app / 'Contents/MacOS/ClearMic', ROOT / 'build/ClearMic.driver/Contents/MacOS/ClearMic']:
        run('lipo', binary, '-verify_arch', 'arm64', 'x86_64')
    zip_path = output / f'ClearMic-{version}.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, zip_path)
    app_receipt = notarize(zip_path, env['CLEARMIC_NOTARY_PROFILE'])
    run('xcrun', 'stapler', 'staple', app)
    run('xcrun', 'stapler', 'validate', app)
    run('spctl', '--assess', '--type', 'execute', app)
    # Archive again so the downloadable app includes its stapled ticket.
    zip_path.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, zip_path)
    subprocess.run(['python3', 'scripts/package-component.py', 'all'], cwd=ROOT, env=env, check=True)
    pkg = output / f'ClearMic-{version}.pkg'
    (ROOT / 'build' / pkg.name).rename(pkg)
    pkg_receipt = notarize(pkg, env['CLEARMIC_NOTARY_PROFILE'])
    run('xcrun', 'stapler', 'staple', pkg)
    run('xcrun', 'stapler', 'validate', pkg)
    run('pkgutil', '--check-signature', pkg)
    run('spctl', '--assess', '--type', 'install', pkg)
    run('.build/artifacts/sparkle/Sparkle/bin/generate_appcast', '--ed-key-file', key,
        '--download-url-prefix', f'https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v{version}/', output)
    feed = output / 'appcast.xml'
    run('python3', 'scripts/normalize-appcast.py', feed)
    run('swift', 'scripts/verify-update.swift', 'Release/public-key.txt', feed, zip_path)
    manifest = {'commit': run('git', 'rev-parse', 'HEAD'), **release,
                'notarization': {'app': app_receipt, 'installer': pkg_receipt},
                'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [pkg, zip_path]},
                'live_install_update_audio_tests': 'pending'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Prepared {output}. Complete live acceptance before publishing. Repository appcast unchanged.')

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, FileExistsError) as error:
        raise SystemExit(str(error))
