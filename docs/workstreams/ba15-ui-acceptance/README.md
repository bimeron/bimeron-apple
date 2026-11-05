# BA15 bounded isolated UI acceptance

Status: the sixth separately authorized owner run naturally exited 0 and completed the bounded sequence, including unique composite-label row selection and owned Edit-sheet presentation. Latest-run evidence includes four successful sidebar AX presses/routes, twelve synthetic fixtures with nil initial selection, fourteen captures and an AX dump. All fourteen latest PNGs are byte-identical to corresponding individually inspected fourth-run images. This is not full ba15 completion or native full-application acceptance. The slot is released, processes ended, and no retries are authorized. No production regression is demonstrated and no production fix was made; ba14 remains untouched.

From this worktree, the owner can run:

```sh
zsh scripts/ba15-ui-acceptance/run.sh
```

This is a separate runner, not a mode of `scripts/local-ui-harness/run.sh`. It never updates shared audit pointers or runs the existing editor matrix or package test suite. It builds a temporary copied package, then launches a replacement NSApplication host, not the production application entry point. Production sources/resources are byte compared and hashed before adding the driver; the omitted entry point is explicitly hashed and marked OMITTED. Original and temporary manifests, driver/runner hashes, commands, build/preflight/interaction logs and own-window captures are retained under the printed `/private/tmp/bimeron-ba15-ui.*` root. Only the temporary manifest loses test-target declarations and the test-only SelectionFreezeGate executable declaration. Its exact declaration is asserted before removal; its support directory is neither copied nor built. Repository Package.swift remains unchanged, and both original and transformed manifests are retained and hashed.

## Failed owner attempts

The owner ran the original runner once: `/private/tmp/bimeron-ba15-ui.qPvHTG/evidence/build.log` records `invalid custom path 'Tests/Support/SelectionFreezeGate' for target 'SelectionFreezeGate'`. The copied manifest retained that test-support executable while the runner copied only Sources. The process naturally exited 1 before sandbox preflight or GUI launch. That attempt supplies no native UI evidence. The minimal correction excludes the now-unused test-support target from the temporary manifest alongside its consuming test targets. The second attempt advanced to compilation, but did not complete a build; the original attempt's evidence remains untouched.

The second authorized owner run, `/private/tmp/bimeron-ba15-ui.lqiiDh/evidence/build.log`, naturally exited 1 during compilation: `Thread.isMainThread` was rejected in async `Driver.run()` at line 90. Sandbox preflight and GUI launch did not execute. The source correction moves that same actual thread query into synchronous `onMainThread()`, called from the async MainActor driver, matching the existing shared harness pattern. The check remains enabled. That correction was initially returned without execution; the third owner attempt below subsequently built it. Both earlier failed attempts retain their original evidence; neither contributes native passes or captures.

## Third owner attempt: partial native evidence

Exact command: `zsh scripts/ba15-ui-acceptance/run.sh`. Evidence: `/private/tmp/bimeron-ba15-ui.SbQXgG/evidence`. The separately granted single run built successfully in 22.72 seconds. Filesystem sandbox preflight allowed the root write and denied the sibling write. Network denial was not dynamically probed.

The owned host performed four own-process native AX presses: Settings, Log, About and Profiles, each returning status 0, with four successful model route assertions. It retained one PNG, `empty-minimum-en-light.png`, at 720 × 600 EN/light. The owner visually inspected that PNG: sidebar, status card with wrapped subtitle, empty state and footer were all visible, with no clipping apparent. This is a bounded visual observation of that captured state only.

Synthetic fixture setup then failed saving the temporary root's `profiles/order.json`, with NSCocoaError 513 and underlying POSIX EPERM under the sandbox. The process naturally exited 1. The twelve-profile setup did not complete; no populated size/language/theme matrix, row selection, Edit routing, keyboard or VoiceOver acceptance followed. This failure is an isolated harness/setup blocker, not an established production regression. No runner or production correction or retry was made after this result. The first two failed attempts above remain preserved.

