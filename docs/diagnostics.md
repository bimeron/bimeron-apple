# Diagnostics history and export

History exists only in the app model's memory. It retains previous GUI attempts
until Clear or app close, with at most 5,000 entries and 4 MiB of UTF-8 message
text. Oldest entries are evicted first; an oversized message keeps a valid UTF-8
prefix. The byte limit covers retained message text, not total process memory.

Save log and Save diagnostics report open the same consent preview. The preview
captures immutable history and metadata when opened. Saving writes that exact
preview as a text file using the system file exporter. No network request is made.
Changing or clearing live history does not change an open preview.

Default exports contain numeric app/macOS versions (or unknown), profile count,
ISO 8601 timestamps with timezone offsets, fixed source/type/outcome values, and
locally generated GUI save-attempt UUIDs. They do not collect configurations,
credentials, access links, SSH file contents, arguments, environment variables,
profile paths, Core session/instance identifiers, authentication payloads, or raw
errors. Arbitrary `record(String)` messages are free text, even when they happen
to contain a fixed localized app message.

Raw Core/user text requires a separate checkbox, off on each preview opening.
The warning explicitly describes sensitive text and the absence of redaction.
Review the complete preview before saving. User notes are not collected.

## Integration

`AppModel.record(DiagnosticEvent)` accepts only fixed enum fields and an optional
GUI attempt UUID; never pass a Core session UUID. `record(String)` remains source
compatible and is excluded by default. `clearLog()` clears both entry and byte
accounting. `diagnosticSnapshot()` freezes history and metadata for preview.

`DiagnosticLifecycleAdapter` consumes existing typed `LifecycleState` observations
and returns events for `record`. It creates no daemon client and establishes no
service readiness. Initial state and state after `lostIPC()` are unknown; IPC loss
does not establish that a previously connected VPN stopped. Integration must feed
observations explicitly. No repair result or repair-success event is provided.

GUI `profileSave` events record started and terminal outcomes for each save attempt.
Success means the update committed or the existing no-op save succeeded. Inside
the existing atomic update validator, `coreCLI` / `validation` events record started
immediately before the actual `CoreCLI.validate` call and success immediately
after it returns. Both use the same GUI attempt UUID. Validation errors are
classified by the outer GUI save outcome; CLI output is never captured. An update that returns or fails before invoking the validator emits no CLI
validation event. The current library validates unchanged saves and checks stale
destination bytes after validation; a CLI success can therefore precede a GUI
save rejection.
Neither validation nor save success establishes network or authentication success.

The snapshot labels the last retained lifecycle event outcome as “Latest retained
lifecycle observation”, or unknown if none is retained. This is historical data,
not a claim about current state or freshness. IPC loss contributes unknown while
earlier connected observations remain in history until evicted or cleared.
