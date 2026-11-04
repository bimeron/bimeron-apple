# Local issue: Apple privileged daemon lifecycle (workstream C)

Implement a separate BimeronDaemon module for attaching to an existing privileged
Core daemon. Core owns utun, routes, DNS and cleanup. The app must adopt sessions
without mutation, coalesce intentions, wait for disconnected and inactive status
before replacement, and preserve uncertainty after IPC failure. No automatic retry
of ambiguous mutations is permitted.

Approved design: platform-independent lifecycle reducer plus serialized async
client, with a separate macOS Unix socket transport. Explicit Core guard support
is required for mutation. No Network Extension or alternate backend is included.

Scope: Sources/BimeronDaemon, Tests/BimeronDaemonTests, minimal Package.swift
registration, and this documentation directory. App/UI integration belongs to a
later integration change. No privileged installation or live network testing.

Acceptance: stable D scenarios C-REPEAT, C-ADOPT, C-IPC-LOSS, C-SWITCH and
C-FAILED-STOP assert ordered mutations at every event boundary. Independent tests
cover pending clicks, restart invalidation, ambiguous timeout/cancellation, unknown
profile adoption, cleanup gates, framing, size, correlation and handshake guards.
