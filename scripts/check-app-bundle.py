#!/usr/bin/env python3
"""Check the assembled development app without launching it (stdlib only)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_macho(data):
    """Recognize an executable Mach-O header, including universal binaries."""
    magics = {b'\xce\xfa\xed\xfe': ('<', 28), b'\xcf\xfa\xed\xfe': ('<', 32),
              b'\xfe\xed\xfa\xce': ('>', 28), b'\xfe\xed\xfa\xcf': ('>', 32)}
    if data[:4] in magics:
        endian, size = magics[data[:4]]
        require(len(data) >= size, 'Truncated Mach-O header')
        require(struct.unpack_from(endian + 'I', data, 12)[0] == 2,
                'Mach-O file is not an executable')
        return
    fat = {b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
           b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True)}
    require(data[:4] in fat, 'Executable is not Mach-O')
    endian, wide = fat[data[:4]]
    require(len(data) >= 8, 'Truncated universal header')
    count = struct.unpack_from(endian + 'I', data, 4)[0]
    entry_size = 32 if wide else 20
    require(count > 0 and 8 + count * entry_size <= len(data),
            'Invalid universal architecture table')
    for index in range(count):
        offset, size = struct.unpack_from(endian + ('QQ' if wide else 'II'),
                                          data, 8 + index * entry_size + 8)
        require(offset >= 8 + count * entry_size and size > 0
                and offset + size <= len(data), 'Invalid universal slice bounds')
        slice_data = data[offset:offset + size]
        require(slice_data[:4] in magics, 'Universal slice is not Mach-O')
        check_macho(slice_data)


# SwiftPM may leave .strings as OpenStep text or convert them to a plist.
TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\r\n]*|"(?:[^"\\]|\\.)*"|[=;]', re.S)


def unquote(token):
    def escape(match):
        value = match.group(1)
        if value.startswith('U'):
            return chr(int(value[1:], 16))
        if value[0] in '01234567':
            return chr(int(value, 8))
        return {'n': '\n', 'r': '\r', 't': '\t', '"': '"', '\\': '\\'}.get(value, value)
    return re.sub(r'\\(U[0-9a-fA-F]{4}|[0-7]{1,3}|.)', escape, token[1:-1])


def read_strings(path):
    data = path.read_bytes()
    try:
        values = plistlib.loads(data)
    except plistlib.InvalidFileException:
        text = data.decode('utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig')
        tokens = []
        position = 0
        for match in TOKEN.finditer(text):
            require(match.start() == position, f'Invalid strings syntax: {path}')
            position = match.end()
            token = match.group()
            if not token.isspace() and not token.startswith(('/*', '//')):
                tokens.append(token)
        require(position == len(text) and len(tokens) % 4 == 0,
                f'Invalid strings syntax: {path}')
        values = {}
        for index in range(0, len(tokens), 4):
            key, equals, value, semicolon = tokens[index:index + 4]
            require(key.startswith('"') and value.startswith('"')
                    and equals == '=' and semicolon == ';', f'Invalid strings entry: {path}')
            key, value = unquote(key), unquote(value)
            require(key not in values, f'Duplicate strings key {key!r}: {path}')
            values[key] = value
    require(isinstance(values, dict) and values, f'Empty or invalid strings table: {path}')
    require(all(isinstance(key, str) and key.strip() and isinstance(value, str)
                and value.strip() for key, value in values.items()),
            f'Empty or invalid strings entry: {path}')
    return values


def nonempty(path):
    require(path.is_file() and path.stat().st_size > 0, f'Missing or empty file: {path}')


def check_bundle(app):
    contents = app / 'Contents'
    with (contents / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    require(isinstance(info, dict), 'Info.plist must be a dictionary')
    for key, expected in {'CFBundleIdentifier': 'org.bimeron.apple.dev',
                          'CFBundleName': 'Bimeron', 'CFBundleDisplayName': 'Bimeron',
                          'CFBundleExecutable': 'Bimeron', 'CFBundleIconFile': 'bimeron',
                          'CFBundlePackageType': 'APPL'}.items():
        require(info.get(key) == expected, f'Info.plist {key} must be {expected!r}')
    require((contents / 'PkgInfo').read_bytes() == b'APPL????', 'Invalid PkgInfo')
    executable = contents / 'MacOS' / info['CFBundleExecutable']
    nonempty(executable)
    require(os.access(executable, os.X_OK), f'Executable permission missing: {executable}')
    check_macho(executable.read_bytes())
    core = contents / 'MacOS' / 'bimeron-core'
    nonempty(core)
    require(os.access(core, os.X_OK), 'Bundled Core is not executable')
    check_macho(core.read_bytes())
    resources = contents / 'Resources'
    install = resources / 'CoreInstall'
    manifest = json.loads((install / 'manifest.json').read_text())
    require(manifest.get('revision') == 'baf3d0e1b061b6f1210b0d9aa040c9512fe646a1'
            and manifest.get('modified') is False and manifest.get('platform') == 'darwin'
            and manifest.get('go_version') == 'go1.26.9'
            and manifest.get('production_shipping') is False
            and manifest.get('metadata_authenticated') is False
            and manifest.get('provenance') == 'local-development-untrusted', 'Invalid development Core manifest')
    require(hashlib.sha256(core.read_bytes()).hexdigest() == manifest.get('sha256'), 'Bundled Core digest mismatch')
    helper = contents / 'MacOS' / 'bimeron-detach'
    nonempty(helper)
    require(os.access(helper, os.X_OK), 'Detach helper is not executable')
    check_macho(helper.read_bytes())
    require(hashlib.sha256(helper.read_bytes()).hexdigest() == manifest.get('detach_sha256'), 'Detach helper digest mismatch')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.txt'):
        nonempty(install / name)
    bundle = resources / 'Bimeron_BimeronApp.bundle'
    for path in (resources / 'bimeron.icns', bundle / 'bimeron.icns',
                 bundle / 'blue-64.png', bundle / 'menu-disconnected-44.png'):
        nonempty(path)
    tables = [read_strings(bundle / language / 'Localizable.strings')
              for language in ('en.lproj', 'ru.lproj')]
    require(tables[0].keys() == tables[1].keys(),
            'English and Russian localization keys differ: '
            f'English only: {sorted(tables[0].keys() - tables[1].keys())}; '
            f'Russian only: {sorted(tables[1].keys() - tables[0].keys())}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    try:
        check_bundle(args.app)
    except (OSError, ValueError, UnicodeError, plistlib.InvalidFileException) as error:
        print(f'App bundle check failed: {error}', file=sys.stderr)
        return 1
    print(f'App bundle valid: {args.app}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
