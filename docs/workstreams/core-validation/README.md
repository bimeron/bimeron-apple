# Editor validation before replacement

Issue: https://github.com/bimeron/bimeron-apple/issues/10

## Scope and provenance

This implements the approved validation-only stage using the existing CoreCLI
adapter. The Core beta.2 contract supports `validate <file>`; it does not expose
the proposed document API. That integration is deferred, with no simulated bridge
or version compatibility policy. Source baseline B is pinned to `66d84d8`; see
`../core-cli/CONTRACT.md` and its parser samples for their evidence and limits.
The desktop editing contract supplied for this work was
`/tmp/bimeron-desktop-audit.XrKHna/docs/gui-profile-editing-contract.md`.

Only editor saves use Core validation. Add, import, restore and the existing
synchronous library update keep their previous local validation behavior.
No Core source, installation, service, networking or runtime integration changes
are included. Static validation success makes no claim about a running daemon,
platform support at runtime, server credentials or connectivity.

## Developer executable configuration

Set `BIMERON_CORE_EXECUTABLE` to an absolute executable path in the app's launch
environment. Relative paths block saving. Without this variable, the app looks
for the bundled auxiliary executable `bimeron-core`. There is no executable
selection or installation UI. Missing or unlaunchable Core blocks editor saving;
there is no local-only fallback. Tests inject a CoreCLI with a fake executable.

## Save and cancellation behavior

The editor keeps its original immutable and snapshots its draft. Local checks
precede staging. The library writes a uniquely named 0600 temporary file inside
the profile directory, preserving relative-reference context. Core validates that
file. After validation, the library checks the original against the editor's
expected bytes and checks staged bytes against the draft. It restores protected
permissions and creation time, checks cancellation, then atomically renames the
staged file over the profile. Temporary files are removed on success and failure.
The actor performs the final checks and rename without suspension, so concurrent
library replacements cannot interleave there. External processes are not locked;
an external write racing the final filesystem operations remains a limitation.

Editing is disabled while saving. The editor owns the save task and cancels it on
Cancel, explicit discard or disappearance. Cancel retains the draft until the
user explicitly discards it. Failures retain both original and draft. Core errors
are mapped to localized categories; output and diagnostic descriptions are never
shown or logged by this save path.

## Verification and limits

`EditorSaveTests` exercises the actual AppModel editor-save path using shell fake
executables: exact staged/committed bytes, profile-directory placement, 0600,
BOM/CRLF/missing-final-newline no-op preservation, nonzero output redaction,
missing executable, timeout, pending cancellation, stale original and cleanup.
A reentrant library test replaces the profile during validation and verifies the
stale save cannot overwrite it. Existing profile-preservation and portable
fixture checks remain applicable to local editing semantics (stage A).

These are regression tests of orchestration, not live Core validation evidence.
SwiftUI dismissal and discard interactions are code-reviewed rather than driven
by UI automation. The document bridge and runtime/service acceptance remain
unimplemented and unverified.