This run establishes only the stated empty-state visual observation and isolated sidebar actions. It does not establish whole-task acceptance, production application commands, native full-app E2E or live runtime behavior.

## Approved fixture-only correction after the third attempt

The fixture loop now uses `try await library.restore(StoredProfile(document: document))` instead of `_ = try await library.add(document)`. This private synthetic setup bypasses Foundation atomic order-file creation; it is not proof of Add behavior or order persistence. The observed failure was Add's `order.json` atomic write before profile save. The exact rejected syscall and temporary path were not logged, so an external-staging cause remains unproven.

Restore follows save → stage with a UUID `.tmp` file and rename within the private root. With no order file, load uses the existing numbered-name sort. The sandbox, twelve-profile count, selection checks and all other assertions remain unchanged. Prior evidence is retained, and no production file changed. This correction was returned without execution, then exercised in the fourth owner attempt below; no further runtime slot is granted.

## Fourth owner attempt: fixture and layout evidence, diagnostic blocker

Exact command: `zsh scripts/ba15-ui-acceptance/run.sh`. Evidence: `/private/tmp/bimeron-ba15-ui.d8kcLS/evidence`. This separately authorized single run naturally exited 1. Build passed in 29.03 seconds. Sandbox preflight allowed the private-root write and denied the sibling write; no network probe ran. Four native own-process sidebar AX presses and four route assertions passed. Restore-based setup loaded twelve synthetic profiles with nil selection successfully; this is not Add or order-persistence acceptance.

The run generated fourteen PNGs: one empty-state capture, one populated-minimum capture, and twelve populated captures covering three sizes in EN/RU light/dark. The owner's initial review inspected these three fourth-run images:

- `populated-720x600-ru-dark.png`
- `populated-855x628-en-light.png`
- `populated-1100x800-ru-light.png`

The owner subsequently inspected the other eleven images individually, completing visual review of all fourteen fourth-run PNGs. Across the captures, sidebar, status card, count, list or empty state, and footer were visible without apparent overlap. At width 720 the status subtitle wraps to two lines; at 855 and 1100 it fits on one line. Long profile names ellipsize at 720/855 and fit at 1100. The partial bottom row at 855 is list viewport clipping, not an established regression. In dark appearance, the enabled Add button looks muted gray but its label remains legible; no contrast measurement or focus assertion was performed. No production layout regression was demonstrated in these captures. These are bounded visual observations, not interaction or full-application acceptance.

After captures, `dumpTree()` failed with EPERM while using `String.write(atomically: true)` for the private `own-process-ax.txt` diagnostic artifact. The exact rejected syscall/path is unknown. The failure occurred before row selection or Edit, so neither has acceptance evidence from this run. No diagnostic artifact correction or retry was performed. All three earlier roots (`qPvHTG`, `lqiiDh`, `SbQXgG`) and their evidence remain preserved.

## Approved diagnostic-only correction and write audit

After main authorization, a read-only audit of Harness.swift and run.sh confirmed two Swift diagnostic artifact write sites: `capture()` uses `Data.write(to:)` with default options `[]`, already non-atomic and successful for all fourteen fourth-run PNGs; `dumpTree()` used `String.write(atomically: true)` for the private AX text artifact. The runner's Python `write_text`, `cp` and shell redirects do not use the Foundation atomic-write option. No other diagnostic write shares that dependency.

Only `dumpTree()` changed to `atomically: false`. Fixture setup, sandbox, assertions and production files remain unchanged. This is a diagnostic-only private evidence write correction; it does not establish the cause of the earlier EPERM. The exact rejected syscall/path remains unknown. Prior evidence remains untouched. The correction was initially returned source-only, then executed in the separately authorized fifth run below. Add/order persistence, scrolling, selection/Edit, keyboard, VoiceOver, full application and live runtime remain unproved; no product regression or fix is claimed.

