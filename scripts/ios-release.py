#!/usr/bin/env python3
"""ClearMic iOS release commands using the mini's existing studio credentials."""
import argparse
import base64
import ctypes
import importlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'ios/Release.json').read_text())
OUTPUT = ROOT / 'build/ios-release'
ARCHIVE = OUTPUT / 'ClearMic.xcarchive'


def credentials(*names):
    values = {name: os.environ[name] for name in names if os.environ.get(name)}
    missing = [name for name in names if name not in values]
    if not missing:
        return values
    override = os.environ.get('STUDIO_LIB_PATH')
    candidates = [Path(override).expanduser()] if override else [p / 'lib' for p in ROOT.parents]
    library = next((p for p in candidates if (p / 'studio/credentials.py').is_file()), None)
    if library is None:
        raise RuntimeError('Set release environment variables: ' + ', '.join(missing) + '. STUDIO_LIB_PATH is an optional maintainer fallback.')
    sys.path.insert(0, str(library))
    module = importlib.import_module('studio.credentials')
    values.update({name: module.require(name).reveal() for name in missing})
    return values


def run(args, label, values=None):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    text = result.stdout
    for name, value in (values or {}).items():
        if value: text = text.replace(value, '<' + name + '>')
    (OUTPUT / (label + '.log')).write_text(text)
    if result.returncode:
        raise RuntimeError(f'{label} failed. Inspect build/ios-release/{label}.log on the mini.')
    return text


