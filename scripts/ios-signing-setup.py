#!/usr/bin/env python3
"""Set up a ClearMic-only distribution identity without altering other identities."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/ios-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def main():
    folder = Path.home() / '.local/share/clearmic-signing/ios'
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(folder, 0o700)
    state_path = folder / 'identity.json'
    if state_path.exists():
        state = json.loads(state_path.read_text())
        if state.get('complete'):
            print('ClearMic signing identity already configured.')
            return
    else:
        state = {}
    def persist():
        state_path.write_text(json.dumps(state, indent=2))
        os.chmod(state_path, 0o600)
    def run(args, data=None):
        result = subprocess.run([str(arg) for arg in args], input=data, capture_output=True)
        if result.returncode:
            message = result.stderr.decode(errors='replace')
            for arg in args[2:]:
                if len(str(arg)) > 5: message = message.replace(str(arg), '<argument>')
            raise RuntimeError('Signing setup command failed: ' + str(args[0]) + ' ' + str(args[1]) + ': ' + message[:400])
        return result.stdout
    client = release.AppStore()
    private, csr = folder / 'private.pem', folder / 'request.csr'
    if not private.exists():
        run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', private, '-out', csr, '-subj', '/CN=ClearMic Distribution'])
        os.chmod(private, 0o600)
    if not state.get('certificateId'):
        existing = client.request('/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200')['data']
        if len(existing) >= 3: raise RuntimeError('Distribution certificate limit reached. No existing certificate was revoked.')
        certificate = client.request('/v1/certificates', 'POST', {'data': {'type': 'certificates', 'attributes': {'certificateType': 'DISTRIBUTION', 'csrContent': csr.read_text()}}})['data']
        der = base64.b64decode(certificate['attributes']['certificateContent'])
        (folder / 'certificate.der').write_bytes(der)
        state['certificateId'] = certificate['id']
        state['sha1'] = hashlib.sha1(der).hexdigest().upper()
        persist()
    run(['openssl', 'x509', '-inform', 'DER', '-in', folder / 'certificate.der', '-out', folder / 'certificate.pem'])
    password_file = folder / 'setup-password'
    if not password_file.exists():
        password_file.write_text(secrets.token_urlsafe(48))
        os.chmod(password_file, 0o600)
    password = password_file.read_text()
    p12 = folder / 'identity.p12'
    if not state.get('imported'):
        run(['openssl', 'pkcs12', '-export', '-inkey', private, '-in', folder / 'certificate.pem', '-out', p12, '-legacy', '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1', '-passout', 'stdin'], (password + '\n').encode())
        os.chmod(p12, 0o600)
    keychain = Path.home() / 'Library/Keychains/clearmic-signing.keychain-db'
    if not keychain.exists():
        run(['security', 'create-keychain', '-p', password, keychain])
    run(['security', 'unlock-keychain', '-p', password, keychain])
    run(['security', 'set-keychain-settings', '-lut', '21600', keychain])
    if not state.get('imported'):
        run(['security', 'import', p12, '-k', keychain, '-P', password, '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'])
        run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain])
        state['imported'] = True
        persist()
    search = shlex.split(run(['security', 'list-keychains', '-d', 'user']).decode())
    if str(keychain) not in search:
        run(['security', 'list-keychains', '-d', 'user', '-s', *search, keychain])
    bundles = client.request('/v1/bundleIds?' + release.urllib.parse.urlencode({'filter[identifier]': release.CONFIG['bundleId']}))['data']
    if not bundles: raise RuntimeError('Register the ClearMic bundle identifier first.')
    if not state.get('profileId'):
        profile = client.request('/v1/profiles', 'POST', {'data': {'type': 'profiles', 'attributes': {'name': 'ClearMic App Store', 'profileType': 'IOS_APP_STORE'},
            'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundles[0]['id']}}, 'certificates': {'data': [{'type': 'certificates', 'id': state['certificateId']}]}}}})['data']
        (folder / 'profile.mobileprovision').write_bytes(base64.b64decode(profile['attributes']['profileContent']))
        state['profileId'] = profile['id']; state['profileUUID'] = profile['attributes']['uuid']; persist()
    profiles = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    profiles.mkdir(parents=True, exist_ok=True)
    profile_path = profiles / (state['profileUUID'] + '.mobileprovision')
    profile_path.write_bytes((folder / 'profile.mobileprovision').read_bytes())
    os.chmod(profile_path, 0o600)
    credential_file = Path.home() / '.config/studio/credentials.env'
    if credential_file.exists() and credential_file.stat().st_mode & 0o077:
        raise RuntimeError('Existing studio credential file has unsafe permissions; it was not changed.')
    original = credential_file.read_text() if credential_file.exists() else ''
    entries = {'CLEARMIC_SIGNING_KEYCHAIN': str(keychain), 'CLEARMIC_SIGNING_KEYCHAIN_PASSWORD': password}
    lines = original.splitlines()
    for name, value in entries.items():
        matches = [i for i, line in enumerate(lines) if line.partition('=')[0].strip().removeprefix('export ') == name]
        if matches:
            existing = lines[matches[0]].partition('=')[2].strip().strip("\"'")
            if existing == value: continue
            raise RuntimeError('A different ClearMic credential already exists; refusing to overwrite it.')
        lines.append(name + '=' + value)
    credential_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile('w', dir=credential_file.parent, delete=False) as destination:
        destination.write('\n'.join(lines) + '\n')
        temporary = Path(destination.name)
    os.chmod(temporary, 0o600)
    os.replace(temporary, credential_file)
    state['keychain'] = str(keychain); state['complete'] = True; persist()
    private.unlink(missing_ok=True)
    password_file.unlink(missing_ok=True)
    print('ClearMic distribution certificate, profile and dedicated signing keychain configured. Existing identities preserved.')


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print('ClearMic signing setup stopped: ' + str(error))
        raise SystemExit(1)
