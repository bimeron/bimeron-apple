#!/usr/bin/env python3
"""Check synthetic fixture integrity only; never invoke Core or an adapter."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent
REQUIRED = {
    'A-BOM-CRLF-NOOP', 'A-BOM-CRLF-EDIT', 'A-UNKNOWN-NOOP', 'A-UNKNOWN-EDIT',
    'A-AMBIGUOUS-NOOP', 'A-AMBIGUOUS-RAW',
    'A-DISABLED-SHADOWTLS-NOOP', 'A-DISABLED-SHADOWTLS-EDIT',
    *('B-' + name for name in (
        'MISSING', 'VERSION-SUPPORTED', 'VERSION-UNSUPPORTED', 'VERSION-MALFORMED',
        'CAPABILITIES-SUPPORTED', 'CAPABILITIES-UNSUPPORTED', 'CAPABILITIES-MALFORMED',
        'VALIDATE-VALID', 'VALIDATE-INVALID', 'NONZERO-STDERR', 'TIMEOUT', 'CANCEL', 'TRUNCATED')),
    'C-REPEAT', 'C-ADOPT', 'C-IPC-LOSS', 'C-SWITCH', 'C-FAILED-STOP',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check(root):
    manifest = json.loads((root / 'manifest.json').read_text())
    require(manifest['schema_version'] == 1, 'Unsupported manifest version')
    scenarios = manifest['scenarios']
    ids = [s['id'] for s in scenarios]
    require(len(ids) == len(set(ids)) and REQUIRED <= set(ids), 'Missing or duplicate scenario IDs')
    hashes = manifest['sha256']
    actual = {str(p.relative_to(root)) for folder in ('config', 'cli', 'lifecycle')
              for p in (root / folder).rglob('*') if p.is_file()}
    require(actual == set(hashes), 'Untracked or missing fixture file')
    for relative, digest in hashes.items():
        path = (root / relative).resolve()
        require(path.is_relative_to(root.resolve()), 'Fixture path escapes root')
        require(hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'Hash mismatch: ' + relative)
    for scenario in scenarios:
        sid = scenario['id']
        require(scenario['owner'] == sid[0], 'Owner mismatch: ' + sid)
        require(scenario['status'] == 'adapter-test-pending' and scenario['expected'], 'Missing expectation/status')
        require(scenario['references'] and all(ref in manifest['references'] for ref in scenario['references']), 'Missing reference')
        require(scenario['fixture'] in hashes, 'Missing fixture link')
        data = (root / scenario['fixture']).read_bytes()
        if sid.startswith('A-'):
            require(scenario['expected_fixture'] in hashes, 'Missing expected byte file')
            expected = (root / scenario['expected_fixture']).read_bytes()
            if scenario['operation'] == 'edit':
                require(data.count(b'Name = Original') == 1, 'Ambiguous edit fixture')
                require(expected == data.replace(b'Name = Original', b'Name = Edited', 1), 'Edit changed unrelated bytes')
            else:
                require(expected == data, 'No-op/rejection changed bytes')
            if 'BOM-CRLF' in sid:
                require(data.startswith(b'\xef\xbb\xbf') and data.count(b'\xef\xbb\xbf') == 1, 'Invalid BOM fixture')
                require(b'\n' not in data.replace(b'\r\n', b'') and not data.endswith(b'\n'), 'Invalid CRLF/EOF fixture')
        elif sid.startswith('B-'):
            result = json.loads(data)
            require(result['kind'] == 'synthetic-process-result', 'Wrong process fixture kind')
            require(isinstance(result['stdout'], str) and isinstance(result['stderr'], str), 'Invalid streams')
            ended = result['termination'] == 'exited'
            require(result['termination'] in ('exited', 'spawn-error', 'timeout', 'cancelled'), 'Invalid termination')
            require((type(result['exit_code']) is int) if ended else result['exit_code'] is None, 'Exit/termination mismatch')
            require(type(result['output_complete']) is bool, 'Invalid completeness flag')
            require(result['decoded_observation'] is None or (ended and result['output_complete']), 'Incomplete result decoded')
            if sid == 'B-VALIDATE-VALID':
                require(result['exit_code'] == 0 and result['decoded_observation'] == 'valid', 'Invalid success result')
            if sid == 'B-TRUNCATED':
                require(not result['output_complete'], 'Truncation not represented')
        else:
            script = json.loads(data)
            require(script['kind'] == 'synthetic-lifecycle-script', 'Wrong lifecycle fixture kind')
            events, commands = script['events'], script['expected_commands']
            require(events and all(isinstance(event, str) for event in events), 'Invalid event script')
            if sid == 'C-SWITCH':
                require(events.index('observe-stop-pending') < events.index('observe-stopped') < events.index('observe-connected:B'), 'Switch observation order')
                require(commands == ['stop', 'start:B'] and script['expected_final_state'] == 'connected', 'Switch command order')
            if sid == 'C-FAILED-STOP':
                require('observe-stop-failed' in events and commands == ['stop'] and script['expected_final_state'] == 'cleanup-unconfirmed', 'Failed stop permits start')
            if sid == 'C-IPC-LOSS':
                require('observe-ipc-lost' in events and not commands and script['expected_final_state'] == 'unknown', 'IPC loss implies stopped')
            if sid == 'C-ADOPT':
                require(not commands and script['expected_final_state'] == 'connected', 'Adoption mutates session')
            if sid == 'C-REPEAT':
                require(commands == ['start:A', 'stop'] and script['expected_final_state'] == 'stopped', 'Repeated commands not coalesced')
    return len(scenarios), len(hashes)


def self_check():
    # Mutate isolated copies, including semantic corruption with a refreshed hash.
    for mutation in ('bytes', 'coverage', 'lifecycle'):
        with tempfile.TemporaryDirectory(prefix='acceptance-integrity-') as temporary:
            copy = Path(temporary) / 'fixtures'
            shutil.copytree(ROOT, copy)
            manifest_path = copy / 'manifest.json'
            manifest = json.loads(manifest_path.read_text())
            if mutation == 'bytes':
                with (copy / 'config/bom-crlf.input.conf').open('ab') as stream:
                    stream.write(b'corrupt')
            elif mutation == 'coverage':
                manifest['scenarios'].pop()
            else:
                relative = 'lifecycle/failed-stop.json'
                path = copy / relative
                script = json.loads(path.read_text())
                script['expected_commands'].append('start:B')
                path.write_text(json.dumps(script))
                manifest['sha256'][relative] = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
            try:
                check(copy)
            except ValueError:
                continue
            raise ValueError('Negative self-check accepted corruption: ' + mutation)
    print('PASS: rejected byte corruption, missing coverage, and unsafe lifecycle expectation')


if __name__ == '__main__':
    count, files = check(ROOT)
    print(f'PASS: {count} scenarios, {files} fixture files; offline integrity only')
    self_check()
