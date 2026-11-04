# Standalone connection statistics

Workstream: issue #37. This module is an in-memory model only. It has no daemon,
wire parser, live adapter, runtime, UI, diagnostic, or transport dependencies.
All test observations are explicitly synthetic; no live Core/VPN validation is implied.

## Caller contract

Construct `ConnectionStatistics` with an explicit positive stale duration and
nonnegative sample/event count bounds (zero disables retention). There are no
production defaults. Invoke it serially. Pass `Duration` elapsed values from one
monotonic origin, such as `ContinuousClock`, and advance time even without samples.
Tests simulate that clock with exact durations; wall-clock timestamps are not used.
At the stale boundary (`age >= staleAfter`) current counters/rates become unavailable;
history remains bounded historical evidence. Status remains the last authoritative
status, not evidence of current IPC health. Call `loseIPC` on IPC loss.

Before `confirm`, the caller must confirm a nonempty daemon instance and session
identity and the association of statistics with that identity. Core does not provide
an atomic status/statistics identity snapshot. This API cannot prove that association;
merely copying the adjacent response status is insufficient. Do not connect a live
adapter until that prerequisite is solved. `confirm` creates an opaque generation
for every resync, including the same identity, and clears current state, histories,
and event cursor. Old generation/session/instance work is rejected. Request sequence
numbers are caller-issued, strictly increasing within a generation; they are not
Core sample sequences. Elapsed sample time must strictly increase too.

`observe` accepts authoritative normalized status plus optional signed byte counters.
A nil counter input means unavailable (including missing stats/native IKEv2), never
zero. Negative counters invalidate the whole byte sample. A fresh zero is available;
a rate needs two valid, increasing-time connected observations. Rates are bytes per
second using fractional seconds (Duration attoseconds divided by 1e18). No rates cross
reconnecting/nonconnected status, unavailable samples, IPC loss, resync, stale gaps,
or either byte counter decreasing. A nonnegative decrease begins a new baseline;
Int64 max-to-negative rollover is unavailable, never a wrapped delta. Subtraction is
safe only after both operands are nonnegative and ordered. Retained post-session
totals are allowed with a nonconnected status but never produce a rate.

Events carry only sequence and code, scoped to the token's instance/generation;
there is no event session attribution. Batches require increasing sequence values
above the prior cursor and at or below the new cursor. Events never establish
connection state. A dropped batch preserves bounded history but invalidates the
token and sets `needsResync`: reread authoritative status and re-confirm before
accepting more data. This is deliberately conservative. Local history eviction is
not a daemon drop. Bounds are item counts, not byte budgets; the eventual adapter
must enforce wire/string size limits. No source-drop count is invented.

## Pinned source evidence

Authoritative Core commit: `c04f20d575e4aed979b1024a32b421e7e5de1afe`.
Read with `git show <commit>:<path>`; line references below refer to that revision.

- `core/engine.go:82-91`: counters are for the most recent Start, remain after end,
  and native IKEv2 reports unavailable. `180-206`: accepted Start allocates new
  counters; reconnect does not establish a new statistics epoch by itself.
- `internal/telemetry/telemetry.go:12-45`: independently atomic signed Int64 values;
  exact fields are `unavailable`, `tcp_total`, `tcp_active`, `tcp_failed`,
  `udp_total`, `udp_active`, `udp_failed`, `dns_queries`, `dns_failed`, `bytes_up`,
  `bytes_down`, `routed_proxy`, `routed_direct`, `routed_block`. `47-65` loads each
  separately, not an atomic multi-counter snapshot. `68-125` counts attempts,
  active flows, failures and DNS queries/failures; active counts are gauges, not
  cumulative traffic. This minimal model exposes byte totals only; it does not
  silently map flow counts to traffic. `128-138` adds positive byte counts with no
  rollover contract or source sample timestamp/time unit.
- Byte semantics are path-specific payload including direct/proxy and DNS, not
  wire bytes or universally delivered bytes. `internal/telemetry/copy.go:10-25`
  counts accepted destination writes; `internal/vpn/handler.go:219-236` counts UDP
  before destination delivery; `internal/proxy/server_udp.go:98-103,174-184` counts
  successful forwarding excluding SOCKS framing; `internal/vpn/dns.go:211-276`
  includes locally generated failure answers. Rates describe observations of these
  counters, with no transport overhead/delivery claims.
- `internal/control/server.go:61-70,145-150`: response instance is a daemon-server
  random identity. `274-280,381`: Stats and Status are read separately, permitting
  old totals/new identity races; there is no statistics sample time or sequence.
- `core/engine.go:27-34`: events use wall time and have no session ID. Status Since
  is a transition time, not a session start clock. `internal/control/server.go:211-218`
  sequences events per daemon instance across sessions and retains 128;
  `288-307` returns cursor and dropped-history indication. Daemon events do not
  populate foreground-only source-drop information.

Desktop commit `296130e3e5f255410dd70c0680b37b0ed351165b`,
`docs/core-desktop-integration-contract.md:291-294,347`, is UX guidance only:
reset cursors/speed on identity changes, reread status after dropped events, and
show native statistics as unavailable rather than zero. It supplies no missing
wire or atomic identity contract. Existing macOS `DaemonProtocol` and
`DaemonLifecycle` were read but are unchanged and are not dependencies.

## Validation

Run `swift test --skip-update --filter BimeronStatisticsTests` offline. Tests cover
fractional rates, fresh zero, reset/decrease/negative rollover, same/new identity
resync, reconnect, IPC loss, stale boundaries, ordering, bounded event/sample
history, drops, unavailable values, and retained disconnected totals. No network,
root, installation, or real VPN activity is required.

Parent verification: seven targeted XCTest tests passed, including the saved JSON
fixture and malformed event batches. The offline full run excluding
ConfigTextEditorTests passed 42 XCTest (one opt-in skip) and 84 Swift Testing tests
before the fixture-only test addition; the final targeted run passed afterward.
Fresh independent Sol LOW review found no actionable correctness issues. No GUI,
live Core, or VPN acceptance is claimed. Fixtures are excluded from SwiftPM resource
processing and loaded from their source path by tests.
