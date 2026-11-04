# Apple core release manifest consumer

Implements the additive schema 1 contract for bimeron/bimeron-apple#13. No release key or approved candidate is embedded.

`AppleCoreRelease.verifyManifest` requires independently supplied trusted 32-byte Ed25519 public key bytes, explicit local candidate tag and full source revision approval, current plain-triplet app version, channel, and target architecture. It authenticates the original bytes before JSON parsing. The returned `AppleCoreReleaseManifest` describes the selected archive; it does not certify archive bytes. `verifyArchive` checks complete Data size and SHA256 before parsing, then validates ZIP packaging and static Mach-O/Go provenance before returning `AppleCoreReleaseVerifiedArchive`. Neither type has a public initializer.

Manifest input is limited to 65,536 bytes including its final LF. The signature is exactly 89 bytes: canonical standard base64 encoding of a 64-byte signature plus LF. JSON must be valid UTF8, end immediately with object close plus LF, and have exact contract fields with no duplicate keys (including escaped or case aliases). Both architecture descriptors must satisfy the contract. Every archive size must be positive and at most 268,435,456 bytes. Callers must bound reads before allocating downloaded Data; these APIs perform no downloads.

Schema, product, key ID, semantic core version/tag, channel, full revision, app range, IPC 1, profile format 1, daemon session guards, explicit reviewed status and local approval all fail closed. App range versions are plain numeric triplets; core versions permit valid prerelease identifiers, without build metadata. Integer JSON fields require unsigned integer tokens: fractional and exponent forms
are rejected before decoding to prevent floating-point rounding into accepted values.
Channel must be beta for a prerelease and stable otherwise. Version strings are
bounded to 128 UTF8 bytes. App triplet components must fit UInt64; larger app components fail closed. Core SemVer numeric components use canonical decimal strings, allowing values above UInt64 within the 128-byte total bound. App triplet ordering also uses decimal length/value comparisons without integer conversion.

The packaging gate requires three regular nonempty files at exactly
`macos-<arch>/{bimeron,LICENSE,THIRD_PARTY_NOTICES.txt}`, with only the empty
expected parent directory optional. It rejects extra/aliased/duplicate paths,
links/special files, encryption, unsupported compression, corrupt CRC and bounded
size violations. Stored and raw-DEFLATE ZIP payloads are read in memory through
system zlib, never extracted. Central-directory metadata governs paths and
payload decoding; local-header names, flags and methods are not compared. The
bounded local header supplies only the lengths needed to locate payload bytes.
Flag-3 data descriptors require matching CRC with optional signature, following
the pinned Go reader; descriptor size words are ignored in favor of central
sizes. Without flag 3, zero central CRC means unspecified, as in Core. The binary must have executable permissions and be
a thin executable Mach-O of the selected CPU. Its unique readable non-writable
`__TEXT` segment must contain one bounded `__rodata` section with consistent
file/virtual ranges and exactly one canonical ADR0032 version record equal to the
signed version. Go inline build information must declare Darwin, the selected
architecture, Git, exact signed source revision, explicit `vcs.modified=false`
and `-trimpath=true`. Duplicate decoded build settings fail closed. Linker flags
are not version evidence. Unsupported compiler formats fail closed.

The base consumer did not have this gate; this local change adds it under the
[local issue](local-apple-packaging-issue.md). See
[reproduction and evidence](local-apple-packaging-evidence.md).
Static embedded claims do not prove an honest builder, safe extraction or runtime
readiness. Independent trusted-key/candidate/review approval and independently
reviewed source derivation remain required before production acceptance. The
consumer never extracts, executes, installs, or accesses a daemon.

Tests use synthetic ephemeral Ed25519 keys and self-signed JSON only. The exact publisher synthetic signed vector is retained under `testdata/` and
verified for both architectures; its intentionally fake archive hashes are rejected.
It proves manifest parser/signature interoperability only, not real archive or
source provenance acceptance.
