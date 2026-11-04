# Local Apple packaging verifier evidence

This is local implementation evidence, not production approval or independent
review. The fixture version `0.1.0-beta.1`, fixed all-zero Ed25519 seed, reviewed
compatibility and explicit candidate approval are synthetic test inputs only.
No production key, pin, candidate or reviewed-policy default is supplied.

## Source identities and artifacts

Consumer base: `70e7f218c62d8ebcf04813e59d4fac3ecd5e95db`.
Authoritative read-only Core L: `15fe391d785e7f4a4a4e63ccb34efe4630b5363f`.
Tested Core code: `e8de4354e2dc5d0364a2fb93119c50971cdf8a5c`, including builder
hardening `3bc62c51341d08afc7733acc567b6e8f583a9c6f`.
The producer contract is `docs/apple-update-manifest.md`, ADR0032,
`internal/appleversion/{record,macho}.go`, and
`release/applemanifest/manifest.go` in L. L, original G and E were not modified.

Real archives were rebuilt in an ignored, detached, tag-free local checkout of
exact tested Core code using installed Go 1.26.9, no dependency downloads and
explicit scoped Git. No archived binary was executed, including arm64.
amd64 is static-only. These match the recorded Core handoff hashes exactly:

- amd64: 9,998,522 bytes, SHA-256 `c428a7cddabb752505cb4f0b0e2ad8d951b0302541c1f5d42ac6c5e5befa5fc5`
- arm64: 9,334,045 bytes, SHA-256 `ffd977be9be015ebb6c7e1a1bb6b218d8066c79afa9f873db6a581bdf0d6e479`

The deterministic generated record is 72 bytes, SHA-256
`1c5eb2a1c3c437a8f1275c04763e5994fc391f8ff8b7e9464007db6ef5c5fc64`.
Its generated ignored bytes remain an additional explicit build input outside
Git source identity. A preliminary local clone containing tags produced different
module-version metadata and archive hashes; final evidence uses the tag-free
checkout, matching the original Core integration recipe.

## Offline reproduction

Run from the consumer root. Use a new ignored local checkout; clone is a
filesystem-only source copy, with no network endpoint. No remote command is used.
Existing ignored artifacts are not required for reproduction.

```sh
ROOT="$PWD"
L=/Users/wrk/.t3/worktrees/bimeron-core/research-apple-core-provenance
GIT=/Users/wrk/.local/bin/git
GO=/Users/wrk/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.26.9.darwin-arm64/bin/go
REV=e8de4354e2dc5d0364a2fb93119c50971cdf8a5c
mkdir -p .build/apple-interop
"$GIT" clone --no-tags --no-hardlinks --no-checkout "$L" .build/apple-interop/core-notags
"$GIT" -C .build/apple-interop/core-notags checkout --detach "$REV"
"$GIT" -C .build/apple-interop/core-notags config --remove-section remote.origin
export GOENV=off GOFLAGS= GOEXPERIMENT= GOAMD64=v1 GOARM64=v8.0
export GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOWORK=off
cd .build/apple-interop/core-notags
mkdir -p .tmp
"$GO" build -o .tmp/apple-builder ./scripts/build-apple-release.go
.tmp/apple-builder -git="$GIT" -go="$GO" -version=0.1.0-beta.1 -revision="$REV"
"$GO" test ./internal/appleversion ./release/...
cd "$ROOT"
python3 scripts/apple-local-vectors.py .build/apple-interop/core-notags/.tmp/apple-release .build/apple-interop/vectors-final
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-final" swift test
cd .build/apple-interop/core-notags
"$GO" run "$ROOT/scripts/apple-local-parity.go" "$ROOT/.build/apple-interop/vectors-final"
cd "$ROOT"
# Verify exact deterministic Go-signed bytes in the final consumer pass.
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-final" swift test
swift build -c release
python3 fixtures/acceptance/check.py
"$GIT" diff --check
```

