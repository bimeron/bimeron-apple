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
bytes and signatures beside every ZIP. For the two original positives, each
manifest contains the real hashes/sizes of both actual architecture archives.
Every negative is rehashed and synthetically signed to reach packaging checks;
a separate tampering assertion checks archive authentication rejection.
The Core parity harness independently authenticates those exact Swift-emitted
manifest/signature bytes with the synthetic public key and runs `CheckArchive`
for every same ZIP against the same expected result. The index records every
vector's SHA-256, architecture and expected disposition. Large generated ZIPs,
signed manifests, logs and working index remain ignored under `.build/apple-interop`; a compact copy of the sorted index and original synthetic signed full-archive descriptor are retained in `testdata/`.

## Results and remaining gates

Final results: all 94 archive vectors have identical expected dispositions in
Swift and Core, including exact Swift-signed manifest verification, complete
Core archive-pair verification and tampering rejection. Full `swift test` with
the corpus passed: 26 XCTest tests and 59 Swift Testing tests. `swift build -c
release` passed. `python3 fixtures/acceptance/check.py` passed 26 scenarios and
29 fixture files, including its corruption/coverage/lifecycle rejection controls.
Offline Core `go test ./internal/appleversion ./release/...` passed all three
packages (0.761s, 4.222s and 10.246s). Scoped `git diff --check` passed.

Final logs: `.build/apple-interop/swift-final.log`, `parity-final.log`,
`release-final.log`, `fixtures-final.log`, `core-tests.log`, `builder-notags.log`.
The opt-in Swift corpus completed in 4.297 seconds; complete XCTest execution
was 4.334 seconds and Swift Testing execution was 5.960 seconds. No runtime
performance benchmark is claimed for this validation-only change.

The sorted index is retained as
`testdata/local-full-archive-vector-index.json`, SHA-256
`cc7935002301537afa48e05a5bf65351f2737c9b661f7a8259ecbf74578ce981`.
The deterministic full-archive synthetic-reviewed manifest is retained as
`testdata/local-full-archive-synthetic-reviewed.json`, SHA-256
`32627976fae87ed9407dbe27f781b414904830914567e0c1ad475ef6390b4bf9`,
and its detached signature has SHA-256
`140ebe76f7c19cbb65a05d3985fd91955dbcf5587cc207a77f506508dbca2ece`.
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

The bounded reader supports thin 64-bit little-endian Mach-O and inline Go build
information emitted by the pinned compiler. Unsupported layouts fail closed and
need new evidence. No universal binary support or execution fallback is added.
Embedded claims and clean metadata do not prove honest source derivation.
Independent parent review, production key/candidate/review-policy approval,
source reproducibility, extraction safety, installation and daemon/session
readiness remain separate gates. No hosted CI was run under the global pause.
