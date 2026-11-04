# feat: add guarded privileged daemon lifecycle client

Adds an isolated BimeronDaemon target for adopting and controlling an existing
root-owned Core daemon. Repeated intentions coalesce; switching waits for confirmed
cleanup; failed stop cancels replacement. IPC ambiguity becomes unknown and never
triggers an automatic mutation retry. Restart resynchronization invalidates pending
work. Production transport authenticates the peer before writing and requires the
explicit Core daemon guard handshake before guarded mutations.

Integrated main `d879fd6ba992faaa4fc359bbaeb5fcee8e8a2f88` includes B (#4) and
merged D (#5). The only merge conflict was Package.swift; both module/test target
pairs are preserved. D fixtures and checker are unchanged from main.

Validation: default `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test` passed
15 daemon XCTest tests and 38 Swift Testing tests (24 baseline plus 14 B test
declarations, including parameterized cases), zero failures. The daemon adapter
checks five C scenarios at every event boundary within one XCTest test. The offline
fixture checker passed 26 scenarios / 29 files and its negative self-checks.
Release app build and executable bundle check passed. See check-results.md.
No hosted CI result is claimed.

Core guards remain local commit `10e29d5dbb26743776d3586dd1a8b506b4c100f3`
(based on `df7f2fd`), unreleased and not remotely CI verified. Coordinated Core
publication remains required. App/UI hookup and protected installation/launchd/live
acceptance remain later work. No live privileged daemon or network session was
used. Parent publishes after review; this workstream did not push or create a PR.
