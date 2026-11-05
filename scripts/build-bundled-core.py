#!/usr/bin/env python3
"""Build one pinned, unsigned development daemon without touching the source checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

REVISION = '6b0d97a4ac96a903153a57d544751401b98d6909'
VERSION = '0.1.0-ba22-dev'
GO_VERSION = 'go1.26.9'


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--go', default='go')
    parser.add_argument('--git', default='git')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() not in ('arm64', 'x86_64'):
        parser.error('native macOS arm64 or x86_64 host required')
    env = dict(os.environ, GOTOOLCHAIN='local', GOPROXY='off', GOSUMDB='off',
               GOOS='darwin', GOARCH='arm64' if platform.machine() == 'arm64' else 'amd64',
               CGO_ENABLED='0', GOFLAGS='')
    if run(args.go, 'version', env=env).split()[2] != GO_VERSION:
        parser.error('Go 1.26.9 is required; supply an already installed toolchain with --go')
    source, output = args.source.resolve(), args.output.resolve()
    if run(args.git, '-C', str(source), 'rev-parse', REVISION + '^{commit}') != REVISION:
        parser.error('pinned source object unavailable')
    output.mkdir(parents=True, exist_ok=True)
    binary = output / 'bimeron-core'
    with tempfile.TemporaryDirectory(prefix='bimeron-core-source-') as temporary:
        checkout = Path(temporary) / 'source'
        subprocess.run([args.git, 'clone', '--shared', '--no-checkout', '--no-hardlinks', str(source), str(checkout)], check=True)
        subprocess.run([args.git, '-C', str(checkout), 'checkout', '--detach', REVISION], check=True)
        subprocess.run([args.go, 'build', '-mod=readonly', '-trimpath', '-buildvcs=true',
                        '-ldflags=-buildid= -X bimeron/core.Version=' + VERSION,
                        '-o', str(binary), './cmd/bimeron'], cwd=checkout, env=env, check=True)
        for name in ('LICENSE', 'THIRD_PARTY_NOTICES.txt'):
            (output / name).write_bytes((checkout / name).read_bytes())
    metadata = json.loads(run(str(binary), 'version'))
    if (metadata.get('revision') != REVISION or metadata.get('modified') is not False
            or metadata.get('platform') != 'darwin' or metadata.get('go_version') != GO_VERSION
            or metadata.get('version') != VERSION or metadata.get('architecture') != env['GOARCH']):
        raise SystemExit('built Core metadata does not match pinned recipe')
    run(str(binary), 'capabilities')
    metadata.update(sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    provenance='local-development-untrusted', production_shipping=False,
                    metadata_authenticated=False, owner_uid=os.getuid())
    subprocess.run(['python3', str(Path(__file__).parent / 'core-install/build.py'),
                    '--binary', str(binary), '--sha256', metadata['sha256'], '--version', VERSION,
                    '--revision', REVISION, '--architecture', platform.machine(),
                    '--owner-uid', str(os.getuid()), '--output', str(output / 'Install Core.pkg')], check=True)
    metadata['package_sha256'] = hashlib.sha256((output / 'Install Core.pkg').read_bytes()).hexdigest()
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()
