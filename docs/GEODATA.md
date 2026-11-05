# GeoData foundation

`BimeronGeoData` is an isolated, offline-testable cache foundation. It has no app
callers, default provider, network adapter, automatic download, selection, settings,
profile mutation, or garbage collection. The caller creates and owns the cache
folder and supplies a transport, source/checksum provenance, expected lowercase
SHA256, and a mandatory asynchronous Core validator.

## API and boundaries

`GeoDataTransport.nextChunk(maxBytes:)` supplies sequential chunks of at most
64 KiB, returning nil at EOF. Implementations must avoid unrestricted buffering
and honor cancellation during their own asynchronous work. The manager rejects
empty chunks, empty files, oversized chunks, and streams exceeding 64 MiB. It
checks cancellation at stream boundaries, around validation, during hashing, and
immediately before publication. A transport or validator that does not cooperate
cannot be forcibly interrupted by this module. Cancellation racing after the
final check can complete publication.

The validator receives the staged URL and `geoip` or `geosite` kind. It must run
the selected compatible Core's validation and throw unless validation completes
successfully. This module neither invokes Core nor implements protobuf parsing;
a no-op callback cannot establish format validity. Validation does not establish
runtime service readability, loaded state, selected groups, or session compatibility.
The file is hashed again after validation to detect accidental validator mutation.

`inventory(file:kind:)` opens the explicitly supplied regular file read-only,
rejects final-component symlinks, and returns its caller-stated kind, size, and
SHA256 under the same size bound. It does not validate semantics or snapshot a
concurrently modified manual file. Manual files are never copied over or altered.

Downloads use `<cache>/<sha256>/<kind>.dat`. Random exclusive staging files live
beside the destination and are removed on success, error, or cancellation. An
atomic hard link publishes the completed, synced file without replacement.
An existing destination is reused only after a bounded hash check. Corrupt files
are reported and left intact; previous immutable versions are retained. Cache root,
hash directory, staging creation, and final-file reads reject symlinks at their
respective final components. Directory-relative creation/publication anchors writes
to opened directory descriptors; no caller-selected replacement path is accepted.

The cache and its ancestors must be private, stable, caller-controlled directories;
this is not a sandbox against another process that can rename cache directories or
modify files while the validator uses path-based access. The validator is trusted
code and must read without modifying or replacing the staged file. Atomic visibility
does not promise crash durability of directory entries. Empty hash directories can
remain after failure; no staging files or partial final files remain. The internal
`beforePublication` fault seam only injects a throwing failure for offline tests.

SHA256 establishes consistency with the caller's expected bytes, not authenticity.
Source and checksum provenance are explicit caller assertions; the module does not
fetch, authenticate, or persist that metadata. Provider policy, license review,
checksum trust, redirects, HTTP policy, and network timeouts belong to future
integration. No real datasets, provider URLs, or license assumptions are bundled.

## Inspected upstream contracts

Desktop reference: `296130e3e5f255410dd70c0680b37b0ed351165b`, specifically
`docs/geodata-download-plan.md`,
`src/GeoDataDownload.cpp`, and `src/GeoDataDialog.cpp`. Its manager offers explicit
click-initiated downloads and manual file choice, shared across managed profiles.
It validates a staged candidate through the selected Core before applying shared
selection; failed downloads preserve the previous usable file. Changes take effect
on a new Core session. The Desktop provider choice and GUI selection/application
workflow are reference behavior, not enabled by this bounded macOS foundation.

Core reference: `d4b85fb6a70893e3ac229697b3acd952599837e9`, inspected from a local checkout,
`internal/routing/geodata.go`. Its decoder limits input to `64 << 20` bytes and
accepts V2Ray `GeoIPList` / `GeoSiteList` protobuf data, with further limits on
entries, groups, strings, and regex work. Only Core can establish those semantics
here; a matching hash or `.dat` suffix cannot.

## Verification

Run `env -u BIMERON_CORE_EXECUTABLE swift test --filter BimeronGeoDataTests`.
Tests use temporary directories, synthetic opaque byte streams and mock validators.
They test hashing, bounds, corruption, validator rejection, cancellation, transport
failure, injected publication failure, symlink rejection, staging cleanup, immutable
versions, and unchanged manual files. They do not claim real format validation,
provider compatibility, network behavior, or a real Core integration test.

All six targeted tests passed locally with the Core executable override unset.
An independent source review found no issues within this bounded scope. The
publication fault test throws immediately before the filesystem commit; it does
not simulate a disk or kernel failure. Shared CI configuration and PR admission
remain owned by the main coordinator.
