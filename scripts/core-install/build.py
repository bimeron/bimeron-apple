#!/usr/bin/env python3
"""Build unsigned LOCAL DEV transport from explicitly supplied, untrusted bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile

BASE = Path(__file__).resolve().parent
CORE = '/Library/PrivilegedHelperTools/org.bimeron.core'
META = CORE + '.dev.json'
PLIST = '/Library/LaunchDaemons/org.bimeron.core.plist'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('binary', 'sha256', 'version', 'revision', 'architecture', 'owner-uid', 'output'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{64}', args.sha256):
        parser.error('sha256 must be 64 lowercase hex digits')
    if not re.fullmatch('[1-9][0-9]*', args.owner_uid) or not 501 <= int(args.owner_uid) <= 2147483647:
        parser.error('owner UID must be a local human UID from 501 to 2147483647')
    if args.architecture not in ('arm64', 'x86_64'):
        parser.error('architecture must be arm64 or x86_64 (asserted, not inspected)')
    for value in (args.version, args.revision):
        if not re.fullmatch('[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}', value):
            parser.error('invalid version/revision')
    source, output = Path(args.binary), Path(args.output)
    # Reject symlinks in every supplied path component, including dangling links.
    for path in (source, output):
        if not path.is_absolute() or '..' in path.parts:
            parser.error('paths must be absolute and contain no traversal')
        if any(p.is_symlink() for p in (path, *path.parents)):
            parser.error('symlink path')
    if output.suffix != '.pkg' or not output.parent.is_dir() or os.path.lexists(output):
        parser.error('output must be a new .pkg in an existing directory')
    parent_stat = output.parent.stat()
    if parent_stat.st_uid != os.getuid() or parent_stat.st_mode & 0o022:
        parser.error('output directory must be owned by the builder and not group/other writable')
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(source, flags), 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            parser.error('binary must be a regular file')
        data = stream.read()
    if not data or digest(data) != args.sha256:
        parser.error('binary hash mismatch or empty binary')
    metadata = dict(schema_version=1, provenance='local-development-untrusted',
                    binary_path=CORE, sha256=args.sha256, expected_version=args.version,
                    expected_revision=args.revision, expected_architecture=args.architecture,
                    owner_uid=int(args.owner_uid), metadata_authenticated=False)
    plist = dict(Label='org.bimeron.core', ProgramArguments=[CORE, 'daemon'],
                 UserName='root', GroupName='wheel', RunAtLoad=True,
                 EnvironmentVariables=dict(BIMERON_CONTROL_UID=args.owner_uid,
                                           PATH='/usr/bin:/bin:/usr/sbin:/sbin'))
    payload = {CORE: (data, 0o755), META: ((json.dumps(metadata, indent=2) + '\n').encode(), 0o644),
               PLIST: (plistlib.dumps(plist), 0o644)}
    with tempfile.TemporaryDirectory(prefix='bimeron-local-dev-') as temporary:
        stage = Path(temporary) / 'payload'
        scripts = Path(temporary) / 'scripts'
        scripts.mkdir()
        for name, (content, mode) in payload.items():
            path = stage / name.lstrip('/')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(mode)
        for path in (stage, *[p for p in stage.rglob('*') if p.is_dir()]):
            path.chmod(0o755)
        common = '#!/bin/sh\nset -eu\nPATH=/usr/bin:/bin:/usr/sbin:/sbin\nexport PATH\n' + (BASE / 'guards.sh').read_text()
        common += '\n[ "$(/usr/bin/id -u)" = 0 ] || fail "requires Installer root"\n[ "${3:-}" = / ] || fail "only live system target supported"\n'
        common += f'''account=$(/usr/bin/dscl . -search /Users UniqueID {args.owner_uid})
[ "$(printf '%s\\n' "$account" | /usr/bin/awk 'NF {{n++}} END {{print n+0}}')" = 1 ] || fail "owner must resolve uniquely on target host"
name=$(printf '%s\\n' "$account" | /usr/bin/awk '{{print $1}}')
case "$name" in ''|_*|root|daemon|nobody) fail "system account" ;; esac
home=$(/usr/bin/dscl . -read "/Users/$name" NFSHomeDirectory)
case "$home" in 'NFSHomeDirectory: /Users/'*) ;; *) fail "owner must have a local human home" ;; esac
shell=$(/usr/bin/dscl . -read "/Users/$name" UserShell)
case "$shell" in 'UserShell: /usr/bin/false'|'UserShell: /bin/false'|*nologin*) fail "nonhuman account" ;; esac
'''
        pre = common + 'check_ancestry "" fresh\ncheck_absent ""\nif /bin/launchctl print system/org.bimeron.core >/dev/null 2>&1; then fail "service already registered"; fi\n'
        post = common + 'check_ancestry "" installed\n'
        for name, (content, mode) in payload.items():
            post += f"check_file '{name}' '{mode:o}' '{digest(content)}'\n"
        post += '/bin/launchctl bootstrap system /Library/LaunchDaemons/org.bimeron.core.plist\n'
        for name, content in (('preinstall', pre), ('postinstall', post)):
            path = scripts / name
            path.write_text(content)
            path.chmod(0o755)
        # Reserve output without overwriting a previous artifact. pkgbuild writes this file.
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        try:
            subprocess.run(['/usr/bin/pkgbuild', '--root', str(stage), '--scripts', str(scripts),
                        '--identifier', 'org.bimeron.core.local-development', '--version', '0.0.0',
                        '--install-location', '/', '--ownership', 'recommended', str(output)], check=True)
        except BaseException:
            output.unlink()
            raise
    print(json.dumps({'package': str(output), 'package_sha256': digest(output.read_bytes()),
                      'binary_sha256': args.sha256, 'provenance': metadata['provenance']}))


if __name__ == '__main__':
    main()
