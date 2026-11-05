#!/usr/bin/env python3
"""Synthetic packaging checks; never build or launch an app."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('check_app_bundle', Path(__file__).with_name('check-app-bundle.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bundle checks ')
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Spaced Path.app'
        self.contents = self.app / 'Contents'
        self.resources = self.contents / 'Resources' / 'Bimeron_BimeronApp.bundle'
        self.executable = self.contents / 'MacOS' / 'Bimeron'
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 0, 0, 0, 0))
        self.executable.chmod(0o755)
        self.info = dict(CFBundleIdentifier='org.bimeron.apple.dev', CFBundleName='Bimeron',
                         CFBundleDisplayName='Bimeron', CFBundleExecutable='Bimeron',
                         CFBundleIconFile='bimeron', CFBundlePackageType='APPL')
        self.write_info()
        (self.contents / 'PkgInfo').write_bytes(b'APPL????')
        for relative in ('bimeron.icns', 'Bimeron_BimeronApp.bundle/bimeron.icns',
                         'Bimeron_BimeronApp.bundle/blue-64.png',
                         'Bimeron_BimeronApp.bundle/menu-disconnected-44.png'):
            path = self.contents / 'Resources' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'synthetic resource')
        for language in ('en', 'ru'):
            path = self.strings(language)
            path.parent.mkdir()
            path.write_text('/* Fixture */ "Profiles" = "Profiles";\n"Quote" = "A \\"quote\\"";\n', encoding='utf-8')

    def strings(self, language):
        return self.resources / (language + '.lproj') / 'Localizable.strings'

    def write_info(self):
        (self.contents / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def check(self):
        checker.check_bundle(self.app)

    def test_valid_spaced_path(self):
        self.check()

    def test_plist_strings_formats(self):
        for format in (plistlib.FMT_XML, plistlib.FMT_BINARY):
            with self.subTest(format=format):
                self.strings('ru').write_bytes(plistlib.dumps({'Profiles': 'Профили', 'Quote': 'Цитата'}, fmt=format))
                self.check()

    def test_utf16_strings(self):
        self.strings('ru').write_text('"Profiles" = "Профили"; "Quote" = "Цитата";', encoding='utf-16')
        self.check()

    def test_identity_fields(self):
        for key in self.info:
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = '../wrong'
                self.write_info()
                with self.assertRaisesRegex(ValueError, key):
                    self.check()
                self.info[key] = original
        self.write_info()

    def test_missing_packaged_files(self):
        for path in (self.executable, self.contents / 'Resources' / 'bimeron.icns',
                     self.resources / 'bimeron.icns', self.resources / 'blue-64.png',
                     self.resources / 'menu-disconnected-44.png', self.strings('en'), self.strings('ru')):
            with self.subTest(path=path):
                data = path.read_bytes()
                path.unlink()
                with self.assertRaises((ValueError, OSError)):
                    self.check()
                path.write_bytes(data)
                if path == self.executable:
                    path.chmod(0o755)

    def test_executable_bit_is_required(self):
        self.executable.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'permission'):
            self.check()

    def test_executable_text_truncation_and_dylib_rejected(self):
        for data in (b'#!/bin/sh\nexit 0\n', b'\xcf\xfa\xed\xfe',
                     struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 6, 0, 0, 0, 0)):
            with self.subTest(data=data):
                self.executable.write_bytes(data)
                with self.assertRaises(ValueError):
                    self.check()

    def test_universal_header_and_bad_slice(self):
        thin = self.executable.read_bytes()
        header = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(thin), 0)
        self.executable.write_bytes(header + thin)
        self.check()
        self.executable.write_bytes(header + b'not Mach-O')
        with self.assertRaises(ValueError):
            self.check()

    def test_corrupt_plist_and_package_type(self):
        (self.contents / 'Info.plist').write_bytes(b'broken')
        with self.assertRaises(plistlib.InvalidFileException):
            self.check()
        self.write_info()
        (self.contents / 'PkgInfo').write_bytes(b'BNDL????')
        with self.assertRaisesRegex(ValueError, 'PkgInfo'):
            self.check()

    def test_empty_resource(self):
        (self.resources / 'blue-64.png').write_bytes(b'')
        with self.assertRaisesRegex(ValueError, 'empty'):
            self.check()

    def test_invalid_strings_and_parity(self):
        for text in ('', '"Profiles" = "";', '"Profiles" = "Профили"',
                     '"Profiles" = "Профили"; garbage',
                     '"Profiles" = "Профили"; "Profiles" = "Повтор";',
                     '"Different" = "Другой";'):
            with self.subTest(text=text):
                self.strings('ru').write_text(text, encoding='utf-8')
                with self.assertRaises(ValueError):
                    self.check()


if __name__ == '__main__':
    unittest.main()