The builder was compiled offline in the first same-commit local checkout and
copied into the final tag-free checkout; building it there as above is equivalent.
Core targeted tests were run in the first same-commit checkout. All source bytes
are identical; the final archive-producing checkout had clean tracked source.

`apple-local-vectors.py` reads trusted source-built archives and creates bounded
positive/negative ZIPs without executing them. Swift emits exact signed manifest
bytes and initial signatures beside every ZIP. The Go parity harness verifies
them and emits deterministic signatures using the synthetic all-zero seed. The
second Swift pass preserves and verifies those exact Go-signed bytes. CryptoKit
signatures were observed to vary for identical bytes and seed, so deterministic
signing evidence comes from pinned Go, not CryptoKit. For the two original positives, each
manifest contains the real hashes/sizes of both actual architecture archives.
Every negative is rehashed and synthetically signed to reach packaging checks;
a separate tampering assertion checks archive authentication rejection.
The Core parity harness independently authenticates those exact initial
manifest/signature bytes with the synthetic public key and runs `CheckArchive`
for every same ZIP against the same expected result. The index records every
vector's SHA-256, architecture and expected disposition. Large generated ZIPs,
signed manifests, logs and working index remain ignored under `.build/apple-interop`; a compact copy of the sorted index and original synthetic signed full-archive descriptor are retained in `testdata/`.

## Results and remaining gates

Final results: all 348 archive vectors have identical expected dispositions in
Swift and Core, including exact Swift-signed manifest verification, complete
Core archive-pair verification and tampering rejection. Full `swift test` with
the corpus passed: 27 XCTest tests and 59 Swift Testing tests. Scoped
`git diff --check` passed.

The prior fix at `5d6cf55` also passed `swift build -c release`. `python3 fixtures/acceptance/check.py` passed 26 scenarios and
29 fixture files, including its corruption/coverage/lifecycle rejection controls.
Offline Core `go test ./internal/appleversion ./release/...` passed all three
packages (0.677s, 2.521s and 6.156s). Those unchanged release/acceptance/Core
package checks were not repeated for the one-line DEFLATE condition fix. The
subsequent third-round container rewrite justified a new release build; see its
results below. Acceptance fixtures and Core package code remain unchanged.

Prior first-round-fix logs: `.build/apple-interop/review-fix-swift.log`,
`review-fix-parity.log`, `review-fix-release.log`, `review-fix-fixtures.log`,
`review-fix-core-tests.log`, `review-fix-targeted.log`. Archive-build evidence
remains in `builder-notags.log`. No runtime performance benchmark is claimed
for this validation-only change. The review-fix run used the existing exact
source-built archives and `vectors-review-fix` instead of `vectors-final` in
the commands above. The final deterministic-signature Swift pass completed
26 XCTest tests in 6.614 seconds and 59 Swift Testing tests in 5.936 seconds.
The release build completed in 3.73 seconds.

The sorted index is retained as
`testdata/local-full-archive-vector-index.json`, SHA-256
`b83302ed61b7b23c0a6b4702bae3ce45b7390622a12dec461718cff60bed670b`.
The deterministic full-archive synthetic-reviewed manifest is retained as
`testdata/local-full-archive-synthetic-reviewed.json`, SHA-256
`32627976fae87ed9407dbe27f781b414904830914567e0c1ad475ef6390b4bf9`,
and its detached signature has SHA-256
`e63867eb737871bd37a9a03d3c3e9cd6a3fdc95d7cd8f4102d47309e71ab488a`.
These authenticate both actual source-built archive descriptors using the fixed
synthetic public key `O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=`;
they confer no production trust or Apple compatibility approval.

A fixture-construction assertion initially caught a quoted-setting mutation
larger than the original section; removing an unrelated synthetic build-setting
line kept that control within its original bounded section. A subsequent Swift
run started before the corpus index existed and failed that test. Both were
corrected before the final passing corpus runs.
Normal `swift test` keeps record/bounds/version tests active and skips only the
opt-in real-Core corpus when `BIMERON_APPLE_VECTORS` is absent. Supplying that
variable runs the full signed both-architecture corpus with the complete suite.

