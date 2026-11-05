# Window lifecycle

Closing the main window with the red close button or Cmd+W must leave the GUI
process and menu bar menu running. Open Bimeron reopens or brings forward the
existing single `Window` scene with ID `main`, then activates the application
using the macOS 14 API.

`AppDelegate` opts out of termination after the last window closes and is wired
through `NSApplicationDelegateAdaptor`. Explicit Quit actions and Cmd+Q remain
unchanged. This change does not alter daemon policy, defaults, Settings,
`AppModel`, localizations, core integration, staging, or CI. It adds no startup
guard or lifecycle framework.

## Verification

Run `swift build` and suitable offline tests without launching the app or using
real user profiles or defaults. A test that merely calls the delegate and checks
`false` would only repeat its implementation; no such test is added. Offline
tests do not establish native process lifetime, menu persistence, window reuse,
or activation behavior.

Implementation checks passed: `swift build`, `git diff --check`, and four existing
offline tests selected with `swift test --filter`:

- `editorCreationRequiresActualCLIAndRetainsDraftOnFailure`
- `unifiedAddImportsQuotedFileAndAddsQuotedURIWithLocalChecks`
- `editorSaveUsesProtectedExactBytesAndPreservesFailures`
- `translationResourcesResolve`

The model tests use temporary profile directories, isolated defaults, and fixture
CLI executables. These are regression checks, not native lifecycle acceptance.

Independent Sol LOW review found no actionable issues. The broader offline run
`swift test --skip ConfigTextEditorTests --skip offlineCore --skip OfflineCore`
also passed (83 Swift Testing tests; XCTest suite passed with the opt-in local
Core vectors test skipped). No native UI was launched.

Native acceptance remains unverified in this workstream. A separately authorized
UI check should use isolated data and verify red close and Cmd+W, menu persistence,
Open Bimeron with both a closed and an already open main window, repeated Open
without duplicate windows, and unchanged explicit Quit and Cmd+Q behavior.