## Fifth owner attempt: bounded completion with locator blocker

Exact command: `zsh scripts/ba15-ui-acceptance/run.sh`. Evidence: `/private/tmp/bimeron-ba15-ui.CVRnjM/evidence`. The separately authorized single run naturally exited 0; build passed in 25.20 seconds. Filesystem preflight allowed the private-root write and denied the sibling write. Network denial was not dynamically probed. Four own-process native sidebar AX presses returned status 0 and four route assertions passed. Twelve restore-based synthetic fixtures and nil selection passed. Fourteen PNGs were generated. The owner subsequently compared every PNG's bytes with its corresponding fourth-run image: 14/14 were identical. Thus the previously recorded visual findings describe identical image content; this is byte-comparison evidence, not a new individual visual inspection, physical interaction or native interaction acceptance. The AX dump successfully saved to `own-process-ax.txt`.

Row selection remained BLOCKED by the driver's name-only exact locator. The current AX tree exposes actual row AXButtons under `AXOpaqueProviderGroup`: the first row's label is the full synthetic profile name followed by `, SOCKS5 · System VPN`. The executed driver's exact name-only comparison did not match that composed label. This is a demonstrated harness locator mismatch, not absent row AX exposure or a VoiceOver defect. No fallback was performed. Selection/Edit, scrolling, keyboard, VoiceOver, full-application/live behavior and Add/order persistence therefore have no acceptance pass from this run. Exit 0/COMPLETE covers the bounded supported sequence only, not whole-task acceptance.

The slot is released. No harness or production changes accompany this report. All four earlier evidence roots (`qPvHTG`, `lqiiDh`, `SbQXgG`, `d8kcLS`) remain preserved, including their natural failures and the unknown rejected syscall/path from the atomic AX write failure. No production regression or fix is claimed.

## Approved unique composite row locator correction

After main authorization, only the row locator now matches the exact known composite label: full fixture name + `, SOCKS5 · System VPN`. It filters AXButtons and requires exactly one match. Zero matches log BLOCKED unsupported; multiple matches log BLOCKED ambiguous. There is no name-only, substring or coordinate fallback and no production accessibility change. The existing sidebar helper remains unchanged.

The remaining sequence after the existing matrix is AX dump → unique composite row match → one native AX press → unchanged `selectedID == profile.id` assertion → Edit AX press once → owned attached-sheet assertion. This correction was initially returned without execution, then exercised in the separately authorized sixth run below. All five earlier evidence roots remain preserved. Save, Add/order persistence, scrolling, keyboard, VoiceOver and full-app/live acceptance are not established.

## Sixth owner attempt: bounded row selection and Edit presentation

Exact command: `zsh scripts/ba15-ui-acceptance/run.sh`. Evidence: `/private/tmp/bimeron-ba15-ui.5kWWcB/evidence`. The separately authorized single run naturally exited 0; build passed in 21.71 seconds. Four native own-process sidebar AX presses returned status 0 and four route assertions passed. Twelve restore-based fixtures with nil initial selection passed. Fourteen PNGs and the AX dump were retained.

The exact composite row locator matched uniquely. One native AX row press returned status 0, and `selectedID == profile.id` passed for the synthetic fixture. One Edit AX press returned status 0, and the owned attached-sheet assertion passed. No further actions were performed; editor save/cancel was not exercised.

The owner compared all fourteen latest PNGs with the corresponding individually visually inspected `d8kcLS` images: 14/14 were byte-identical. The recorded bounded visual findings therefore apply to identical content; this is not a new individual visual inspection or additional physical interaction acceptance. The five prior roots (`qPvHTG`, `lqiiDh`, `SbQXgG`, `d8kcLS`, `CVRnjM`) and all earlier failure/locator-BLOCKED history remain preserved.

