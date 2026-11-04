# feat: add guarded privileged daemon lifecycle client

Adds an isolated BimeronDaemon target for adopting and controlling an existing
root-owned Core daemon. Repeated intentions coalesce; switching waits for confirmed
cleanup; failed stop cancels replacement. IPC ambiguity becomes unknown and never
triggers an automatic mutation retry. Restart resynchronization invalidates pending
work. Production transport authenticates the peer before writing and requires the
explicit Core daemon guard handshake before guarded mutations.

Integrated main `34e90e00c114f9748e41ccc2b4a67c48c678fbf6` includes merged
A (#7), B (#4) and D (#5). Final merge
`db9835bb59f5de066105bbfd030d2cb9344034a3` is conflict-free. All A/B/C targets
and tests are preserved. A/B app/model/CLI sources and tests and D fixtures/workflow
match main; C daemon sources/tests match published C `6ab1c1a`. No duplicate
fixtures or production changes were introduced during final integration.

Validation: default `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test` passed
15 daemon XCTest tests and 52 Swift Testing tests (24 baseline plus 14 A preservation and 14 B test
declarations, including parameterized cases), zero failures. The daemon adapter
checks five C scenarios at every event boundary within one XCTest test. The offline
fixture checker passed 26 scenarios / 29 files and its negative self-checks.
Release app build and executable bundle check passed. See check-results.md.
Both working-tree and full C-versus-main whitespace checks passed.
No hosted CI result is claimed for this unpushed integration.

Core guards remain local commit `10e29d5dbb26743776d3586dd1a8b506b4c100f3`
(based on `df7f2fd`), unreleased and not remotely CI verified. Coordinated Core
publication remains required. App/UI hookup and protected installation/launchd/live
acceptance remain later work. No live privileged daemon or network session was
used. PR #9 already exists. The parent owns its publication and merge after current
combined CI; this integration did not push, merge or create a PR.
