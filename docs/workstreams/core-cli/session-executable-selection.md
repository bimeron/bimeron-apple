# Session executable selection (issue #32, item 11)

Settings offers an explicit execution consent dialog followed by a native file picker.
Choosing a file authorizes that candidate's `version`, `capabilities`, and subsequent
`validate <staged-file>` commands for this session. Cancelling the picker does not
select or execute a candidate. Nothing is persisted: no paths, bookmarks, or metadata.
Reset restores the original injected CLI, which normally comes from the existing
`BIMERON_CORE_EXECUTABLE` then bundled-executable resolver.

Only selected overrides are probed; existing injected validation-only clients still
work. The candidate must be a regular executable file. Both existing JSON contracts
must decode, both platforms must be `darwin`, and the trimmed version must be nonempty.
Unknown versions and architectures and all-false capabilities are accepted. There is
no validate capability flag or invented minimum version. Metadata is UNTRUSTED
development compatibility, never production release approval, installation approval,
root authorization, or daemon readiness. The UI does not display raw metadata.

Each command has the existing CLI cancellation/timeout handling (10 seconds by
default) and a 64 KiB output capture limit for selected clients. Cancelling or failing
a probe blocks validation until explicit reselect/reset. Generation checks prevent a
superseded probe from committing. Create/save captures a client before awaiting and
blocks selection, reset, and cancellation throughout the operation. Probe errors and
output are reduced to a generic state and are not logged. Draft preservation and
staged validation use the existing library paths.

This is path-based execution, not an immutable binary identity guarantee. Symlinks,
replacement of a path or its target, and other TOCTOU changes between the regular-file
check, metadata commands, and validation are not prevented. A user-selected executable
runs with the application's privileges and can perform arbitrary actions; consent
is required before the first probe. No sandbox, signature verification, install,
daemon integration, or live switching is added. Security-scoped bookmark persistence
is deliberately absent. Picker behavior is not covered by screen automation.

Controlled tests use temporary synthetic shell executables only. Run with
`env -u BIMERON_CORE_EXECUTABLE swift test --filter BimeronAppTests --skip ConfigTextEditorTests` to keep the
separate real-Core offline opt-in disabled.
