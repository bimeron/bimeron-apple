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

The final P1 review found that Raw's AppKit text view ignored SwiftUI's disabled
state, allowing draft edits during validation that a successful snapshot save
could discard. `ConfigTextEditor` now applies the environment's `isEnabled` to
`NSTextView.isEditable` at creation and before the unchanged-text early return.
A hosted SwiftUI/AppKit wrapper regression covers initial disabled creation and
enable/disable/re-enable with unchanged text, retaining the same text view,
selection, selectable reading and exact content. Removing the propagation makes
this regression fail for both initial creation and the disabled update.

These are regression tests of orchestration, not live Core validation evidence.
SwiftUI dismissal and discard interactions are code-reviewed rather than driven
by UI automation. The document bridge and runtime/service acceptance remain
unimplemented and unverified.

## Combined C and F integration evidence

Integrated fetched main `5a008fe6848fb353f77a5b70a230b17871c96d7e`
(C, PR #9) into F baseline `532e12f0d3199669a8c10b304c9ccc09b8e64da7`
(PR #11) on 2026-11-04. The merge had no textual conflicts. All eight
package targets remain: BimeronModel, BimeronDaemon, BimeronCoreCLI,
BimeronApp, BimeronModelTests, BimeronDaemonTests, BimeronCoreCLITests and
BimeronAppTests. The app explicitly depends on model, daemon lifecycle and
CoreCLI modules.

C has no AppModel/UI integration or executable resolver: its transport attaches
to the fixed privileged daemon socket. F's AppModel continues to resolve one
CoreCLI executable from `BIMERON_CORE_EXECUTABLE` or the bundled auxiliary
executable for editor validation. There is no competing configured executable
location to reconcile. Absent or unlaunchable Core explicitly blocks editor save;
add, import and restore retain their existing local-validation scope. No new
runtime wiring or architecture was introduced: privileged daemon/utun ownership
remains with Core, with no Network Extension or unguarded/local-only fallback.

Combined local checks (default fixture root; no fixture override):

- `swift test`: passed, 15 XCTest tests and 59 Swift Testing tests (74 total),
  zero failures. This includes all C lifecycle/client/protocol tests and F editor
  save regression coverage.
- `python3 fixtures/acceptance/check.py`: passed, 26 scenarios and 29 fixture
  files; also rejected byte corruption, missing coverage and unsafe lifecycle
  expectations. This is offline integrity evidence only.
- `sh scripts/build-app.sh`: passed, release app bundle rebuilt successfully.
- `test -x dist/Bimeron.app/Contents/MacOS/Bimeron`: passed.
- `plutil -lint dist/Bimeron.app/Contents/Info.plist`: OK.
- `git diff --check` and `git diff --cached --check`: passed.

These checks do not establish live acceptance. CoreCLI shell-fake validation is
not live Core acceptance; daemon tests use synthetic exchanges. No Core edits,
installation, production socket access, live networking or runtime sessions were
performed. Privileged peer authentication, utun/routes/DNS cleanup, protected
installation/launchd, SwiftUI interaction automation and hosted CI remain
unverified here. The document API remains deferred under the contract above.
