# Local integrated UI audit

## Provenance and boundary

Tested production commit: `bfa86381313eb2ec132c803c20528613dbdb1914` (K15 + I18 + J19 + H21). Worktree: `/Users/wrk/.t3/worktrees/bimeron-macos/test-integrated-ui-audit`. Date: 2026-11-04. The P harness was copied as files from its bound worktree, without cherry-picking history. Production Sources, Package.swift and Tests are unchanged. The runner refuses dirty production inputs, compares every copied source/resource byte, records SHA-256 hashes, and omits only the application entry point. Retained harness/runner files identify each executed driver version.

The actual production views run on the main-thread NSApplication event loop. ProfileLibrary is explicitly temporary; AppModel defaults use the inherited in-memory subclass. Sandbox preflight requires a temporary write to succeed, an outside write to fail and loopback networking to fail with EPERM before any window appears. The inherited sandbox denies all outside writes, network access, actual Bimeron profile/preference reads and actual `.ssh` reads. This is not a general filesystem read allowlist; frameworks can read ordinary system preferences. HOME redirection alone is not treated as isolation proof. No permission prompt, OS setting change or global input/window inspection is used. AX is restricted to this process and events to its own sheet.

AddProfileView remains excluded: onAppear and its timer read NSPasteboard.general, and HOME does not isolate that service. No clipboard read/write, import acceptance, SSH file browsing or file panel is claimed. DiagnosticExportView is instantiated safely, but its Save button is never pressed because that opens a file exporter. No actual daemon/connection is started. Validation uses only the scoped temporary stub, never real Core. I has no application dependency/UI and runtime replies remain disabled; authentication acceptance is not wired and was not simulated. J lifecycle adapters are not actual runtime feeding.

## Evidence and bounded results

`evidence/matrix-run/` retains the first integrated run, `/private/tmp/bimeron-isolated-ui.FMJysE`. It completed all 56 initial protocol-tab cases before stopping at an unsupported K locator. Its exit 1 is retained, not relabeled as a successful whole run. An earlier build-only attempt `/private/tmp/bimeron-isolated-ui.tCOuyx` failed because the added harness called nonexistent `appendLog`; changed to the existing `record` API before any UI launched.

Observed in the first integrated run:

- Mock-backed create persists one profile; native Raw edit saves a changed name without duplication.
- Missing Core and invalid Raw expose visible errors; invalid Raw blocks returning to General.
- Mock rejection retains editor and persisted bytes. Unchanged Cancel dismisses; dirty Cancel → Keep editing retains the draft; Cancel → Discard dismisses without changing stored text.
- All 14 existing-profile protocol tabs were navigated in EN/RU and light/dark (56 assertions and PNGs). This is not all-field or all-protocol creation acceptance.
- Tab from a cleared responder enters a native field. Local Return did not expose the offline error; local Escape dismissed the invalid Raw sheet without establishing discard semantics. As in P, direct event dispatch is not physical keyboard acceptance or proof of a product shortcut bug.

## Findings and repro

No confirmed production defect is established by these observations. The following are coverage blockers, not bug claims:

- **K / medium audit gap:** open unchanged ProfilesView after loading the H-edited synthetic profile. Own-process AX exposes `AXScrollArea → AXOpaqueProviderGroup` without profile row controls. Attempting the row locator failed. Selection, Edit routing, scrolling and focus restoration therefore have no integrated interaction pass. Do not infer a VoiceOver defect from this harness alone. The driver records this explicitly as BLOCKED on subsequent runs.
- **Import / medium audit gap:** AddProfileView cannot be instantiated under the current unchanged-source harness without reading the shared clipboard. File panels cannot be safely constrained by this harness. Both remain unlaunched.
- **Keyboard/accessibility / medium audit gap:** full Tab/Shift-Tab order, physical Return/Escape, VoiceOver speech, profile focus restoration and validation-in-progress cancellation require bounded manual acceptance later. No user session or accessibility settings were changed.
- **Core/runtime / delivery gap:** no trusted pinned Core candidate is established here. Optional beta2 validation was not run. Mock results establish UI/staging behavior only; no daemon handshake, VPN, SSH authentication or network acceptance is claimed.

## Checks and held work

Local package tests: 85 Swift Testing + 23 XCTest, zero failures; optional offline Core test skipped with Core unset. Fixture checker: 26 scenarios / 29 files and all three negative checks passed, integrity only. Exact logs are retained in `evidence/`. Shell syntax and Git whitespace checks are run on the final harness/report.

No remote writes, push, issues, PR, CI, watchers, tags, releases, privileged installation, live VPN/SSH or owner wakeups were performed. No production fix or architecture change was made. Existing P screenshots were not reused as integrated evidence. PNG creation is not itself a visual layout pass. Temporary packages and all matrix PNGs remain under their recorded run roots; selected evidence is retained here.

