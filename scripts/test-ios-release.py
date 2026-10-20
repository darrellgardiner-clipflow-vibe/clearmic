import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ios_release', Path(__file__).with_name('ios-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_failed_command_redacts_credentials_in_persisted_log_and_exception(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(release, 'OUTPUT', Path(directory)), patch.object(release.subprocess, 'run', return_value=types.SimpleNamespace(returncode=1, stdout='failed secret-value at private-key-path')):
            with self.assertRaises(RuntimeError) as error:
                release.run(['fake-command'], 'export', {'PASSWORD': 'secret-value', 'KEY_PATH': 'private-key-path'})
            persisted = (Path(directory) / 'export.log').read_text()
            for text in (persisted, str(error.exception)):
                self.assertNotIn('secret-value', text)
                self.assertNotIn('private-key-path', text)
            self.assertIn('<PASSWORD>', persisted)

    def test_archive_refuses_uncommitted_source_before_running_xcode(self):
        with patch.object(release.subprocess, 'check_output', return_value=b' M ios/App/Info.plist'), patch.object(release, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Commit tracked'):
                release.archive()
            run.assert_not_called()

    def test_jwt_has_a_valid_es256_signature_without_logging_key_material(self):
        with tempfile.TemporaryDirectory() as directory:
            private, public = Path(directory) / 'private.pem', Path(directory) / 'public.pem'
            subprocess.run(['/usr/bin/openssl', 'ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', private], check=True, capture_output=True)
            subprocess.run(['/usr/bin/openssl', 'ec', '-in', private, '-pubout', '-out', public], check=True, capture_output=True)
            store = release.AppStore.__new__(release.AppStore)
            store.values = {'ASC_KEY_PATH': str(private), 'ASC_KEY_ID': 'test-key', 'ASC_ISSUER_ID': 'test-issuer'}
            token = store.token()
            header, body, signature = token.split('.')
            decode = lambda value: base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
            self.assertEqual(json.loads(decode(header))['alg'], 'ES256')
            claims = json.loads(decode(body))
            self.assertEqual(claims['aud'], 'appstoreconnect-v1')
            self.assertEqual(claims['exp'] - claims['iat'], 600)
            raw = decode(signature)
            self.assertEqual(len(raw), 64)
            integers = []
            for value in [raw[:32], raw[32:]]:
                value = value.lstrip(b'\0') or b'\0'
                if value[0] & 128: value = b'\0' + value
                integers.append(b'\x02' + bytes([len(value)]) + value)
            sequence = b''.join(integers)
            signed = Path(directory) / 'signature.der'
            signed.write_bytes(b'\x30' + bytes([len(sequence)]) + sequence)
            result = subprocess.run(['/usr/bin/openssl', 'dgst', '-sha256', '-verify', public, '-signature', signed], input=(header + '.' + body).encode(), capture_output=True)
            self.assertEqual(result.returncode, 0)

    def test_already_configured_internal_group_performs_no_writes(self):
        store = release.AppStore.__new__(release.AppStore)
        store.app = lambda: {'id': 'clear-app'}
        store.status = lambda: None
        group = {'id': 'internal', 'attributes': {'name': 'Internal', 'isInternalGroup': True}}
        def request(path, method='GET', data=None):
            self.assertEqual(method, 'GET', 'An already assigned build/tester must not be posted again')
            if '/betaGroups' in path and path.endswith('/betaGroups'): return {'data': [group]}
            if path.startswith('/v1/apps?'): return {'data': [{'id': 'source-app'}]}
            if path.endswith('/betaTesters'): return {'data': [{'id': 'owner'}]}
            if path.startswith('/v1/builds?') or path.endswith('/builds'): return {'data': [{'id': 'build-1'}]}
            if path.endswith('/betaBuildLocalizations'): return {'data': [{'id': 'english'}]}
            raise AssertionError(path)
        store.request = request
        with contextlib.redirect_stdout(io.StringIO()): store.enable_testing()


if __name__ == '__main__': unittest.main()
