#!/usr/bin/env python3
"""Generate synthetic local packaging vectors from trusted source-built ZIPs; never execute them."""
import hashlib
import io
import json
import pathlib
import struct
import sys
import warnings
import zipfile
import zlib

source, output = map(pathlib.Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
index = []
PREFIX = b'BIMERON.APPLE.CORE.VERSION/v1\0'


def write(arch, label, data, accept=False):
    name = f'{arch}-{label}.zip'
    (output / name).write_bytes(data)
    index.append(dict(file=name, arch=arch, accept=accept, sha256=hashlib.sha256(data).hexdigest()))


def pack(entries):
    target = io.BytesIO()
    with warnings.catch_warnings(), zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        warnings.simplefilter('ignore', UserWarning)
        for name, data, mode in entries:
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    return target.getvalue()


def change_first_deflate(data, trailing):
    """Insert bytes after EOS or remove the final stream byte, preserving ZIP offsets."""
    end = data.rfind(b'PK\x05\x06')
    directory = struct.unpack_from('<I', data, end + 16)[0]
    count = struct.unpack_from('<H', data, end + 10)[0]
    local = struct.unpack_from('<I', data, directory + 42)[0]
    compressed = struct.unpack_from('<I', data, directory + 20)[0]
    assert struct.unpack_from('<H', data, directory + 10)[0] == 8
    payload_end = local + 30 + sum(struct.unpack_from('<HH', data, local + 26)) + compressed
    delta = len(trailing) if trailing else -1
    cut = payload_end if trailing else payload_end - 1
    modified = bytearray(data[:cut] + trailing + data[cut + (0 if trailing else 1):])
    p = directory
    for i in range(count):
        n, e, c = struct.unpack_from('<HHH', data, p + 28)
        old_local = struct.unpack_from('<I', data, p + 42)[0]
        struct.pack_into('<I', modified, p + delta + 42, old_local + (delta if old_local >= cut else 0))
        if i == 0:
            struct.pack_into('<I', modified, p + delta + 20, compressed + delta)
        p += 46 + n + e + c
    struct.pack_into('<I', modified, end + delta + 16, directory + delta)
    flags = struct.unpack_from('<H', data, directory + 8)[0]
    if flags & 8:
        descriptor = payload_end + delta
        signed = modified[descriptor:descriptor + 4] == b'PK\x07\x08'
        struct.pack_into('<I', modified, descriptor + (8 if signed else 4), compressed + delta)
    else:
        struct.pack_into('<I', modified, local + 18, compressed + delta)
    return modified


def directory_records(data):
    end = data.rfind(b'PK\x05\x06')
    p = struct.unpack_from('<I', data, end + 16)[0]
    result = []
    for _ in range(struct.unpack_from('<H', data, end + 10)[0]):
        n, e, c = struct.unpack_from('<HHH', data, p + 28)
        result.append((p, data[p + 46:p + 46 + n]))
        p += 46 + n + e + c
    return result


def change_mode(data, name, creator, attrs):
    p = next(p for p, n in directory_records(data) if n.decode() == name)
    modified = bytearray(data)
    modified[p + 5] = creator
    struct.pack_into('<I', modified, p + 38, attrs)
    return modified


def add_directory_bytes(data, extra):
    end = data.rfind(b'PK\x05\x06')
    modified = bytearray(data[:end] + extra + data[end:])
    size = struct.unpack_from('<I', data, end + 12)[0]
    struct.pack_into('<I', modified, end + len(extra) + 12, size + len(extra))
    return modified


def add_zip64_extra(data, values, *, malformed=False, duplicate=False):
    p, _ = directory_records(data)[0]
    n, e = struct.unpack_from('<HH', data, p + 28)
    fields = b''.join(struct.pack('<Q', value) for value in values)
    extra = struct.pack('<HH', 1, len(fields) + (1 if malformed else 0)) + fields
    if duplicate: extra += struct.pack('<HH', 1, 0)
    insert = p + 46 + n + e
    modified = bytearray(data[:insert] + extra + data[insert:])
    struct.pack_into('<H', modified, p + 30, e + len(extra))
    end = data.rfind(b'PK\x05\x06')
    size = struct.unpack_from('<I', data, end + 12)[0]
    struct.pack_into('<I', modified, end + len(extra) + 12, size + len(extra))
    return modified


for arch in ('amd64', 'arm64'):
    original = (source / f'bimeron-v0.1.0-beta.1-macos-{arch}.zip').read_bytes()
    write(arch, 'original', original, True)
    end = original.rfind(b'PK\x05\x06')
    count = struct.unpack_from('<H', original, end + 10)[0]
    directory_size, directory_offset = struct.unpack_from('<II', original, end + 12)
    extended = struct.pack('<IQHHIIQQQQ', 0x06064b50, 44, 45, 45, 0, 0, count, count, directory_size, directory_offset)
    locator = struct.pack('<IIQI', 0x07064b50, 0, end, 1)
    trailer = bytearray(original[end:])
    struct.pack_into('<HHII', trailer, 8, 65535, 65535, 0xffffffff, 0xffffffff)
    write(arch, 'zip64-end', original[:end] + extended + locator + trailer, True)

    with zipfile.ZipFile(io.BytesIO(original)) as z:
        entries = [(f.filename, z.read(f), f.external_attr >> 16) for f in z.infolist()]
    binary_index = next(i for i, e in enumerate(entries) if e[0].endswith('/bimeron'))
    name, binary, mode = entries[binary_index]
    repacked = pack(entries)
    write(arch, 'repacked', repacked, True)
    parent_name = f'macos-{arch}/'
    parent_zip = pack(entries + [(parent_name, b'', 0o40755)])
    notice_name_text = parent_name + 'LICENSE'
    for creator in (3, 19):
        for label, path, attrs in [
            ('unix-dos-dir', name, 0x81ed0010),
            ('unix-dos-readonly', name, 0x81ed0001),
            ('unix-unknown-type', name, 0x31ed0000),
            ('unix-no-type', name, 0x01ed0000),
            ('unix-special-permissions', name, 0x8fed0000),
            ('unix-notice-dos-dir', notice_name_text, 0x81a40010),
            ('unix-notice-unknown', notice_name_text, 0xf1a40010),
            ('unix-parent-regular', parent_name, 0x81ed0010),
            ('unix-parent-unknown', parent_name, 0x31ed0000),
        ]:
            write(arch, f'mode-{creator}-{label}', change_mode(parent_zip if path == parent_name else repacked, path, creator, attrs), True)
        for kind in (0x1000, 0x2000, 0x4000, 0x6000, 0xa000, 0xc000):
            write(arch, f'mode-{creator}-binary-special-{kind:x}', change_mode(repacked, name, creator, ((kind | 0o755) << 16) | 0x10))
        for kind in (0x4000, 0xa000):
            write(arch, f'mode-{creator}-notice-special-{kind:x}', change_mode(repacked, notice_name_text, creator, (kind | 0o644) << 16))
        for kind in (0x1000, 0xa000):
            write(arch, f'mode-{creator}-parent-special-{kind:x}', change_mode(parent_zip, parent_name, creator, (kind | 0o755) << 16))
    for creator in (0, 11, 14):
        for label, path, attrs, accept in [
            ('dos-binary-regular', name, 0x81ed0000, False),
            ('dos-binary-directory', name, 0x81ed0010, False),
            ('dos-notice-regular', notice_name_text, 0xa1a40000, True),
            ('dos-notice-directory', notice_name_text, 0x81a40010, False),
            ('dos-notice-readonly', notice_name_text, 0xa1a40001, True),
            ('dos-parent-suffix', parent_name, 0xa1ed0000, True),
            ('dos-parent-directory', parent_name, 0x81ed0011, True),
        ]:
            write(arch, f'mode-{creator}-{label}', change_mode(parent_zip if path == parent_name else repacked, path, creator, attrs), accept)
    for creator in (7, 255):
        for label, path, accept in [('binary', name, False), ('notice', notice_name_text, True), ('parent', parent_name, True)]:
            write(arch, f'mode-{creator}-unknown-{label}', change_mode(parent_zip if path == parent_name else repacked, path, creator, 0xa1ed0010), accept)

    # Concrete container leniencies in pinned Go's readDirectoryEnd/readDirectoryHeader.
    repacked_end = repacked.rfind(b'PK\x05\x06')
    repacked_records = directory_records(repacked)
    for label, offset, fmt, value, accept in [
        ('eocd-disks', repacked_end + 4, '<I', 0x00020001, True),
        ('eocd-count-this-disk', repacked_end + 8, '<H', 0xffff, True),
        ('eocd-count-mismatch', repacked_end + 10, '<H', 4, False),
        ('eocd-short-directory-size', repacked_end + 12, '<I', struct.unpack_from('<I', repacked, repacked_end + 12)[0] - 1, True),
        ('eocd-long-directory-size', repacked_end + 12, '<I', struct.unpack_from('<I', repacked, repacked_end + 12)[0] + 1, False),
        ('eocd-truncated-comment', repacked_end + 20, '<H', 1, False),
        ('central-disk-number', repacked_records[0][0] + 34, '<H', 9, True),
    ]:
        modified = bytearray(repacked); struct.pack_into(fmt, modified, offset, value)
        write(arch, label, modified, accept)
    for label, trailing, accept in [('eocd-trailing', b'X', True), ('eocd-second-window', b'X' * 2048, True), ('eocd-window-edge', b'X' * (65 * 1024 - 22), True), ('eocd-outside-window', b'X' * (65 * 1024 - 21), False), ('eocd-truncated-last-signature', struct.pack('<I', 0x06054b50) + b'\0' * 16 + b'\x01\0', False)]:
        write(arch, label, repacked + trailing, accept)
    write(arch, 'central-padding', add_directory_bytes(repacked, b'padding'), True)
    malformed_header = bytearray(46); struct.pack_into('<I', malformed_header, 0, 0x02014b50); struct.pack_into('<I', malformed_header, 42, 0xffffffff)
    write(arch, 'central-malformed-extra-header', add_directory_bytes(repacked, malformed_header), True)
    write(arch, 'relative-prefix', b'prefix' + repacked, True)
    prefix = b'prefix'; modified = bytearray(prefix + repacked)
    struct.pack_into('<I', modified, repacked_end + len(prefix) + 16, repacked_records[0][0] + len(prefix))
    write(arch, 'prefix-bad-local-offsets', modified)
    for p, _ in repacked_records:
        offset = struct.unpack_from('<I', repacked, p + 42)[0]
        struct.pack_into('<I', modified, p + len(prefix) + 42, offset + len(prefix))
    write(arch, 'absolute-prefix', modified, True)

    zip64 = original[:end] + extended + locator + trailer
    for label, offset, fmt, value, accept in [
        ('zip64-ignored-record-size', end + 4, '<Q', 0, True),
        ('zip64-ignored-disks', end + 16, '<Q', 0xffffffffffffffff, True),
        ('zip64-ignored-this-disk-count', end + 24, '<Q', 0xffffffffffffffff, True),
        ('zip64-count-low-bits', end + 32, '<Q', count + 65536, True),
        ('zip64-count-mismatch', end + 32, '<Q', count + 1, False),
        ('zip64-size-overflow', end + 40, '<Q', 0xffffffffffffffff, False),
        ('zip64-offset-overflow', end + 48, '<Q', 0xffffffffffffffff, False),
        ('zip64-locator-negative', end + 56 + 8, '<Q', 0xffffffffffffffff, False),
        ('zip64-locator-outside', end + 56 + 8, '<Q', 0x7fffffffffffffff, False),
        ('zip64-locator-disk', end + 56 + 4, '<I', 1, False),
    ]:
        modified = bytearray(zip64); struct.pack_into(fmt, modified, offset, value)
        write(arch, label, modified, accept)
    classic = add_directory_bytes(repacked, b'X' * (65535 - struct.unpack_from('<I', repacked, repacked_end + 12)[0]))
    write(arch, 'classic-size-zip64-sentinel-without-locator', classic, True)
    for sentinel, accept in [(65535, True), (0xffffffff, False)]:
        modified = bytearray(zip64)
        struct.pack_into('<HHII', modified, end + 76 + 8, count, count, sentinel, directory_offset)
        write(arch, f'zip64-size-trigger-{sentinel}', modified, accept)

    first = repacked_records[0][0]
    uncompressed, compressed, local_offset = struct.unpack_from('<I', repacked, first + 24)[0], struct.unpack_from('<I', repacked, first + 20)[0], struct.unpack_from('<I', repacked, first + 42)[0]
    for label, values, malformed, duplicate, needs, accept in [
        ('zip64-entry', [uncompressed, compressed, local_offset], False, False, True, True),
        ('zip64-entry-duplicate', [uncompressed, compressed, local_offset], False, True, True, True),
        ('zip64-entry-short', [uncompressed, compressed], False, False, True, False),
        ('zip64-entry-truncated-extra', [uncompressed, compressed, local_offset], True, False, True, False),
        ('zip64-entry-ignored-truncated-extra', [], True, False, False, True),
        ('zip64-entry-negative-offset', [uncompressed, compressed, 0xffffffffffffffff], False, False, True, False),
    ]:
        modified = add_zip64_extra(repacked, values, malformed=malformed, duplicate=duplicate)
        if needs:
            for offset in (20, 24, 42): struct.pack_into('<I', modified, first + offset, 0xffffffff)
        write(arch, label, modified, accept)

    # SectionReader caps actual reads at underlying EOF; Go flate can reach EOS
    # before a large declared compressed size, including signed ZIP64 conversions.
    for label, compressed_size, accept in [
        ('zip64-compressed-beyond-file', len(repacked) + 1, True),
        ('zip64-compressed-intmax', 0x7fffffffffffffff, True),
        ('zip64-compressed-negative-one', 0xffffffffffffffff, True),
        ('zip64-compressed-minint', 0x8000000000000000, True),
    ]:
        modified = add_zip64_extra(repacked, [uncompressed, compressed_size, local_offset])
        for offset in (20, 24, 42): struct.pack_into('<I', modified, first + offset, 0xffffffff)
        write(arch, label, modified, accept)

    for label, base in [('descriptor', original), ('no-descriptor', repacked)]:
        write(arch, 'deflate-trailing-' + label, change_first_deflate(base, b'X'), True)
        write(arch, 'deflate-truncated-' + label, change_first_deflate(base, b''))
    target = io.BytesIO()
    with zipfile.ZipFile(target, 'w') as z:
        for n, content, permissions in entries:
            info = zipfile.ZipInfo(n); info.create_system = 3; info.external_attr = permissions << 16
            z.writestr(info, content)
    write(arch, 'stored', target.getvalue(), True)
    write(arch, 'missing', pack(entries[:binary_index] + entries[binary_index + 1:]))
    write(arch, 'duplicate', pack(entries + [entries[0]]))
    write(arch, 'traversal', pack(entries + [('../escape', b'x', 0o100644)]))
    write(arch, 'malformed', b'not a zip')
    # Corrupt authenticated ZIP metadata/data independently of the manifest hash.
    central = original.index(b'PK\x01\x02')
    local = struct.unpack_from('<I', original, central + 42)[0]
    for label, offset, fmt, value in [('encrypted', central + 8, '<H', 1), ('compression', central + 10, '<H', 99), ('crc', central + 16, '<I', 0), ('bad-local-offset', central + 42, '<I', 0xfffffffe), ('bad-local-header', local, '<I', 0), ('oversized-binary', central + 24, '<I', 268435457)]:
        modified = bytearray(original); struct.pack_into(fmt, modified, offset, value)
        write(arch, label, modified)
    # Go uses central metadata; local fields other than signature and lengths are ignored.
    for label, offset, fmt, value in [('local-name', local + 30, '<B', original[local + 30] ^ 1), ('local-method', local + 8, '<H', 99), ('local-flags', local + 6, '<H', 0xffff)]:
        modified = bytearray(original); struct.pack_into(fmt, modified, offset, value)
        write(arch, label, modified, True)
    descriptor = local + 30 + sum(struct.unpack_from('<HH', original, local + 26)) + struct.unpack_from('<I', original, central + 20)[0]
    assert original[descriptor:descriptor + 4] == b'PK\x07\x08'
    modified = bytearray(original); modified[descriptor + 4] ^= 1
    write(arch, 'descriptor-crc', modified)

    # Put a stored notice and descriptor at true EOF inside the EOCD comment so
    # short descriptors cannot accidentally read bytes from the next ZIP header.
    notice_central = central
    while True:
        n, e, c = struct.unpack_from('<HHH', original, notice_central + 28)
        notice_name = original[notice_central + 46:notice_central + 46 + n]
        if notice_name.endswith(b'/LICENSE'): break
        notice_central += 46 + n + e + c
    notice_crc = zlib.crc32(b'x')
    for label, signature, wide, descriptor_bytes, accept in [
        ('descriptor-signed', True, False, None, True),
        ('descriptor-unsigned', False, False, None, True),
        ('descriptor-zip64-signed', True, True, None, True),
        ('descriptor-zip64-unsigned', False, True, None, True),
        ('descriptor-signed-short', True, False, 15, False),
        ('descriptor-unsigned-short', False, False, 11, False),
        ('descriptor-zip64-short-signed', True, True, 16, True),
        ('descriptor-zip64-short-unsigned', False, True, 12, True),
        ('descriptor-empty', False, False, 0, False),
        ('descriptor-four-bytes', False, False, 4, False),
        ('descriptor-unsigned-bad-crc', False, False, -1, False),
        ('descriptor-zip64-bad-crc', True, True, -1, False),
        ('descriptor-ignored-sizes', True, False, -2, True),
        ('no-descriptor-zero-crc', False, False, -3, True),
    ]:
        checksum = notice_crc ^ (1 if descriptor_bytes == -1 else 0)
        sizes = (0xffffffffffffffff, 0xffffffffffffffff) if wide else (0xffffffff, 0xffffffff)
        frame = (b'PK\x07\x08' if signature else b'') + struct.pack('<I', checksum) + struct.pack('<QQ' if wide else '<II', *sizes)
        if descriptor_bytes is not None and descriptor_bytes >= 0: frame = frame[:descriptor_bytes]
        if descriptor_bytes == -3: frame = b''
        flags = 0 if descriptor_bytes == -3 else 8
        header = struct.pack('<IHHHHHIIIHH', 0x04034b50, 20, flags, 0, 0, 0, 0, 0, 0, len(notice_name), 0)
        tail = header + notice_name + b'x' + frame
        modified = bytearray(original)
        struct.pack_into('<HH', modified, notice_central + 8, flags, 0)
        struct.pack_into('<III', modified, notice_central + 16, 0 if descriptor_bytes == -3 else notice_crc, 1, 1)
        struct.pack_into('<I', modified, notice_central + 42, len(original))
        struct.pack_into('<H', modified, end + 20, len(tail))
        write(arch, label, modified + tail, accept)
    write(arch, 'truncated', original[:-1])
    for label, extra_name in [('absolute', '/escape'), ('backslash', 'macos-' + arch + '\\LICENSE'), ('alias', f'macos-{arch}/./LICENSE')]:
        write(arch, label, pack(entries + [(extra_name, b'x', 0o100644)]))
    for label, replacement in [('symlink', (name, binary, 0o120755)), ('special', (name, binary, 0o020755)), ('no-exec', (name, binary, 0o100644)), ('empty', (name, b'', mode))]:
        changed = entries.copy(); changed[binary_index] = replacement
        write(arch, label, pack(changed))
    for label, old, new in [('record-missing', PREFIX, b'X' + PREFIX[1:]), ('record-malformed', b'012:0.1.0-beta.1', b'999:0.1.0-beta.1'), ('version', b'0.1.0-beta.1', b'0.1.0-beta.2'), ('dirty', b'vcs.modified=false', b'vcs.modified=true '), ('revision', b'e8de4354e2dc5d0364a2fb93119c50971cdf8a5c', b'0' * 40), ('os', b'GOOS=darwin', b'GOOS=linux '), ('arch', b'GOARCH=' + arch.encode(), b'GOARCH=other'), ('vcs', b'vcs=git', b'vcs=svn'), ('trimpath', b'-trimpath=true', b'-trimpath=fals')]:
        assert old in binary, label
        changed = entries.copy(); changed[binary_index] = (name, binary.replace(old, new), mode)
        write(arch, label, pack(changed))
    # Mutate actual segment and section fields with size-preserving writes.
    commands = struct.unpack_from('<I', binary, 16)[0]
    p = 32
    sections = []
    text = None
    for _ in range(commands):
        cmd, size = struct.unpack_from('<II', binary, p)
        if cmd == 0x19:
            segment = binary[p + 8:p + 24].rstrip(b'\0')
            if segment == b'__TEXT': text = p
            for i in range(struct.unpack_from('<I', binary, p + 64)[0]):
                s = p + 72 + i * 80
                sections.append(s)
        p += size
    build = next(s for s in sections if binary[s:s + 16].rstrip(b'\0') == b'__go_buildinfo')
    build_off = struct.unpack_from('<I', binary, build + 48)[0]
    build_size = struct.unpack_from('<Q', binary, build + 40)[0]
    q = build_off + 32

    def read_string():
        global q
        n = 0; shift = 0
        while True:
            byte = binary[q]; q += 1
            n |= (byte & 127) << shift
            if byte < 128: break
            shift += 7
        result = binary[q:q + n]; q += n
        return result

    go_version, module = read_string(), read_string()

    def encoded_string(value):
        n = len(value); result = bytearray()
        while n >= 128:
            result.append((n & 127) | 128); n >>= 7
        return bytes(result + bytes([n])) + value

    for label, old, new, accept in [
        ('quoted-provenance', b'build\tGOOS=darwin\n', b'build\t"GOOS"="darwin"\n', True),
        ('escaped-provenance', b'build\tGOOS=darwin\n', b'build\t"GO\\x4fS"=`darwin`\n', True),
        ('duplicate-provenance', b'build\t-compiler=gc\n', b'build\t"GOOS"=darwin\n', False),
        ('missing-clean', b'build\tvcs.modified=false\n', b'', False),
        ('bad-module', b'mod\tbimeron\t', b'mod\tbimeron\t\t\t', False),
    ]:
        changed_module = module.replace(old, new)
        assert changed_module != module, label
        changed_module = changed_module.replace(b'build\tCGO_ENABLED=0\n', b'')
        contents = binary[build_off:build_off + 32] + encoded_string(go_version) + encoded_string(changed_module)
        assert len(contents) <= build_size, label
        modified = bytearray(binary)
        modified[build_off:build_off + build_size] = contents.ljust(build_size, b'\0')
        changed = entries.copy(); changed[binary_index] = (name, modified, mode)
        write(arch, label, pack(changed), accept)
    ro = next(s for s in sections if binary[s:s + 16].rstrip(b'\0') == b'__rodata')
    for label, offset, fmt, value in [('cpu', 4, '<I', 0), ('type', 12, '<I', 1), ('writable', text + 60, '<I', 3), ('unreadable', text + 60, '<I', 4), ('oversized-record', ro + 40, '<Q', 64 * 1024 * 1024 + 1), ('section-offset', ro + 48, '<I', 0xffffffff), ('section-address', ro + 32, '<Q', 0)]:
        modified = bytearray(binary); struct.pack_into(fmt, modified, offset, value)
        changed = entries.copy(); changed[binary_index] = (name, modified, mode)
        write(arch, label, pack(changed))
    modified = bytearray(binary)
    ro_offset = struct.unpack_from('<I', binary, ro + 48)[0]
    modified[ro_offset:ro_offset + len(PREFIX)] = PREFIX
    changed = entries.copy(); changed[binary_index] = (name, modified, mode)
    write(arch, 'duplicate-record', pack(changed))
    changed = entries.copy(); changed.append((f'macos-{arch}/', b'', 0o40755))
    write(arch, 'parent', pack(changed), True)
    changed = entries.copy(); changed.append((f'macos-{arch}/', b'x', 0o40755))
    write(arch, 'parent-nonempty', pack(changed))
    notice = next(i for i, e in enumerate(entries) if e[0].endswith('/LICENSE'))
    changed = entries.copy(); changed[notice] = (entries[notice][0], b'x' * (4194304 + 1), 0o100644)
    write(arch, 'oversized-notice', pack(changed))
index.sort(key=lambda item: item['file'])
(output / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
