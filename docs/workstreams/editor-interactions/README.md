# Bounded native editor interaction audit

Production base: `f48d9c8b2e9158e82a728d17def3570a2b65197c`, 2026-11-05. Issue: https://github.com/bimeron/bimeron-apple/issues/33. No production defect was established by this audit. Later port-placeholder changes must be evaluated separately; these GUI runs do not validate them.

The unchanged production EditorView ran in a copied temporary package with an explicit temporary ProfileLibrary, MemoryDefaults, synthetic inputs and a scoped mock validator. Sandbox preflight denied outside writes and networking before launch. No AddProfileView, clipboard, file panels, personal profile data, real Core, live connections, permission changes or global input were used. This is not a filesystem read allowlist; ordinary framework/system preference reads remain possible.

## Executed evidence

All four GUI runs exited 1; none is a whole-suite acceptance pass. Exact executed source, runner, hashes, build/preflight logs and interaction logs are retained under `evidence/`. PNGs remain at the original temporary roots and were not individually reviewed for visual quality.

| Evidence directory | Temporary root suffix | Outcome |
| --- | --- | --- |
| initial-locator | Ux43cf | Native labels empty; Server locator failed before mutation. |
| initial-mapping | Ep2hqT | AX labeled Server found, native bounds mapping failed. |
| diagnostic | K7jHcD | Captured AX/native rectangles: two-point inset per horizontal edge. |
| verification | HalW8Z | Unique per-edge matching enabled field edits; later stopped at checkbox locator. |

Verification observed Server/Port field editing propagated to explicit Raw fields, generated URI endpoints or decoded VMess JSON for all 14 variants. Revisiting all variants after intervening edits retained those endpoints. Selected secret/UUID fields accepted native text and used secure controls; secret/UUID serialization or persistence was not asserted. Generated Raw source changes blocked returning to the form, Restore recovered exact draft bytes, and mock Save persisted those bytes exactly once.

The Name field accepted an edit in EN/light, and a secure control was present in the imported-link form. The assertion did not identify that control as the link specifically; no field-specific masking acceptance is claimed. The run stopped at the Show access key helper because AX exposes an adjacent label and unlabeled checkbox. This is a harness locator blocker, not a demonstrated user accessibility defect.

After that blocker, independent scenarios in the same launch exercised native Raw editing and exact-byte mock save, then visible mock rejection in EN/RU and light/dark. The rejected saves used unchanged profiles; stored bytes stayed equal, which does not prove rejection protection for proposed dirty changes. Forced sheet cleanup was not Cancel/Discard acceptance. The original error was rethrown and no COMPLETE marker emitted.

`evidence/targeted-tests.log` records 31 existing targeted tests passing on the original base, including draft guards, Restore, protected save failures, localization and ConfigTextEditor behavior. Model/controller results are separate from native UI field acceptance.

## Limits and review

Full field/picker coverage, reveal, subsequent focus/cancel, physical Return/Escape, VoiceOver, layout quality, real Core validation and application lifecycle remain unverified. No production selector changes were made to facilitate tests. Screen reservation was explicitly released after the two bounded diagnostic/verification launches.

Independent Sol Low review confirmed retained partial results and identified four evidence limits: secret persistence, unchanged rejection fixtures, generic secure-control assertions, and potential completion after unsupported cancellation. Claims above reflect those limits. Subsequent harness-only corrections are not retroactive GUI execution evidence.

## Requested port-placeholder change

New creation forms keep the port text empty and show a protocol-specific prompt: SS 8388, SOCKS5 1080, SSH 22, HTTP 8080, and 443 for the remaining variants. Serialization uses the effective numeric default. Explicit input is retained per protocol; clearing returns to the prompt/default. Existing/imported values remain explicit; Raw source authority is preserved. Empty-versus-explicit state is editor-only, so reopening a saved profile displays its serialized numeric port.

Four regression tests cover defaults across all variants, explicit/default/cleared draft switches, generated URI endpoints, imported values and Raw edits. Final local package checks passed: 89 Swift Testing tests and 35 XCTest cases (one XCTest skipped), with optional real-Core creation validation skipped because no executable was configured. Logs: `evidence/port-final-tests.log` and `evidence/port-targeted-tests.log`. Independent Sol Low review found no confirmed material regressions. No GUI launch tested this change; earlier native audit evidence remains bound to its unchanged base.
