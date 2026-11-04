# Local check results

Date: 2026-11-04. Branch: `feat/daemon-utun-lifecycle`.

## Integrated revisions

- Previous published C head: `6ab1c1a6b01d304d62e985e2ab03f105b84017a3` (PR #9).
- Fetched main: `34e90e00c114f9748e41ccc2b4a67c48c678fbf6`, including
  merged A (#7), B (#4) and D (#5).
- Final integration merge: `db9835bb59f5de066105bbfd030d2cb9344034a3`.
  This merge was conflict-free. All A/B/C targets and tests remain present.
  A/B app/model/CLI sources and tests, plus D fixtures and CI workflow, match
  main exactly; C daemon sources/tests match the previous published C head.
  No production changes or duplicate fixtures were needed.
- Final handoff head is the documentation commit containing this report; obtain
  its full ID with `git rev-parse HEAD` (also supplied in the handoff).

## Executed checks

- `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test`: passed, zero failures.
  XCTest reports 15 daemon tests: 3 client, 10 lifecycle and 2 protocol tests.
  Swift Testing separately reports 52 tests (24 baseline plus 14 A preservation and 14 B declarations,
  including parameterized cases). These are framework-reported counts, not a
  count of acceptance scenarios or parameter invocations.
  `testSharedAcceptanceScriptsAtEveryBoundary` passes using repository fixtures
  at the default path; it checks all five C scenario IDs at every event boundary
  within one of those 15 XCTest tests.
- `python3 fixtures/acceptance/check.py`: passed, 26 scenarios and 29 fixture
  files, offline integrity only. Negative self-checks rejected byte corruption,
  missing coverage and an unsafe lifecycle expectation. These scenarios are not
  26 additional Swift tests or proof of full application acceptance.
- `sh scripts/build-app.sh`: passed, including `swift build -c release`.
- `test -x dist/Bimeron.app/Contents/MacOS/Bimeron`: passed.
- `/Users/wrk/.local/bin/git diff --check`: passed.
- `/Users/wrk/.local/bin/git diff --check origin/main`: passed across the full
  C-versus-main diff.
- The merged `.github/workflows/macos.yml` runs the fixture checker, Swift tests,
  release app build and executable check. Local equivalents passed; no hosted CI
  run is claimed. The former missing-D/default-path blocker is resolved.

## Remaining boundaries

Core's contract remains pinned to local, unreleased commit
`10e29d5dbb26743776d3586dd1a8b506b4c100f3` (base `df7f2fd`), previously inspected
for the guard handshake and atomic mutation admission. The separate Core worktree
was not edited, published or executed during this integration. Its contract still
needs coordinated publication and remote CI verification; released beta.2 lacks
the required guard handshake and is blocked for mutation.

Daemon tests use deterministic in-memory observations/exchanges and synthetic
bytes. The production macOS transport compiled in debug and release; no live
socket/root-peer authentication, real descriptor cancellation, daemon, privileged
install, utun, routes, DNS or network session was exercised. B tests run synthetic
subprocess fixtures, not a real Core binary. App/UI hookup, protected installation,
launchd and live acceptance remain later work. No benchmark is warranted for the
small reducer; I/O remains bounded and cancellable.

Only this C branch/worktree was changed. No push, PR merge, PR creation, account switch or
privileged operation ran. PR #9 already exists; its draft below is local documentation only. The parent
owns publication and merge after current combined hosted CI. This local final
head has not been pushed and has no hosted CI result.
