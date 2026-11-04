# Local check results

Date: 2026-11-04. Branch: `feat/daemon-utun-lifecycle`.

## Integrated revisions

- Original C head: `292a8e9056d6a0a22e1cb786587ccb934d8dc0cc`.
- Fetched main: `d879fd6ba992faaa4fc359bbaeb5fcee8e8a2f88`, including B (#4)
  and merged D (#5).
- Integration merge: `27501da435dfda27a614b934ffbf3135a215d920`.
  Package.swift was the only conflict; both BimeronDaemon and BimeronCoreCLI
  module/test target pairs are retained. No C implementation or test changes
  were needed. B sources/tests and D checker/fixtures/docs/CI match main.
- Final handoff head is the documentation commit containing this report; obtain
  its full ID with `git rev-parse HEAD` (also supplied in the handoff).

## Executed checks

- `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test`: passed, zero failures.
  XCTest reports 15 daemon tests: 3 client, 10 lifecycle and 2 protocol tests.
  Swift Testing separately reports 38 tests (24 baseline plus 14 B declarations,
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
- `git diff --check`: passed.
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

Only this C branch/worktree was changed. No push, PR creation, account switch or
privileged operation ran. The parent reviews and publishes the prepared PR draft.
