# Local issue: authenticate Apple Core packaging and static provenance

Status: implemented locally; two P2 findings from review at `686415c` fixed locally;
new independent parent review pending. No remote issue.

Base consumer commit: `70e7f218c62d8ebcf04813e59d4fac3ecd5e95db`.
The base verifies manifest signatures and archive hashes but has no packaging or
static binary gate. The user explicitly authorized adding this missing gate after
that scope conflict was reported. This is a new gate, not an ldflags adaptation.

Acceptance: authenticate original bounded manifest bytes, require independent
public-key trust and exact local tag/revision approval plus reviewed policy, then
check archive size/SHA-256 before any ZIP parsing. Validate exact ZIP paths,
regular file types, executable permissions, bounded decompression and CRC, thin
Mach-O executable CPU, unique read-only retained version record, and Go
OS/architecture/Git revision/explicit clean/trimpath evidence. Reject malformed,
missing, duplicated, writable, oversized or mismatched evidence. Keep all trust
defaults absent. Never execute archived binaries.

The only new system dependency is macOS SDK zlib (`libz`), used for bounded raw
DEFLATE and CRC32. No package download or dependency installation is needed.
Integer readers use checked byte slices rather than unaligned native structs;
untrusted ranges are validated before allocation or conversion. ZIP64 size fields
are supported within the same overall archive limits. The Go metadata reader
supports the pinned compiler's inline 64-bit little-endian format, with Go string
quoting and duplicate decoded setting rejection. Older pointer-based Go build
metadata is unsupported and fails closed; compiler changes need fresh evidence.

No extraction, installation, daemon access, runtime readiness, network, real key,
production pin/candidate/review approval, remote issue/PR/CI, publishing or original
G/E/L modification is authorized by this local issue. Independent review and
production trust/source-derivation/readiness gates remain open.
