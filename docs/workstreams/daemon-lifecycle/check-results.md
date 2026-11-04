# Local check results

Date: 2026-11-04. Branch: `feat/daemon-utun-lifecycle`.

- Full `swift test` with explicit `BIMERON_ACCEPTANCE_FIXTURE_ROOT` pointing to
  `/Users/wrk/.t3/worktrees/bimeron-macos/test-acceptance-scenarios-fixtures/fixtures/acceptance`:
  passed, 15 daemon XCTest tests and 24 existing Swift Testing tests, zero failures.
  All five C IDs are checked by the fixture adapter at every event boundary;
  `observe-stop-pending` now translates to Core's `stopping` spelling. Five added
  deterministic tests cover Core-state adoption, accepted connecting stop,
  failed-stop explicit recovery, switch cleanup boundaries, and active session
  identity requirements. No D scenarios or artifacts were changed.
- External D worktree HEAD at final verification:
  `ce2654d8d5b94bded4db230d317df76e66998ca3`. Manifest and lifecycle fixture bytes
  have no diff against required `f8988b7`; later D documentation/CI changes remain
  outside this branch.
- Without the environment override,
  `swift test --filter DaemonLifecycleTests.testSharedAcceptanceScriptsAtEveryBoundary`
  failed with the explicit missing-D dependency diagnostic (one expected failure).
  This confirms missing default fixtures cannot silently pass. Default CI is not
  ready until D integration; no passing remote CI run is claimed.
- `git diff --check`: passed.
- macOS production socket transport compiled as part of the test build. No test
  connected to its endpoint. Runtime root-peer authentication and descriptor
  cancellation were not exercised against a real socket; in-memory client doubles
  cover cancellation, late completion, timeout uncertainty and coalesced intent.
- Core contract re-read from local commit
  `10e29d5dbb26743776d3586dd1a8b506b4c100f3`, including contract.md and server.go.
  Core source was not edited or executed by this workstream. Core remains local,
  unreleased and not remotely CI verified.

Implementation and local checks are complete. D integration is the remaining
fixture/default-CI dependency. Coordinated Core publication, app/UI integration,
and actual protected install/launchd/live acceptance remain later work. No remote
issue/PR, push, account switch, privileged install or live network operation ran.
