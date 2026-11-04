# Workstream C integration contract

`DaemonClient` is an actor. Call `reconcile()` for read-only hello/status adoption,
then `connect(profile)` or `disconnect()` for explicit intentions. Call
`invalidate()` on independently observed IPC loss; it cancels the owned exchange
and discards late results. Errors and cancellation become unknown. Reconciliation
never automatically retries an ambiguous mutation. A switch retains its replacement
only until authoritative cleanup, stop failure, restart or IPC loss. A stop
acknowledgment with an active session cannot start the replacement. Poll by explicit
read-only reconciliation if Core reports a pending transition.

`DaemonLifecycle` is the deterministic reducer used by that actor. `DaemonProfile`
contains a stable profile ID and an absolute config path, not configuration bytes.
Unknown adopted profile IDs remain usable session identities without rewriting or
restarting them. Core's six states remain distinguishable (`disconnected` maps to
`stopped`); `starting` is only a locally pending start request. After start acceptance,
a known active session can be explicitly stopped while connecting or reconnecting.
An outstanding stop blocks duplicate mutations until confirmed cleanup or failure.
Stop failure clears any queued replacement and permits an explicit guarded stop of
the observed active session; it never resumes the replacement automatically.
Unknown IPC state or an absent/empty active session identity blocks stop.
Static config validation remains a separate caller prerequisite.

The production transport attaches only to `/var/run/bimeron/control.sock`, uses
nonblocking I/O, authenticates peer UID 0 with macOS `getpeereid` before any write,
and closes its own descriptor on every return/cancellation/error. It neither
creates nor deletes the endpoint. Each exchange has a five-second deadline; a
mutation first performs a separate bounded hello, so the total can take up to ten
seconds. Cancellation checks occur at most five milliseconds apart while waiting.
No daemon, subprocess, route, DNS or installation ownership is acquired.

Wire contract inspected locally in Core worktree
`feat-daemon-session-guards`, local commit
`10e29d5dbb26743776d3586dd1a8b506b4c100f3` (base `df7f2fd`):
newline JSON, `version:1`, string `id`, `command`; hello explicitly returns
`daemon_session_guards:true`. Guarded start sends `instance` and absolute `config`;
guarded stop sends `instance` and `session`. Responses carry `instance`, `status`,
optional `error`; Core status keys are `State` and `Session`, session keys include
`id`, `active`, `profile_id`. Only `disconnected` plus no active session confirms
cleanup. A restart invalidates pending replacement and guard support. Production
mutations repeat hello and verify identity; Core must atomically enforce guards
at mutation admission to close the remaining race. No unguarded fallback exists.
Released beta.2 does not supply this handshake and is blocked for mutation.
Requests are limited to 16 KiB, responses to 256 KiB including newline. Responses
require matching protocol/id and a nonempty instance. Duplicate keys (including
escaped and casing aliases), malformed JSON, extra lines and incomplete frames are rejected.

## Local checks and dependency boundaries

Integrated main `d879fd6ba992faaa4fc359bbaeb5fcee8e8a2f88` includes B (#4)
and merged D (#5). Merge commit `27501da435dfda27a614b934ffbf3135a215d920`
preserves both modules and their tests. D's fixtures and checker are inherited
unchanged from main; fixtures are not copied from another worktree.
The adapter reads repository `fixtures/acceptance` by default. Missing fixtures
fail explicitly; they are never skipped or counted as a pass. Verify with:

```sh
env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test
python3 fixtures/acceptance/check.py
sh scripts/build-app.sh
test -x dist/Bimeron.app/Contents/MacOS/Bimeron
```

Default local checks now pass; see check-results.md for exact counts. The merged
macOS CI workflow runs the same fixture, test, release app build and bundle checks.
No hosted CI result is claimed. Core's guard extension remains the local, unreleased
pinned revision above and must be published in coordination; it is not remotely CI
verified. Recheck the final Core contract before app integration.

Daemon tests use deterministic in-memory observations/exchanges and synthetic bytes.
They do not connect to the production endpoint, authenticate a live root peer,
prove privileged socket security, or verify actual utun/routes/DNS cleanup. The
macOS transport is compiled locally; protected installation/launchd and live
acceptance remain item 10 work. No benchmark is warranted for this small reducer;
I/O remains bounded and cancellable. No app UI is wired in this workstream.