Development runs retained separately: `evidence/generated-locator-failure/` (`65ZgUu`) stopped because the protocol popup's AX value is `SS`, not its adjacent `Protocol` label. `evidence/restore-ax-failure/` (`23MfBm`) selected AnyTLS and observed the generated Raw guard, then stopped on Restore's raw AX status `-25200`. Like Save/Cancel, Restore can change the element while AX returns; the final driver attempts it once and checks resulting native text. Neither harness failure is counted as a production bug or silently removed.

The auditor visually inspected the integrated Raw syntax-error, mock-rejection and VMess RU dark PNGs: short error messages and the localized masked-link layout are visible. Other matrix PNGs are navigation evidence, not individually reviewed layout passes.

## Final targeted run

`/private/tmp/bimeron-isolated-ui.uD1Oj0`, exit 0, with `HARNESS_SKIP_MATRIX=1`; exact executed files, logs, hashes and four new screenshots are in `evidence/final-run/`. The matrix was intentionally not repeated; the earlier integrated 56-case run remains its evidence. The final driver also repeats create/edit/error/cancel assertions and contains no FAIL lines. K remains explicitly BLOCKED, even though the supported checks complete.

Additional observed passes:

- Own-process AX selects AnyTLS from the actual creation picker. A native Raw edit replaces its source with a synthetic valid link. Protocol navigation is refused with the generated-source warning. One Restore attempt preserves the Raw-edited profile name and removes the custom endpoint, then Protocol navigation succeeds. Dirty discard dismisses. This verifies source authority/restore guards, not all generated protocols, parameter entry or real Core acceptance.
- The J snapshot contains validation events from H editing. Its actual preview excludes synthetic free text by default; consent reveals it; append and clear of the live log do not change the displayed frozen snapshot. Revoking consent hides it, Cancel dismisses, and reopening defaults to exclusion. No exporter or file save was opened.

These are unchanged production views hosted individually, not MainWindow/application-command end-to-end acceptance. K→H callback delivery could not be completed because of the recorded AX blocker. I authentication remains not wired. No conclusion about live lifecycle follows from J's retained validation events.

Reproduce locally with `scripts/local-ui-harness/run.sh`; to repeat only the targeted cross-feature checks plus base editor checks, use `HARNESS_SKIP_MATRIX=1 scripts/local-ui-harness/run.sh`. Requires existing Accessibility trust, never requests it. Own windows only; no global input injection. Run roots are intentionally retained for inspection.

Final executed driver SHA-256: `2e0caf25d0d7f5a4450f289f163af97a753da7d74bd16482463ae2a71584708f`; runner: `ea9635cd2cba6970994134d173ae99c4d0cbeba0a171b8879da42d6f9ba7f72a`. Both retained files match the final tracked harness files byte-for-byte.

Visual capture limitation: the auditor opened `diagnostics-opt-in-frozen.png`; the cache-display image has an unreadable dark/transparent text/background presentation in the image viewer, although native controls and the scrollbar appear. Thus the diagnostic PNG is retained as a capture limitation and is **not** a visual preview readability pass. J consent/content/freeze assertions above are own-process AX evidence only. No production rendering defect is inferred. The production editor screenshots listed above remain separately inspected evidence.

Retained `.log` files normalize trailing whitespace for repository hygiene; raw logs remain at the recorded temporary run roots. No statuses or message content were removed. The initial whitespace check flagged AX dump trailing spaces; after normalization, the staged whitespace check passed.

## Source-only publication on current main

The publication branch starts at `859f15b33e915be75506faf6409488da2936dccb` (main) and cherry-picks only original R audit commit `a81d97b208370ff95207668956f55b507acc8007`. Original branch/history and all earlier evidence remain preserved. No historical KIJH merge commits are imported. The delta contains only this report/evidence and `scripts/local-ui-harness`; no product, package, tests or shared CI changes.

For publication, `HARNESS_BUILD_ONLY=1 scripts/local-ui-harness/run.sh` compiles byte-verified copied production sources with the harness, then exits before sandbox preflight or any AppKit/AX launch. This mode passed against current-main production sources, run `/private/tmp/bimeron-isolated-ui.4tfsSi`; provenance records publication intermediate commit `d85ecf6` whose production sources equal the stated base. Package tests passed again (85 Swift Testing + 23 XCTest); fixture integrity/negative checks, shell syntax and whitespace checks passed. New compile/test logs and source hashes are in `evidence/publication/`.

Historical native interaction results above remain bound exclusively to `bfa86381313eb2ec132c803c20528613dbdb1914`. No latest-main UI acceptance, sandbox execution, Core validation, installation or live runtime is claimed by the new build-only check. The earlier byte-match statement about the retained final driver/runner describes the original audit commit; the publication runner adds the build-only exit while the historical runner remains intact. The harness is intentionally local/macOS-specific and uses the scoped `/Users/wrk/.local/bin/git` wrapper. Existing AX trust is required only for interactive runs, not compilation.

Parent source review confirmed the build-only path exits before mock creation, sandbox preflight and UI execution, and that the delta does not change application behavior or CI. K, clipboard/panels, physical keyboard, VoiceOver and diagnostics image limitations remain unresolved. Hosted PR checks may initially be pending; no self-hosted allowlist changes, manual workflow dispatch or watcher are part of this publication.
