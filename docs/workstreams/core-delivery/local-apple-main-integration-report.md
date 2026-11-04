# Local Apple verifier integration report

Integration date: 2026-11-04. Local integration only; publication belongs to the parent.

## History and scope

- Original branch head: `a4acbf146624f5f593189f6ac1a211fa1dc19a14`.
- Previously reviewed verifier code: `52be97decbc9d583e22cea8c979ae1914fa5d8eb`.
- Fetched main integrated: `859f15b33e915be75506faf6409488da2936dccb`.
- Merge commit: `e9bc19ef9ba5de6b70afde916c16677fad562ff0`.

The non-fast-forward merge had no conflicts. Both parents and all original
static verifier commits remain ancestors; no rebase or force operation occurred.
Package.swift automatically merged SSHAuth alongside CZlib. Upstream delivery,
forms, diagnostics and SSHAuth changes are retained. The entire `.github`
contents match the integrated main commit; no local CI or runner allowlist edits
were made. Existing issue and evidence reports remain unchanged.

## Verification

Commands were run at the repository root unless explicitly scoped below.
Logs are ignored local artifacts under `.build/`.

```sh
BIMERON_APPLE_VECTORS="$PWD/.build/apple-interop/vectors-round3-fix" swift test > .build/apple-integration-348-initial.log 2>&1
swift build -c release > .build/apple-integration-release.log 2>&1
python3 fixtures/acceptance/check.py > .build/apple-integration-acceptance.log 2>&1
swift test > .build/apple-integration-standard.log 2>&1
ROOT="$PWD"
cd .build/apple-interop/core-notags
GOENV=off GOFLAGS= GOEXPERIMENT= GOAMD64=v1 GOARM64=v8.0 GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOWORK=off /Users/wrk/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.26.9.darwin-arm64/bin/go run "$ROOT/scripts/apple-local-parity.go" "$ROOT/.build/apple-interop/vectors-round3-fix" > "$ROOT/.build/apple-integration-core-348.log" 2>&1
cd "$ROOT"
BIMERON_APPLE_VECTORS="$PWD/.build/apple-interop/vectors-round3-fix" swift test > .build/apple-integration-348-final.log 2>&1
/Users/wrk/.local/bin/git diff --check
```

The isolated Core checkout is clean at
`e8de4354e2dc5d0364a2fb93119c50971cdf8a5c`; installed compiler reports
`go version go1.26.9 darwin/arm64`. The existing corpus index contains exactly
348 entries, rather than the older 94-entry vectors-final corpus. Prior source
ZIP hashes and source-build evidence remain in local-apple-packaging-evidence.md.

All commands passed (exit zero). Initial and final explicit corpus Swift runs
passed 35 XCTest tests with zero failures and 85 Swift Testing tests; each
reported `Apple archive corpus: 348 signed vectors`. The final run followed
Go signature regeneration. The optional executable-Core creation test remained
skipped because BIMERON_CORE_EXECUTABLE was unset; no archive execution was used.
The standard suite passed the same test inventory, with the optional corpus
XCTest also skipped as expected when BIMERON_APPLE_VECTORS is unset.
The offline Go harness reported `PASS 348 Core archive vectors`. The release
build passed. Acceptance reported `PASS: 26 scenarios, 29 fixture files; offline
integrity only` and rejected byte corruption, missing coverage and unsafe
lifecycle expectations. Diff whitespace checks passed.

## Limits and handoff

Only synthetic signing keys and static archive validation were used. No archived
binary was executed. No installation, daemon, live service, production key,
release, main merge, remote mutation, push or PR operation occurred. Original
G/E/L checkouts remain untouched. Hosted CI has not yet run for this integration;
parent publication and review remain outstanding. The finite corpus does not
establish universal parser parity, honest source derivation or runtime readiness.
