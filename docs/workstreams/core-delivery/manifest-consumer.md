# Apple core release manifest consumer

Implements the additive schema 1 contract for bimeron/bimeron-apple#13. No release key or approved candidate is embedded.

`AppleCoreRelease.verifyManifest` requires independently supplied trusted 32-byte Ed25519 public key bytes, explicit local candidate tag and full source revision approval, current plain-triplet app version, channel, and target architecture. It authenticates the original bytes before JSON parsing. The returned `AppleCoreReleaseManifest` describes the selected archive; it does not certify archive bytes. `verifyArchive` checks complete Data size and SHA256 and alone returns `AppleCoreReleaseVerifiedArchive`. Neither type has a public initializer.

Manifest input is limited to 65,536 bytes including its final LF. The signature is exactly 89 bytes: canonical standard base64 encoding of a 64-byte signature plus LF. JSON must be valid UTF8, end immediately with object close plus LF, and have exact contract fields with no duplicate keys (including escaped or case aliases). Both architecture descriptors must satisfy the contract. Every archive size must be positive and at most 268,435,456 bytes. Callers must bound reads before allocating downloaded Data; these APIs perform no downloads.

Schema, product, key ID, semantic core version/tag, channel, full revision, app range, IPC 1, profile format 1, daemon session guards, explicit reviewed status and local approval all fail closed. App range versions are plain numeric triplets; core versions permit valid prerelease identifiers, without build metadata. Integer JSON fields require unsigned integer tokens: fractional and exponent forms
are rejected before decoding to prevent floating-point rounding into accepted values.
Channel must be beta for a prerelease and stable otherwise. Version strings are
bounded to 128 UTF8 bytes. Numeric triplet components must fit UInt64; larger components fail closed.

Archive hash verification does not establish safe extraction or runtime readiness. Before installation, a separate packaging gate must enforce at most four entries: exactly `macos-<arch>/{bimeron,LICENSE,THIRD_PARTY_NOTICES.txt}` plus the optional expected parent directory; no extras, traversal, duplicates, links or special files; store/deflate only, no encryption; executable binary mode; binary uncompressed size at most 256 MiB and each notice at most 4 MiB. Publisher nonexecuted Go buildinfo checks are source metadata evidence, not consumer proof of runtime readiness. This consumer never extracts, executes, installs, or accesses a daemon.

Tests use synthetic ephemeral Ed25519 keys and self-signed JSON only. Publisher interoperability fixtures remain a follow-up integration check.
