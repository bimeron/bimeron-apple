# Historical H-only UI audit evidence

Audited production source: `ace5610e9e3817fb9238f256915898f95ab38f48`.
Date: 2026-11-04. Isolated worktree: `test-local-profile-ui-audit`.
Environment: macOS 26.5 (25F71), arm64, Apple Swift 6.1.2.
No production source changes, remote operations, installation, VPN/SSH activation or live networking were performed.

## Publication scope

Published separately on baseline `859f15b33e915be75506faf6409488da2936dccb`. All results below describe the earlier H-only run, not a rerun of that baseline. The original full archive remains in local commit `3370283` on branch `test/local-profile-ui-audit`. This publication retains four logs and the two visually inspected screenshots; the other 54 images and superseded rendering harness are intentionally omitted. R owns the integrated interactive harness and integrated acceptance report; this archive contributes exact H-only offline-Core/build provenance and the original timeout failure, not a second harness. Later integrated evidence can cover checks marked unexecuted here.

## Isolation and tooling

The T3 tool catalog exposes browser and mobile-device automation, not native macOS window automation. A local, non-prompting `AXIsProcessTrusted()` probe returned true and AppKit reported one screen. This means Accessibility permission is available; it does **not** mean VoiceOver or interactive accessibility validation ran. No permissions were granted or settings changed.

The exact H executable was independently built in debug and release, but was not launched: `BimeronApp` constructs the default AppModel, which uses `UserDefaults.standard` and `ProfileLibrary.defaultDirectory()` (Application Support/Bimeron/Profiles). There is no explicit isolated launch configuration in that entry point. Merely changing HOME is not verified isolation for Foundation preferences or home-directory APIs. At the time of this run, an isolated executable harness with an event loop and native interaction driver had not yet been prepared in this workstream; OS permission was not the blocker. This is a historical tooling limitation, not a claim that later R/P harnesses are unavailable.

Instead, a temporary test file instantiated the unchanged EditorView with an explicitly injected ProfileLibrary under this audit's evidence directory, a unique UserDefaults suite, and `coreCLI: nil`. The suite was removed on completion. It did not instantiate AddProfileView, read the clipboard or SSH defaults, call load/save, or start the main application. The original rendering harness is preserved in local commit `3370283`, outside the normal test target. It is not republished because R owns the more complete integrated harness.

## Observed evidence

- Independent `swift build --disable-automatic-resolution`: passed.
- Independent `swift build -c release --disable-automatic-resolution`: passed.
- Native NSHostingView rendering completed for SS, SOCKS5, VLESS, SSH, Trojan, HTTP, HTTPS, Naive H2, MASQUE, Hysteria2, VMess, TUIC, AnyTLS and Naive QUIC, in EN/RU and light/dark: 56 PNGs, 760 × 600 points. These show **only the initial General tab of existing-profile editing**. They do not establish coverage of protocol fields or creation forms.
- Visually inspected `VMess-ru-light.png` and `SS-en-dark.png`: headings, tabs, General fields, footer and Save/Cancel fit at this size; localized labels and theme rendering are visible. Remaining images were generated, not individually visually reviewed. No layout pass is claimed for other tabs, sizes or states.
- Full suite with temporary rendering harness and `BIMERON_CORE_EXECUTABLE=/tmp/bimeron-h-core-beta2-cli`: 81 tests, failed with two expectations in the timeout argument of `B-TIMEOUT / B-CANCEL: resistant process is reaped` (missing `ready` and PID). The rendering test and all 14 real offline Core variant arguments passed. A focused rerun of CoreCLITests passed all 14 tests. Timing sensitivity under concurrent rendering/build load is plausible, not proven; the initial failure remains recorded.
- Existing tests passed for generated/Raw authority, conflicting-schema restore refusal, save guards, failed creation cleanup, cancellation before commit and committed-save success. These are model/component tests, not physical Save/Cancel interactions.

Offline Core executable SHA-256: `342adbaf4da760e1eec3dcf2c6032d124149a6bed69de8712264852a28599038`. Existing H documentation attributes it to source-built beta2 `66d84d8`; this audit reused the local binary and did not independently rebuild its provenance. Only validation tests were invoked; no release/runtime compatibility acceptance is implied.

## Findings and remaining checks

No confirmed production UI defect was established by the limited render inspection. Do not interpret that as an interactive UI pass.

P2 test reliability observation: the resistant-process timeout fixture failed during the full audit run and passed alone. Reproduce with the full command above, compare `evidence/tests.log` and `evidence/core-retry.log`; owner investigation is needed before attributing the cause.

Unverified source-level risk: EditorView displays errors with `.lineLimit(2)` and no explicit expanded detail control. Long filesystem/Core errors may be truncated. Reproduce in an isolated interactive harness using a long validation failure in RU/EN at minimum editor size. Severity remains provisional P2 until an actual inaccessible diagnostic is demonstrated; no fix was made.

Still unexecuted: all 14 protocol-specific creation/edit forms, protocol draft switching, Raw edits and restore through UI, actual create/save/cancel/discard/error presentation, validation-in-progress cancellation, Return/Escape, Tab/Shift-Tab order, focus visibility and restoration, application command shortcuts, VoiceOver navigation/announcements, clipping/scrolling at other sizes and all tabs in RU/EN light/dark. These were unexecuted in this historical run; consult the later integrated audit for subsequent coverage. VoiceOver was not activated because doing so would change the current user session's accessibility state. Existing AX trust alone cannot provide VoiceOver speech evidence.

No production preferences/profile store were intentionally read or modified by an app launch; the app was never launched. Existing tests sometimes construct default AppModel instances, but their persistence mutations use unique suites and profile operations use temporary injected libraries. No hosted CI run or equivalence is claimed. Paused owner threads were not contacted.