def encoded(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


class AppStore:
    def __init__(self):
        self.values = credentials('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID')

    def token(self):
        now = int(time.time())
        header = encoded(json.dumps({'alg': 'ES256', 'kid': self.values['ASC_KEY_ID'], 'typ': 'JWT'}).encode())
        payload = encoded(json.dumps({'iss': self.values['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
        message = header + b'.' + payload
        result = subprocess.run(['/usr/bin/openssl', 'dgst', '-sha256', '-sign', self.values['ASC_KEY_PATH']], input=message, capture_output=True)
        if result.returncode: raise RuntimeError('App Store API request signing failed.')
        der = result.stdout
        if len(der) < 6 or der[0] != 48 or der[1] + 2 != len(der): raise RuntimeError('Unexpected API signature format.')
        position, parts = 2, []
        for _ in range(2):
            if der[position] != 2: raise RuntimeError('Unexpected API signature integer.')
            length = der[position + 1]
            parts.append(int.from_bytes(der[position + 2:position + 2 + length], 'big').to_bytes(32, 'big'))
            position += 2 + length
        return (message + b'.' + encoded(b''.join(parts))).decode()

    def request(self, path, method='GET', data=None):
        request = urllib.request.Request('https://api.appstoreconnect.apple.com' + path,
            headers={'Authorization': 'Bearer ' + self.token(), 'Content-Type': 'application/json'},
            method=method, data=json.dumps(data).encode() if data is not None else None)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            try: errors = json.loads(error.read()).get('errors', [])
            except ValueError: errors = []
            detail = '; '.join(e.get('detail') or e.get('title', '') for e in errors)
            for value in self.values.values():
                if value: detail = detail.replace(value, '<credential>')
            raise RuntimeError(f'App Store API {method} {path.split("?")[0]} returned {error.code}: {detail[:700]}') from None

    def find_app(self):
        query = urllib.parse.urlencode({'filter[bundleId]': CONFIG['bundleId']})
        apps = self.request('/v1/apps?' + query)['data']
        return apps[0] if apps else None

    def app(self):
        app = self.find_app()
        if not app: raise RuntimeError('Create the ClearMic App Store Connect record first, using ' + CONFIG['bundleId'] + '.')
        return app

    def register(self):
        query = urllib.parse.urlencode({'filter[identifier]': CONFIG['bundleId']})
        found = self.request('/v1/bundleIds?' + query)['data']
        if not found:
            found = [self.request('/v1/bundleIds', 'POST', {'data': {'type': 'bundleIds', 'attributes': {
                'name': CONFIG['name'], 'platform': 'IOS', 'identifier': CONFIG['bundleId']}}})['data']]
        print('Bundle identifier registered:', found[0]['attributes']['identifier'])
        app = self.find_app()
        print('App Store record:', app['id'] if app else 'Awaiting creation in App Store Connect')

    def status(self):
        app = self.app()
        builds = self.request('/v1/builds?' + urllib.parse.urlencode({'filter[app]': app['id'], 'sort': '-uploadedDate', 'limit': 5}))['data']
        groups = self.request(f'/v1/apps/{app["id"]}/betaGroups')['data']
        details = self.request(f'/v1/builds/{builds[0]["id"]}/buildBetaDetail')['data']['attributes'] if builds else {}
        print(json.dumps({'betaState': details.get('internalBuildState'), 'appId': app['id'], 'bundleId': CONFIG['bundleId'], 'name': app['attributes']['name'],
            'builds': [{'id': b['id'], 'version': b['attributes']['version'], 'processingState': b['attributes']['processingState']} for b in builds],
            'groups': [{'id': g['id'], 'name': g['attributes']['name'], 'internal': g['attributes']['isInternalGroup']} for g in groups]}, indent=2))

    def enable_testing(self):
        app = self.app()
        groups = self.request(f'/v1/apps/{app["id"]}/betaGroups')['data']
        group = next((g for g in groups if g['attributes']['isInternalGroup'] and g['attributes']['name'] == 'Internal'), None)
        if group is None:
            group = self.request('/v1/betaGroups', 'POST', {'data': {'type': 'betaGroups',
                'attributes': {'name': 'Internal', 'isInternalGroup': True, 'hasAccessToAllBuilds': True},
                'relationships': {'app': {'data': {'type': 'apps', 'id': app['id']}}}}})['data']
        source_apps = self.request('/v1/apps?' + urllib.parse.urlencode({'filter[bundleId]': 'flow-labs.link-inbox'}))['data']
        if not source_apps: raise RuntimeError('Existing Link Inbox tester group is unavailable.')
        source_groups = self.request(f'/v1/apps/{source_apps[0]["id"]}/betaGroups')['data']
        source = next(g for g in source_groups if g['attributes']['name'] == 'Internal' and g['attributes']['isInternalGroup'])
        testers = self.request(f'/v1/betaGroups/{source["id"]}/betaTesters')['data']
        if len(testers) != 1: raise RuntimeError('Expected the existing single-owner Internal group. Confirm intended testers before expanding access.')
        existing = self.request(f'/v1/betaGroups/{group["id"]}/betaTesters')['data']
        existing_emails = {t['attributes']['email'].casefold() for t in existing}
        for tester in testers:
            attributes = tester['attributes']
            if attributes['email'].casefold() not in existing_emails:
                self.request('/v1/betaTesters', 'POST', {'data': {'type': 'betaTesters',
                    'attributes': {k: v for k, v in attributes.items() if k in ('email', 'firstName', 'lastName') and v},
                    'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group['id']}]}}}})
        builds = self.request('/v1/builds?' + urllib.parse.urlencode({'filter[app]': app['id'], 'sort': '-uploadedDate', 'limit': 1}))['data']
        if builds:
            build = builds[0]
            assigned = self.request(f'/v1/betaGroups/{group["id"]}/builds')['data']
            if build['id'] not in {item['id'] for item in assigned}:
                self.request(f'/v1/betaGroups/{group["id"]}/relationships/builds', 'POST', {'data': [{'type': 'builds', 'id': build['id']}]})
            localizations = self.request(f'/v1/builds/{build["id"]}/betaBuildLocalizations')['data']
            if not localizations:
                self.request('/v1/betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations', 'attributes': {
                    'locale': CONFIG['locale'], 'whatsNew': 'Experimental Bluetooth mic routing. Pair your transmitter in Settings, choose it in ClearMic, test levels, then Prepare Camera and switch to Camera. Verify the recorded mic yourself. Receiver-free Camera compatibility is not guaranteed. Temporary tests stop after 30 seconds and are deleted.'},
                    'relationships': {'build': {'data': {'type': 'builds', 'id': build['id']}}}}})
        print('Internal testing configured for the existing owner tester; no external testers or App Review submission.')
        self.status()


def archive():
    if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT).strip():
        raise RuntimeError('Commit tracked release changes before archiving.')
    build = subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=ROOT, text=True).strip()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    run(['xcodebuild', '-project', 'ios/ClearMic.xcodeproj', '-scheme', 'ClearMic-iOS', '-destination', 'generic/platform=iOS',
         '-configuration', 'Release', '-derivedDataPath', str(OUTPUT / 'derived'), '-archivePath', str(ARCHIVE),
         'CODE_SIGNING_ALLOWED=NO', 'CURRENT_PROJECT_VERSION=' + build, 'MARKETING_VERSION=' + CONFIG['version'], 'archive'], 'archive')
    app = ARCHIVE / 'Products/Applications/ClearMic.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != CONFIG['bundleId'] or info['CFBundleVersion'] != build:
        raise RuntimeError('Archive identity or build number does not match the release.')
    run(['codesign', '--force', '--sign', '-', str(app)], 'archive-signature')
    (OUTPUT / 'manifest.json').write_text(json.dumps({'commit': commit, 'build': build, 'version': CONFIG['version'], 'bundleId': CONFIG['bundleId']}, indent=2) + '\n')
    print('Archived', CONFIG['version'], 'build', build, 'commit', commit[:8])


def unlock_if_needed(values):
    security = ctypes.CDLL('/System/Library/Frameworks/Security.framework/Security')
    security.SecKeychainOpen.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    security.SecKeychainGetStatus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    security.CFRelease.argtypes = [ctypes.c_void_p]
    keychain = ctypes.c_void_p()
    status = ctypes.c_uint32()
    opened = security.SecKeychainOpen(values['SIGNING_KEYCHAIN'].encode(), ctypes.byref(keychain))
    if opened != 0: raise RuntimeError('Signing keychain could not be opened.')
    try:
        result = security.SecKeychainGetStatus(keychain, ctypes.byref(status))
        if result != 0: raise RuntimeError('Signing keychain status is unavailable.')
        if not (status.value & 1):
            password = credentials('CLEARMIC_SIGNING_KEYCHAIN_PASSWORD')
            run(['security', 'unlock-keychain', '-p', password['CLEARMIC_SIGNING_KEYCHAIN_PASSWORD'], values['SIGNING_KEYCHAIN']], 'keychain-unlock', {**values, **password})
    finally: security.CFRelease(keychain)


def release(destination):
    if destination == 'upload':
        AppStore().app()
    values = credentials('TEAM_ID', 'ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'CLEARMIC_SIGNING_KEYCHAIN')
    values['SIGNING_KEYCHAIN'] = values['CLEARMIC_SIGNING_KEYCHAIN']
    identity_path = Path.home() / '.local/share/clearmic-signing/ios/identity.json'
    if not identity_path.is_file(): raise RuntimeError('Run scripts/ios-signing-setup.py on the mini first.')
    identity = json.loads(identity_path.read_text())
    if not identity.get('complete'): raise RuntimeError('ClearMic signing setup is incomplete.')
    archive()
    unlock_if_needed(values)
    options = {'method': 'app-store-connect', 'destination': destination, 'teamID': values['TEAM_ID'],
               'signingStyle': 'manual', 'signingCertificate': identity['sha1'],
               'provisioningProfiles': {CONFIG['bundleId']: identity['profileUUID']}}
    options_path = OUTPUT / 'export-options.plist'
    options_path.write_bytes(plistlib.dumps(options))
    run(['xcodebuild', '-exportArchive', '-archivePath', str(ARCHIVE), '-exportPath', str(OUTPUT / 'export'), '-exportOptionsPlist', str(options_path),
         '-allowProvisioningUpdates', '-authenticationKeyPath', values['ASC_KEY_PATH'], '-authenticationKeyID', values['ASC_KEY_ID'], '-authenticationKeyIssuerID', values['ASC_ISSUER_ID']], destination, values)
    print('App Store Connect upload completed.' if destination == 'upload' else 'Signed IPA export completed.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['archive', 'export', 'upload', 'register', 'status', 'enable-testing'])
    action = parser.parse_args().action
    try:
        if action == 'archive': archive()
        elif action in ('export', 'upload'): release('export' if action == 'export' else 'upload')
        else:
            client = AppStore()
            if action == 'register': client.register()
            elif action == 'status': client.status()
            else: client.enable_testing()
    except Exception as error:
        # Avoid exception tracebacks containing subprocess argument values.
        print('iOS release stopped: ' + str(error), file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