The bounded sixth sequence completed, not the full ba15 task. Scrolling, focus restoration, physical keyboard, VoiceOver, full-app commands/E2E, live behavior, editor save/cancel and Add/order persistence remain explicit gaps. No production regression was demonstrated or fixed; production files and ba14 remain untouched. Slot released, processes ended, no retries, commits, push or PR.

## Isolation review

- AppModel receives an explicit temporary ProfileLibrary, MemoryDefaults and `coreCLI: nil`; its default initializers are not used. Synthetic SOCKS5 fixtures use `example.invalid` without resolution or connections. Direct fixture insertion is setup, not UI creation proof.
- The copied production BimeronApp entry point is omitted. Its default AppModel, AppDelegate, menu bar and application commands do not run. The replacement host never searches for, closes or sends events to another application's windows. It closes only its own window and exits only its own process.
- The sandbox denies networking and all writes except the unique temporary root and `/dev/null`. It denies reads of the original user's Bimeron Application Support, Bimeron preference files and `.ssh`. HOME/TMPDIR redirection supplements explicit injection; it is not the isolation proof. Ordinary framework preference reads remain possible under the inherited allow-default policy.
- Filesystem preflight checks an allowed temporary write and a denied sibling write before opening a window. A preflight failure stops execution. If the deny check unexpectedly permits the sibling write, the runner reports failure and retains that path for owner inspection rather than deleting outside its root.
- No socket/network probe exists. The retained sandbox policy provides source evidence for network denial; runtime network enforcement is **not dynamically verified**. This intentionally differs from the shared harness's socket preflight.
- Add profile and its shortcuts are never invoked: AddProfileView appearance reads shared clipboard/SSH defaults. No clipboard, file panel, executable selection, export, quit action, profile deletion or user settings control is exercised. Native AX queries/actions are scoped to `getpid()`; no global input injection, activation of the user's app, permission request or accessibility-setting change occurs.

## Bounded evidence

One owned MainWindow checks empty temporary loading at EN/light 720 × 600 and sidebar routing through Settings/Log/About/Profiles. Twelve synthetic profiles with long EN/RU names provide overflow setup once. The same owned window captures the populated layout at 720 × 600, 855 × 628 and 1100 × 800, each in EN/RU and light/dark, by changing memory-backed language and hosting color scheme/appearance. No editor sheet is opened until these captures finish. This is a bounded layout capture sequence, not a repeated editor matrix or interaction suite.

After restoring minimum EN/light presentation, the driver retains an own-process AX tree and requires one AXButton matching the exact known composite row label. If uniquely available, AX selection must change selectedID and a single Edit action must present an owned sheet. Unsupported or ambiguous matches leave selection/Edit explicitly BLOCKED; no fallback or model assignment substitutes for interaction. Historical integrated audit evidence documents an opaque ProfilesView AX provider, but the fifth-run tree exposes row AXButtons with composed labels. Its executed blocker was the name-only locator mismatch; historical opacity must not be generalized to that run. The sixth run exercised the corrected composite-label locator and passed selection/Edit presentation as recorded above.

AX presses are native control-action evidence on synthetic data. Fixture insertion is source/model setup. PNG creation alone is not visual inspection. COMPLETE means only the supported bounded sequence finished; it does not turn BLOCKED or UNTESTED items into passes. Failures retain evidence and exit nonzero; the host has a 60-second self-watchdog.

Visual review covers all fourteen fourth-run captures and the third run's empty-state observation, within the stated sizes, languages and appearances; fifth- and sixth-run PNGs are byte-identical to the fourth-run images. Sixth-run native row selection and Edit-sheet presentation passed. Scrolling interaction, focus restoration, physical keyboard, VoiceOver, production application commands/full app E2E, real Core/live runtime, editor save/cancel and Add/order persistence remain untested. Completed coverage is limited to the explicitly recorded observations. No duplicate editor acceptance suite is added. Production MainWindow/ProfilesView, ba14 compact card and `focusEffectDisabled` remain unchanged. Every Git invocation in the runner uses `/Users/wrk/.local/bin/git`.
