# feat: add guarded privileged daemon lifecycle client

Adds an isolated BimeronDaemon target for adopting and controlling an existing
root-owned Core daemon. Repeated intentions coalesce; switching waits for confirmed
cleanup; failed stop cancels replacement. IPC ambiguity becomes unknown and never
triggers an automatic mutation retry. Restart resynchronization invalidates pending
work. Production transport authenticates the peer before writing and requires the
explicit Core daemon guard handshake before guarded mutations.

Validation: deterministic C scenario adapter checks every event boundary, plus
independent client/reducer/protocol tests. Run the full Swift suite with the explicit
external D fixture root documented in README.md. See check-results.md for results.
No live privileged daemon or external network was used.

Integration blockers: D f8988b7 is not merged, so default CI fixture readiness is
pending. Core guards are local commit 10e29d5dbb26743776d3586dd1a8b506b4c100f3
(based on df7f2fd), not a released or remotely CI-verified Core contract. Parent publishes only after review/dependency coordination. Actual
protected installation and launchd acceptance remain item 10. App integration is
outside this change. No remote issue or PR has been created by this workstream.
