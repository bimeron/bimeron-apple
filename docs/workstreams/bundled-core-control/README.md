# Bundled development Core and guarded GUI control (ba-22 / ba-24)

Tracks #79 and #77, related to #13. Production shipping is **false**. No signing key,
Apple review, authenticated release pin, updater, rollback, or service repair is
provided by this change.

The development app contains one native Core executable built from Git object
`6b0d97a4ac96a903153a57d544751401b98d6909`, its notices, and a native C detach helper.
The builder makes an isolated shared clone and checks out that full commit; it
never builds from or modifies the source repository's working tree. The recipe
requires Go 1.26.9, native Darwin architecture, `CGO_ENABLED=0`, `-mod=readonly`,
`-trimpath`, `-buildvcs=true`, and a fixed development version/build ID. Module
network access and automatic toolchain downloads are disabled during the build.
Cached dependencies are required. CI prepares its dependency cache separately.

Build from the Apple repository root:

```sh
BIMERON_CORE_SOURCE=/absolute/path/to/bimeron-core \
BIMERON_GO=/absolute/path/to/go1.26.9/bin/go \
BIMERON_GIT=/absolute/path/to/git sh scripts/build-app.sh
```

Start reuses a compatible running daemon without approval. If no daemon answers,
Start requests administrator approval through osascript. Cancellation is reported
in English or Russian. An incompatible revision is refused and never replaced
silently. There is no separate Core launch action, launchd service, or autostart.

The administrator script refuses symlinks, non-root ownership, writable ancestry,
and directory ACLs. Root-owned ancestors may use the admin group; the two
Bimeron directories require root:wheel 0755. Before prompting, the GUI refuses
the .app directory or any ancestor owned by another user or world-writable.
Group write is accepted only on root-owned directories (such as /Applications).
The bundled binaries are protected by root re-hashing the staged copies. Paths and
hashes pass as osascript argv and AppleScript quotes each shell argument. It stages **both** bundled executables under
`/Library/Application Support/Bimeron/DevCore`, verifies their SHA256 values from
the development manifest, then installs root:wheel 0755 copies. Only those copies
execute as root. The native helper double-forks, calls setsid, redirects standard
streams to /dev/null, changes cwd to /, and execve's Core with exactly
`BIMERON_CONTROL_UID=<uid>` and `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. An exec failure
is returned through a close-on-exec pipe. Hashes are consistency checks, not
publisher authentication; the app and manifest are locally built and untrusted.

After approval the GUI waits for a compatible handshake before starting the
selected profile. A timeout does not kill or replace a late daemon. There is no
automatic VPN start at boot or on reopen. Protected copies remain after shutdown;
the next authorized launch can replace them. This is development-only, not a
shipping installer or service lifecycle.

The app reconciles with a fresh root-authenticated socket handshake every second
while the main window exists. It requires the pinned daemon's self-reported clean
Darwin revision and v1 session guards before admitting a session Start. This is development
compatibility evidence, not a trust assertion. Start performs another fresh
handshake and passes the selected library config's absolute path unchanged.
Core hashes that path for profile ownership; no config conversion, copying,
normalization, or preference migration occurs. An active session is stopped
before another profile can be started, with the next Start remaining explicit.
Stop uses the daemon instance and session guards; disconnected is displayed only
on authoritative cleanup confirmation. IPC loss remains unknown. Closing/reopening
reconciles and adopts a running session without starting or stopping it.

Core reachability is separate from session state and reconnect reasons. Journal
polls the bounded events RPC with its sequence cursor; Traffic uses the existing
session-bound statistics adapter. The Profiles card keeps one title, one subtitle,
and a compact download/upload total line. Detailed statistics remain hidden until their placement is decided.
An absent Core is shown as Not connected unless it disappeared during a known
active/in-progress session. Cancellation and launch errors appear separately
below the card. Confirmed stopped/inactive terminal status clears the session-loss
warning. About displays the bundled manifest version/short revision and live
daemon reachability. IPC loss
makes live traffic unavailable.

Offline tests use injected daemon exchanges, launch closures, synthetic bundles,
and isolated settings. Actual administrator approval, protected installation,
detach lifetime, VPN and cleanup remain manual acceptance work.

Manual acceptance (user only):

1. With no daemon running, select a real supported profile and press Start. Cancel
   the password prompt: a localized cancellation appears and no session starts.
2. Press Start again, approve the password prompt, and verify connecting then
   connected, Journal entries and increasing Traffic. The daemon must survive the
   administrator prompt returning.
3. Press Stop and verify authoritative disconnected state and restored routes/DNS.
4. Start again, close the app while connected, then reopen. Verify it adopts the
   same session, shows live Journal/Traffic, and neither prompts nor sends Start.
   Stop and verify cleanup again.

Do not stop an unrelated testing daemon to exercise these steps. Coordinate its
shutdown explicitly first. A wrong-revision daemon must show incompatibility
without a prompt or replacement.

Accepted residual risk (development-only): the hashes come from the user-writable
bundle. A same-user attacker who can modify it can obtain root execution after
the user approves. Hashes detect corruption and close the pre-check/copy race:
root re-hashes staged copies in a 0700 mktemp directory before atomic moves.
Protected copies remain after shutdown. Any process of the control user can
control the daemon. Signing and SMAppService are the real production fix.

A partially created Bimeron/ or DevCore/ directory with ownership other than
root:wheel makes Start fail. An administrator must manually remove that directory
before retrying Start; the app does not repair its ownership. The stderr read is
bounded to 64 KiB; the temporary stderr file itself has no size bound.

An inactive terminal failed session keeps its failure reason visible and permits
an explicit Start retry through the reachable daemon without administrator approval.
Disconnected is the other terminal state and already permits Start. Active failed
sessions still require Stop; transitional/unknown states and unconfirmed cleanup
are not treated as authoritative readiness. Failed does not imply confirmed cleanup.

Stop refreshes the daemon handshake before mutating a session, avoiding a stale
Stop after the session has already ended. If failure races with Stop, the app
reports that stopping failed and preserves the daemon reason without claiming
cleanup. Start/Stop failures and launcher errors have English and Russian copy;
unrecognized protocol errors use a localized fallback. Runtime Core diagnostic
reasons remain verbatim.

An initial failed/disconnected inactive snapshot is the daemon's previous session,
so the card shows Not connected and hides that historical reason across repeated
polls. Active sessions are adopted normally. A failure transition observed during
this app run, or a failure after its own explicit Start, remains visible with its
reason. This presentation rule does not change daemon state or retry admission.