Coverage includes original/repacked/stored/ZIP64-end/optional-parent positives and quoted
or escaped provenance keys; malformed/truncated/extra/missing/duplicate/aliased/
absolute/backslash/traversal paths; symlinks/special files/no execute/empty files;
notice/binary limits; encryption/compression/CRC/local-header corruption; CPU/type;
missing/malformed/duplicate/oversized/mismatched record and read-only placement;
OS/architecture/revision/dirty/missing-clean/Git/trimpath metadata and duplicate
decoded provenance. Canonical record tests cover arbitrary decimal components
above UInt64, total 128-byte boundary and no build suffix. App numeric ranges
retain UInt64 bounds and compare decimal strings.

## Independent review disposition at 686415c

The parent independently passed the prior 94-vector Swift corpus. A separate
Sol MEDIUM read-only review nevertheless found two P2 parity bugs. Both findings
are accepted; passing the old corpus did not cover these cases. Reviewer
artifacts were supplied at `/tmp/apple-review.gTYXNO/`. This implementation
turn did not perform or delegate independent review. A new parent-owned review
round is still pending.

1. The descriptor CRC was ignored when central flag 3 was set. The amd64
   regression flips byte 9,981,277 in the original ZIP; its SHA-256 is
   `2d33b8cccecd90ec7495de55ab4a61268c46ec4d9f7d7be7c30c499f37a3b650`.
   The regenerated regression matches the reviewer artifact byte-for-byte.
   Swift now checks descriptor CRC and the decompressed-content CRC as Core does.
2. Local-header name/flags/method equality was stricter than Core's central
   directory reader. The amd64 regression flips byte 30; SHA-256 is
   `8a1ba6193b2e6cd689dfe89bbb4d50076ec34fc53993edb5598b926f9d3f0f38`.
   It also matches the reviewer artifact byte-for-byte. Swift now checks the
   bounded 30-byte local header and its signature, then uses only its name/extra
   lengths to locate payload bytes. Exact accepted names, type, permissions,
   compression, flags, CRC and size limits still come from the authenticated
   central directory. Local naming cannot redirect a path because this gate
   never extracts or writes entries. Any future extractor needs its own safe
   extraction policy. As in Core, the optional empty parent is not opened.

The implementation follows installed Go 1.26.9
`src/archive/zip/reader.go`: `findBodyOffset`, `checksumReader.Read` and
`readDataDescriptor`. With central flag 3, Go consumes 12 descriptor bytes without
signature or 16 with `0x08074b50`, compares descriptor CRC to central CRC and then
compares actual content CRC. Size words are intentionally ignored, including
ZIP64 words; central sizes remain authoritative. Without flag 3, a nonzero
central CRC is checked and zero is treated as unspecified, matching Go.
No manifest signature/hash, central path/type/limit or binary evidence check was
removed. Decompressed-size validation remains mandatory.

The expanded corpus adds 18 vectors per architecture: the original descriptor
CRC regression; local name/method/flags acceptance; signed/unsigned descriptors;
signed/unsigned ZIP64 descriptors; EOF truncation below minimum reads; ZIP64
frames shortened to Go's accepted minimum; empty/four-byte descriptors; bad CRC
in unsigned/ZIP64 forms; ignored descriptor sizes; and no-descriptor zero CRC.
Descriptors are placed at true EOF in the EOCD comment for truncation controls,
preventing accidental reads from the next header. Every vector is synthetically
signed and checked by Swift and Core with full archive-pair verification.

## Independent round-two review disposition at 5d6cf55

The parent reports that the independent second review confirmed both first-round
fixes, all 130 signed parity vectors and the full Swift suite. It found a new P2:
Swift required the DEFLATE decoder to consume every byte of the central-directory
compressed range, while pinned Go stops at the final block and ignores trailing
bytes within that bounded range. The finding is accepted. No independent review
was performed or delegated by this implementation turn; fresh parent-owned
review remains pending.

