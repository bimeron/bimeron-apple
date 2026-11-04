# Isolated SSH authentication preparation

`BimeronSSHAuth` is a Foundation-only value module. It has no diagnostics,
transport, settings, model, application, or daemon dependency. The package registers independent library and test targets; the application
does not depend on this module.

The contract was checked against Bimeron Core commit
`7cc55f07ce2c48be4071b155c3dd58cf925a88ae`, `internal/control/server.go` and
`docs/SSH.MD`. Protocol v1 provides `auth_pending` and `auth_reply`, with
`key_passphrase`, `password`, and `keyboard_interactive` challenges. IDs are
32 lowercase hexadecimal characters and usable once. There are 1–8 prompts,
each at most 256 UTF-8 bytes, with exactly one echo flag and answer per prompt.
Answers are limited to 1024 UTF-8 bytes each; the full request including its
newline is limited to 16 KiB.

## Runtime gate

Runtime sending is **disabled unconditionally**. The pinned Core rejects
instance/session fields on `auth_reply`, so it cannot bind a reply to the
required daemon instance and session. `requireRuntimeSending()` always throws.
There is no capability override, transport, RPC encoder, or sendable reply
type. Validation success grants no permission to send. Parent integration
must keep interactive submission disabled until a separately reviewed Core
contract supports both guards. The module does not poll or perform network I/O.

## State and caller responsibilities

Create one `SSHAuthState` per local connection attempt UUID, Core instance,
and active session. Do not recreate it on every poll or after local cancellation
for the same attempt. Feed only strictly decoded, authenticated, correlated
control responses to `observe`. The control adapter owns raw JSON validation
(including rejecting invalid UTF-8 before a decoder can replace it), duplicate
fields, response limits, request correlation, and daemon authorization. Swift
strings already contain valid Unicode. On malformed responses or transport
failure, cancel the state and dismiss the UI. A response error, including
`unknown_command`, must never be presented as a valid challenge.

Pass the current local scope separately from the response instance/session.
Changed or absent sessions, changed instances/attempts, and unsupported versions
invalidate the state permanently. A new attempt needs a new state. An absent
challenge retires its ID; replaced, changed, or expired IDs cannot be revived
by repeated polls in that state. There is no attempt to enforce Core's global
one-use guarantee locally across distinct attempts; Core remains authoritative.

Core's two-minute timer starts when Core creates its pending challenge. There
is no expiry timestamp on the wire. The local deadline starts at first
observation and never moves on duplicate polls, so it is only a UI ceiling:
Core may already have expired the challenge. Call `expire(now:)` from the UI
timer even without polls, and before displaying retained state. Supply a
nondecreasing local time source; explicit `Date` arguments make tests deterministic.
Local cancel clears prompts and prevents further observations; there is no
`auth_cancel` command. Session stop belongs to the session owner outside this
module and cancels Core's pending challenge.

`validateAnswers` requires the displayed challenge ID and current scope. It
checks count, UTF-8 byte limits, and a conservative JSON-escaped v1 envelope
size without constructing an RPC or retaining answers. Its conservative count
may reject inputs that a less escaping encoder could fit. It does not consume
the challenge or prove that Core still accepts it. A future guarded transport
would need to account for all additional envelope fields before sending.

Prompts originate from the remote SSH server. Render them as untrusted plain
text; obey each echo flag and distinguish key passphrases from account passwords.
Challenge/state descriptions redact IDs and prompt contents. Do not persist,
log, export, put in settings, or pass answers to diagnostics. UI code must clear
its own transient answer fields on dismissal/replacement/invalidation. Swift
strings do not guarantee secure memory zeroization. The separate event adapter
belongs to J and is outside this module.

## File preflight and host verification

`SSHFilePreflight.validate` requires an explicit absolute `known_hosts` path
and optionally an absolute identity path. Each must identify a regular readable
file; relative paths, `~`, directories, missing files, and NUL paths are rejected.
No key contents are loaded or copied. This checks the GUI process's access at
that moment only: it does not prove daemon access, future access, valid file
contents, or host trust. Core opens/parses the files under its own account.

Core owns `known_hosts` parsing and actual remote host-key verification.
Host verification cannot happen before the SSH server handshake supplies its
key. Preflight therefore cannot verify a remote host. There is no autoaccept,
SSH subprocess, live network check, or trust bypass. Establish fingerprints
through a trusted channel before updating `known_hosts`.

## Verification

Tests cover supported kinds, malformed IDs and arrays, prompt/answer UTF-8
boundaries, escaped request limits, scope invalidation, repeated poll deadlines,
absence/replacement/cancel retirement, redacted descriptions, file errors, and
the unconditional runtime gate. They require no SSH server. The library and test targets are registered in `Package.swift`. The existing
macOS CI runs the package tests and release build; no application dependency
or runtime wiring is added.
