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

Final results: all 138 archive vectors have identical expected dispositions in
Swift and Core, including exact Swift-signed manifest verification, complete
Core archive-pair verification and tampering rejection. Full `swift test` with
the corpus passed: 26 XCTest tests and 59 Swift Testing tests. Scoped
`git diff --check` passed.

The prior fix at `5d6cf55` also passed `swift build -c release`. `python3 fixtures/acceptance/check.py` passed 26 scenarios and
29 fixture files, including its corruption/coverage/lifecycle rejection controls.
Offline Core `go test ./internal/appleversion ./release/...` passed all three
packages (0.677s, 2.521s and 6.156s). Those unchanged release/acceptance/Core
package checks were not repeated for the one-line DEFLATE condition fix; the
changed Swift path was compiled and exercised by the complete Swift suite.

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
`90718990f86d2c5c8166734e011c4f3f8c845d18773dab7247b7dc92a35fb56b`.
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

The bounded reader supports thin 64-bit little-endian Mach-O and inline Go build
information emitted by the pinned compiler. Unsupported layouts fail closed and
need new evidence. No universal binary support or execution fallback is added.
Embedded claims and clean metadata do not prove honest source derivation.
Independent parent review, production key/candidate/review-policy approval,
source reproducibility, extraction safety, installation and daemon/session
readiness remain separate gates. No hosted CI was run under the global pause.