The reviewer archive `/tmp/apple-rereview.7SFMVS/trailing-deflate.zip` has SHA-256
`38d0de2cfe00f7b5203fc2cb77579fd90c6c0dd84629602850ea57a2d6fc33d7`.
The generated amd64 `deflate-trailing-no-descriptor` vector matches it byte for
byte. It inserts `X` after the first compressed stream in the repacked archive
and updates compressed sizes, following local offsets and central-directory
offset without changing uncompressed content.

Installed Go 1.26.9 `src/archive/zip/reader.go` opens a section reader bounded by
the central compressed size and uses the registered DEFLATE reader.
`src/archive/zip/register.go` uses `flate.NewReader`;
`src/compress/flate/inflate.go` explicitly states that the reader returns EOF
after the final block and ignores trailing data. Swift now requires
`Z_STREAM_END` and exact decompressed size without requiring `total_in` to equal
the supplied bounded payload length. Archive signature/SHA-256, payload bounds,
CRC checks, descriptor checks and static binary evidence are unchanged.
Descriptors remain located after the entire declared compressed range.

Eight new synthetically signed full-archive controls cover both architectures:
trailing-byte acceptance and final-stream-byte removal rejection, each with and
without data descriptors. The generator updates central/local compressed sizes,
following entry offsets and descriptor placement consistently. The new
truncation cases retain valid ZIP structure and exercise missing DEFLATE EOS,
rather than simply deleting the ZIP trailer.

Round-two-fix results: the full 138-vector Swift corpus passed before and after
the Core deterministic-signature handoff. Core reported `PASS 138 Core archive
vectors`, including manifest signature verification, complete archive pairs,
`CheckArchive` and tampering rejection. The final complete Swift run passed
26 XCTest tests (8.529 seconds) and 59 Swift Testing tests (6.238 seconds).
Scoped `git diff --check` passed. Logs are
`.build/apple-interop/round2-fix-swift-initial.log`, `round2-fix-parity.log` and
`round2-fix-swift-final.log`. The original full-archive manifest/signature hashes
and source-built archive hashes remain unchanged. No release build, acceptance
fixture or unchanged Core package-test rerun was needed for this fix.

The exact corpus/handoff commands use the same `ROOT`, installed `GO` and
explicit offline Go environment from the reproduction block above, with the
existing tag-free exact-source checkout:

```sh
python3 scripts/apple-local-vectors.py .build/apple-interop/core-notags/.tmp/apple-release .build/apple-interop/vectors-round2-fix
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-round2-fix" swift test
cd .build/apple-interop/core-notags
"$GO" run "$ROOT/scripts/apple-local-parity.go" "$ROOT/.build/apple-interop/vectors-round2-fix"
cd "$ROOT"
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-round2-fix" swift test
"$GIT" diff --check
```

## Independent round-three review and authorized container rewrite

The parent reports that the third independent review confirmed the DEFLATE fix,
all 138 signed vectors, and full Swift runs before/after deterministic Go
signing. It found a P2 creator-mode mismatch: a Unix regular entry with the DOS
directory attribute was incorrectly rejected. The finding is accepted. Reviewer
artifact
`/var/folders/yb/8qc2pj8d021g__3c2_fnhkmr0000gn/T/apple-round3-mode.rsb3mj18/amd64-unix-dos-dir.zip`
has SHA-256
`2b1f8e8f377686a77d35498f70ab0abbe2464b61e2f54b9f28ff45638631e4d4`.
The generated `amd64-mode-3-unix-dos-dir.zip` matches it byte-for-byte.

This implementation turn read the complete installed Go 1.26.9
`FileHeader.Mode`, `msdosModeToFileMode`, `unixModeToFileMode`, their constants,
`fs.FileMode.Type/IsRegular`, and actual Core `CheckArchive` use. The consumer now
mirrors the fields Core observes:

