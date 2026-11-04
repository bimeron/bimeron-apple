#!/usr/bin/env python3
"""Offline only: never execute candidate Core or generated Installer scripts."""
import importlib.util
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True

BASE = Path(__file__).resolve().parent


class PackageTests(unittest.TestCase):
    def test_offline_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            binary = root / 'candidate'
            binary.write_bytes(b'#!/bin/sh\necho MUST-NOT-EXECUTE >&2\nexit 99\n')
            output = root / 'local-dev.pkg'
            command = [sys.executable, str(BASE / 'build.py'), '--binary', str(binary),
                       '--sha256', hashlib.sha256(binary.read_bytes()).hexdigest(),
                       '--version', 'dev.1', '--revision', 'abc123', '--architecture', 'arm64',
                       '--owner-uid', '501', '--output', str(output)]
            def build(args, success):
                result = subprocess.run(args, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                return result
            for option, value in [('--owner-uid', '0'), ('--owner-uid', '500'),
                                  ('--owner-uid', '501x'), ('--architecture', 'unknown'),
                                  ('--revision', 'a\nb'), ('--sha256', '0' * 64),
                                  ('--output', str(root / '../escape.pkg'))]:
                changed = command.copy()
                changed[changed.index(option) + 1] = value
                build(changed, False)
            link = root / 'link'
            link.symlink_to(binary)
            changed = command.copy()
            changed[changed.index('--binary') + 1] = str(link)
            build(changed, False)
            spec = importlib.util.spec_from_file_location('local_builder', BASE / 'build.py')
            builder = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(builder)
            with mock.patch.object(sys, 'argv', command[1:]), mock.patch.object(builder.subprocess, 'run', side_effect=RuntimeError('synthetic pkgbuild failure')):
                with self.assertRaises(RuntimeError):
                    builder.main()
            self.assertFalse(output.exists())
            report = json.loads(build(command, True).stdout.splitlines()[-1])
            print('Synthetic package SHA256: ' + report['package_sha256'])
            print('Synthetic binary SHA256: ' + report['binary_sha256'])
            self.assertEqual(report['package_sha256'], hashlib.sha256(output.read_bytes()).hexdigest())
            build(command, False)
            expanded = root / 'expanded'
            subprocess.run(['/usr/sbin/pkgutil', '--expand-full', str(output), str(expanded)], check=True)
            bom = subprocess.check_output(['/usr/bin/lsbom', '-p', 'fmug', str(expanded / 'Bom')], text=True)
            for row in bom.splitlines():
                name, mode, uid, gid = row.split('\t')
                self.assertEqual((uid, gid), ('0', '0'), row)
                expected_mode = 0o100755 if name.endswith('org.bimeron.core') else 0o100644
                if not name.endswith(('.core', '.json', '.plist')):
                    expected_mode = 0o40755
                self.assertEqual(int(mode, 8), expected_mode, row)
            payload = expanded / 'Payload'
            expected = {'Library/PrivilegedHelperTools/org.bimeron.core',
                        'Library/PrivilegedHelperTools/org.bimeron.core.dev.json',
                        'Library/LaunchDaemons/org.bimeron.core.plist'}
            self.assertEqual({str(p.relative_to(payload)) for p in payload.rglob('*') if p.is_file()}, expected)
            core = payload / 'Library/PrivilegedHelperTools/org.bimeron.core'
            self.assertEqual(core.read_bytes(), binary.read_bytes())
            for name in expected:
                self.assertEqual((payload / name).stat().st_mode & 0o777, 0o755 if name.endswith('.core') else 0o644)
            metadata = json.loads(Path(str(core) + '.dev.json').read_text())
            self.assertEqual(metadata['owner_uid'], 501)
            self.assertFalse(metadata['metadata_authenticated'])
            plist = plistlib.loads((payload / 'Library/LaunchDaemons/org.bimeron.core.plist').read_bytes())
            self.assertEqual(plist['ProgramArguments'], ['/Library/PrivilegedHelperTools/org.bimeron.core', 'daemon'])
            self.assertEqual(plist['EnvironmentVariables']['BIMERON_CONTROL_UID'], '501')
            self.assertNotIn('KeepAlive', plist)
            for script in (expanded / 'Scripts').iterdir():
                subprocess.run(['/bin/sh', '-n', str(script)], check=True)
            # Source only pure checks with a sandbox prefix; no Installer script runs.
            harness = '. "$1"; check_absent "$2"'
            def absent(ok):
                result = subprocess.run(['/bin/sh', '-c', harness, 'test', str(BASE / 'guards.sh'), str(root)], capture_output=True)
                self.assertEqual(result.returncode == 0, ok)
            absent(True)
            destination = root / 'Library/PrivilegedHelperTools/org.bimeron.core'
            destination.parent.mkdir(parents=True)
            destination.symlink_to(root / 'missing')
            absent(False)
            destination.unlink()
            destination.write_text('existing')
            absent(False)
            # Exercise missing-leaf logic with protected ownership stubbed only here.
            ancestry = root / 'ancestry'
            (ancestry / 'Library').mkdir(parents=True)
            check = '. "$1"; protected_directory() { [ ! -L "$1" ] && [ -d "$1" ] || fail unsafe; }; check_ancestry "$2" "$3"'
            def ancestry_check(mode, ok):
                result = subprocess.run(['/bin/sh', '-c', check, 'test', str(BASE / 'guards.sh'), str(ancestry), mode], capture_output=True)
                self.assertEqual(result.returncode == 0, ok)
            ancestry_check('fresh', True)
            ancestry_check('installed', False)
            (ancestry / 'Library/PrivilegedHelperTools').symlink_to(root / 'missing')
            ancestry_check('fresh', False)
            # A user-owned/writable sandbox ancestry must be rejected.
            result = subprocess.run(['/bin/sh', '-c', '. "$1"; protected_directory "$2"',
                                     'test', str(BASE / 'guards.sh'), str(root)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