- Creators 3 and 19 use upper Unix attributes and ignore DOS attributes.
  Recognized directory/FIFO/device/link/socket types map to their Go types.
  Zero and unrecognized Unix type values remain regular as Go defines them;
  setuid/setgid/sticky are outside Go's type mask. Executable permission checks
  still use the low nine Unix permission bits.
- Creators 0, 11 and 14 use DOS directory/read-only attributes: directory mode
  starts at 0777, regular mode at 0666, and read-only removes 0222. A DOS regular
  executable therefore fails the independent execute-bit requirement. High Unix
  attributes are ignored for these creators.
- Other creators start with zero mode/permissions. Every creator receives Go's
  directory bit for a trailing slash. The optional parent must have exactly
  directory type; a Unix symlink or FIFO plus slash still fails. Notices must be
  regular, but do not require execute permissions.

The requested adjacent ZIP inspection found concrete container differences.
They were reported before redesign. The user explicitly approved a bounded
container-parity rewrite within this local scope, retaining all trust, exact
path/type/content/size gates and forbidding dependencies or extraction.

Central-directory structural parsing is now separate from policy validation.
The reader stores at most five headers and rejects five immediately under Core's
four-entry cap. Each header has at most three UInt16-length variable fields, so
no declared record count controls allocation or scanning. Policy validation then
requires the same exact three files and optional parent; a valid extra header is
counted and cannot bypass policy checks.

Concrete pinned-Go semantics now covered include:

- EOCD search in 1024-byte and 65-KiB windows; permitted bytes after its declared
  comment; the last-signature truncated-comment stop rule; ignored disk IDs and
  per-disk counts. These fields never cause access to another volume.
- Relative prefixes and Go's absolute-offset fallback when its inferred positive
  base offset is inconsistent but the original central offset parses correctly.
  Offset arithmetic uses Go-compatible signed wrapping followed by strict
  authenticated-buffer bounds checks.
- Directory scanning until a structural format/partial-read boundary, with
  actual count compared to the low 16 bits of the declared count. Exact EOF
  remains an error as in Go. Malformed padding after the counted entries is not
  treated as another file; a successfully parsed extra header is counted.
- Pinned Go's exact ZIP64 sentinel/locator rules, including its 0xffff directory
  size trigger, optional missing locator, ignored ZIP64 record-size/disk fields,
  and low-bit count comparison. ZIP64 sizes/offsets needed for an entry are
  consumed only once; missing required compressed-size/offset fields fail.
  Truncated unknown extra fields are ignored as Go does.
- `io.NewSectionReader` compressed-size limits, including signed ZIP64 size
  conversion. A DEFLATE stream may reach EOS before the declared compressed end
  or physical EOF. Supplied decoder bytes are always capped at the actual
  authenticated archive buffer, never allocated from a huge size claim.
  Descriptor offsets use the same signed calculation and bounded reads. Exact
  uncompressed size, EOS, CRC, descriptor and binary evidence still apply.

No resource-unsafe behavior or policy contradiction was needed to match these
cases. The five-header early stop has the same final rejection as Core for every
larger entry set, while avoiding Go's potentially larger intermediate allocation.

The corpus grows from 138 to 348 vectors: 130 creator/type/permission vectors and
80 focused container regressions, split evenly across amd64 and arm64. Coverage
includes Unix/macOS/DOS/unknown creators for executable, notice and optional
parent; all recognized Unix special types; DOS read-only and directory behavior;
unknown Unix types and special permission bits; EOCD windows/truncated comments,
count/disk fields and padding; relative/absolute prefixes; ZIP64 fields, extras,
counts and overflow bounds; and compressed ranges extending beyond file bytes.
A normal-suite creator-mode unit test also remains active without opt-in data.

Third-round-fix results: all 348 vectors passed in the full Swift run before
signing handoff, Core's exact manifest-signature/archive-pair/`CheckArchive`
parity run, and the final Swift verification of deterministic Go signatures.
Core reported `PASS 348 Core archive vectors`. Final Swift results were
27 XCTest tests in 20.709 seconds and 59 Swift Testing tests in 7.099 seconds.
`swift build -c release` passed in 11.40 seconds. Acceptance fixture checking
passed 26 scenarios/29 files with corruption/coverage/lifecycle rejection
controls. Scoped `git diff --check` passed. Unchanged Core package tests were
not repeated; the actual pinned Core library ran on every corpus archive.

Logs are `.build/apple-interop/round3-fix-swift-initial.log`,
`round3-fix-parity.log`, `round3-fix-swift-final.log`, `round3-fix-release.log`,
`round3-fix-fixtures.log` and `round3-mode-unit.log`. The final Swift log prints
its loaded 348-vector count. An earlier intermediate run loaded the previous
340-vector index while the eight compressed-range controls were still being
generated; the complete 348-vector run supersedes it. The original archive,
full-archive manifest and deterministic signature hashes remain unchanged.

The exact corpus/handoff commands use the same `ROOT`, installed `GO`, scoped
`GIT` and offline environment as the reproduction block, reusing the clean exact
Core source-built archives:

```sh
python3 scripts/apple-local-vectors.py .build/apple-interop/core-notags/.tmp/apple-release .build/apple-interop/vectors-round3-fix
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-round3-fix" swift test
cd .build/apple-interop/core-notags
"$GO" run "$ROOT/scripts/apple-local-parity.go" "$ROOT/.build/apple-interop/vectors-round3-fix"
cd "$ROOT"
BIMERON_APPLE_VECTORS="$ROOT/.build/apple-interop/vectors-round3-fix" swift test
swift build -c release
python3 fixtures/acceptance/check.py
"$GIT" diff --check
```

The release build ran alongside Core parity, before the final Swift pass;
parentheses subsequently made the unchanged arithmetic precedence explicit.
No separate independent review was requested by this implementation turn.
Fresh parent-owned review is required for both creator and container changes.

The bounded reader supports thin 64-bit little-endian Mach-O and inline Go build
information emitted by the pinned compiler. Unsupported layouts fail closed and
need new evidence. No universal binary support or execution fallback is added.
Embedded claims and clean metadata do not prove honest source derivation.
Independent parent review, production key/candidate/review-policy approval,
source reproducibility, extraction safety, installation and daemon/session
readiness remain separate gates. No hosted CI was run under the global pause.


## Final independent review and parent verification

Independent read-only Sol MEDIUM round four reviewed code commit
`52be97decbc9d583e22cea8c979ae1914fa5d8eb` against pinned Go/Core creator
modes, EOCD/ZIP64, counts, offsets, bounds and payload handling. It reported
no actionable P1/P2 findings. It independently passed the full Swift suite
with all 348 signed archive vectors and confirmed the exact mode reproducer
hash. It did not rerun Core parity or the release build. Prior review findings
are resolved; a finite corpus does not prove universal parser parity.

The parent then independently passed the full Swift suite at the same code
commit using `.build/apple-interop/vectors-round3-fix` (348 entries):
27 XCTest and 59 Swift Testing tests. Log: `.build/apple-parent-348-final.log`.
Earlier parent status messages incorrectly described runs using the older
`vectors-final` directory (94 entries) as covering the expanded corpus.
Those runs passed, but only this final explicit directory run establishes the
parent's 348-vector Swift result. The independent review's 348-vector result
is separate evidence.

Production trust/candidate/review approvals, honest source derivation, safe
extraction, installation and runtime readiness remain separate gates. No
archived binary was executed, including arm64; both CPU archives were checked
statically. Original G/E/L remain untouched. No network, remote mutations,
hosted CI, installation or production approval occurred.

The parent additionally reran the offline pinned Go authenticated parity harness
against that exact 348-entry directory after the final Swift run: exit zero,
`PASS 348 Core archive vectors`. Log: `.build/apple-parent-core-348.log`.
The harness authenticated the Swift-written sidecars, verified every expected
archive disposition and refreshed deterministic synthetic Go signatures.
