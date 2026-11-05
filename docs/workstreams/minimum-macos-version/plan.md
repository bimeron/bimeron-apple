# Minimum working macOS version — ba-23

## Purpose and ownership

Deliver an explicitly started, working macOS VPN for declared supported profiles,
then prove real operation and safe cleanup. This is a minimum working product
plan, not a minimum macOS OS-version decision or the full desktop parity backlog.
Desktop parity remains the broader goal.

Main coordinator: `e2dd3cf1-d30e-47aa-a0b3-3d32fc658e6d`.
Ba-22 (bundled Core and GUI Start/Stop) is merged as PR #78 (`850bdef`).
Active implementation owner **ba-24** handles the development Core launch (D5,
issue #79). This document assigns no second writer, implementation or system work.
Future code needs a separate bounded assignment: LOW sole writer, MEDIUM review.
Planning uses Sol MEDIUM. Root main remains untouched; ready-source publication
and guarded merge belong to main.

## User decisions (2026-11-05)

- **D1 — First-release profile set: all access protocols.** Every protocol in
  `AccessProtocol` (SS, SSConf, SOCKS5, HTTP, MASQUE, VLESS, VMess, Trojan, Naive,
  Hysteria2, AnyTLS, SSH, TUIC), plus routing and GeoData, are in scope. The user
  runs manual live checks and reports protocol failures; SSH uses a user-provided
  test server whose address and credentials stay outside this public repository.
  Reported failures are fixed as actual findings.
- **D2 — Quit while connected: three-choice dialog.** Quit/Cmd+Q while connected
  offers:
  - "Disconnect and quit": the app quits only after Stop and observed cleanup
    succeed; on Stop failure it stays open and shows the error.
  - "Quit and keep VPN": the GUI process terminates (not hides) while the Core
    session keeps running; the next launch adopts its authoritative state (M1
    reopen reconciliation) without restarting or changing the session.
  - "Cancel": nothing changes.
  The dialog is always shown on Quit while connected; there is no setting to skip
  it. The existing disabled Settings toggle "Disconnect VPN and stop the core
  service on quit" is removed rather than made functional.
- **D3 — GeoData: follow the Windows Desktop scenario.** Reuse the
  `bimeron-desktop` behavior (`docs/geodata-routing.md`, `src/GeoDataDownload.cpp`
  at `296130e`): explicit user-initiated download of the latest Loyalsoldier
  `v2ray-rules-dat` release, pinning that release's exact `.dat` and
  `.dat.sha256sum` assets; no download on launch, Save or Start; one shared choice
  per kind; offline Choose file for local files; immutable content-addressed
  cache. SHA-256 checks release consistency, not publisher authenticity. Files
  are fetched by the user, not bundled; upstream license terms are recorded before
  release.
- **D4a — App signing: unsigned first, Developer ID later.** Internal builds are
  unsigned until Apple Developer Program approval; then Developer ID signing and
  notarization are added before public distribution. Clean-Mac acceptance of
  unsigned builds documents the manual Gatekeeper step.
- **D4b — Core source: user-specified.** The user will name the shipping Core
  source. For testing, on the user's command, the app is built either with Core
  from a specified commit or with a user-specified Core file; the manifest records
  whichever was used. Neither is a shipping pin. A planned in-app developer mode
  will also let the user select a Core manually; it must be clearly marked as
  non-shipping and must not bypass payload validation or the guarded launch path.
- **D4c — Approval:** the user alone approves Core pins and releases.
- **D5 — Development Core launch without an installer.** The Install Core.pkg /
  launchd installer is dropped for now. Until Apple Developer signing exists,
  the app launches its bundled Core as root through an `osascript` administrator
  prompt on the first Start. Accepted drawbacks: a password prompt whenever Core
  is not running, no autostart, development-only use. A launchd/SMAppService
  service returns after signing. Implementation: issue #79 (ba-24, separate
  owner).

## Baseline and credited evidence

Apple baseline is `850bdef`; ba15–20 and ba22 (#78) are merged. Ba21 at that revision accepts
**policy only**: explicit manual root resume for an interrupted committed
installation. A clean, already released installation's reboot behavior is a
separate case. Neither policy grants mechanism, trust or system authority, and
neither permits automatic VPN restoration. See the
[accepted policy](../core-gui-contract/decision-proposal.md) and
[servicing proposal](../daemon-servicing-recovery/hosting-proposal.md).

- **ba15:** [bounded native synthetic MainWindow evidence](../ba15-ui-acceptance/README.md)
  includes 14 captures and AX sidebar/profile selection/Edit presentation. It
  proves neither production app E2E nor keyboard, scroll or VoiceOver acceptance;
  issue #75 remains open.
- **ba16:** [forms audit and targeted synthetic regressions](../profile-forms-parity/ba16-audit.md)
  credit draft preservation and Raw authority; complete Core option compatibility
  and runtime behavior remain unproven.
- **ba17:** file URL identity and encoded import-selection regressions are merged
  (#74/#67). Actual native import/export panels and cancellation remain pending.
- **ba18:** daemon client interleaving coverage is merged (#71), supplementing the
  [guarded lifecycle contract](../daemon-lifecycle/README.md). Synthetic exchanges
  do not prove privileged IPC, networking or cleanup.
- **ba19:** untouched disabled routing source preservation is merged (#72).
  Editor preservation does not prove actual Core route application.
- **ba20:** assembled development bundle validation is merged (#70). Bundle
  structure checks do not prove installation, trusted delivery or distribution.
- Statistics model, presentation and session-bound adapter already exist; see
  [model contract](../connection-statistics/README.md),
  [presentation](../statistics-presentation/README.md) and
  `Sources/BimeronStatistics/DaemonStatisticsAdapter.swift`. Older documents
  describing no adapter are historical; its presence is not live GUI acceptance.
  Diagnostics, SSH file preflight, local GeoData and window lifecycle foundations
  are likewise credited below, not restarted.

Ba22 wired the GUI Start/Stop to a pinned bundled development Core; the exact
pin is recorded in its [workstream notes](../bundled-core-control/README.md).
That pin is not a shipping pin (D4b).

Shipping remains false/no-key. There is no release candidate, public trust pin or
`apple_reviewed` approval. Historical document claims retain their original scope
and revision; they are not new passes at this baseline.

## Acceptance tracking

All remaining gates below are **pending**, with no invented dates. Record each
future result with gate ID, exact app/Core source and artifact hashes, macOS and
architecture, profile/config identity with secrets omitted, command or user action,
expected/observed result, retained evidence, reviewer and unresolved findings.
Use PASS, FAIL or BLOCKED only for the named scenario; synthetic and live results
must remain separate. Main assigns owners beyond ba22 before execution.

### M1 — Bundled Core and explicit Start/Stop (ba22 merged; D5 launch in ba-24)

- Pin compatible exact Core source, build, version, architecture and provenance;
  validate CLI and guarded IPC capabilities. Package the verified payload in the
  app bundle. Missing/incompatible/tampered payloads must fail understandably.
- Per D5, launch the bundled Core as root via an administrator prompt on Start
  when Core is not running, with explicit owner binding and permission checks
  (issue #79, ba-24). Protected installation with launchd/SMAppService is
  deferred until signing exists. Reuse the
  [delivery boundaries](../core-delivery/README.md); older release references are
  not a compatible shipping pin. Installation approval does not authorize running
  privileged or live acceptance here.
- Make readiness, service status, connection state, uncertainty and actionable
  errors reflect actual observations. Installation or start acknowledgement alone
  must not display a connected VPN.
- Start the selected validated profile and stop the observed guarded session;
  reconcile on app reopen without duplicate start or automatic VPN connection.
  Unknown IPC/session state must not authorize an unsafe replacement.

Acceptance: reviewed ba22 code and ordinary CI evidence first; later, separately
authorized installation/readiness and actual selected-profile GUI Start/Stop.
App reopen adopts authoritative state without changing the session. M1 does not
alone prove traffic or cleanup. No auto-connect in this first slice.

Evidence so far: ba22 merged as PR #78 (`850bdefb`). A user-run live test
(reported by main, 2026-11-05) started and stopped a real SSConf tunnel from the
GUI, and routes/DNS were restored. Exact app/Core hashes for that run are not
recorded here yet. It is the first M2 data point, not full M2 acceptance.

### M2 — Real VPN and cleanup (after M1 code readiness and separate authorization)

Core owns utun, DNS, routes and cleanup; there is no new Network Extension fallback.
Use an explicitly authorized test Mac, provisioned endpoint and recovery plan.
Record baseline, connected and post-stop network observations for:

- Actual traffic through the selected VPN, DNS behavior and applied routes.
- Repeated explicit Start/Stop; Stop restores DNS/routes and leaves no residual
  network state. An IPC disconnect or stop acknowledgement is not cleanup proof.
- Reconnect and profile switch, with authoritative old-session cleanup before a
  replacement starts; failed cleanup blocks replacement.
- IPC loss and restoration, Core crash and reboot: truthful unknown/error state,
  explicit reconciliation/recovery, no automatic VPN restoration and no residual
  network state after verified recovery. Distinguish interrupted installation
  resume from reboot of a clean released installation.

Acceptance: retained real observations for each scenario and resolved failures.
Synthetic tests are regression evidence, never live VPN proof. Fix actual findings
before adding preparatory infrastructure or expanding the release profile set.

### M3 — Usable first-release flows (depends on M1; live cases also on M2 authority)

- Wire and accept real-session statistics/diagnostics: correct instance/session,
  stale/unavailable/reset behavior, bounded redacted errors and exports. Reuse
  existing foundations and [diagnostics policy](../../diagnostics.md).
- Exercise supported forms with the exact selected Core, invalid/incompatible
  options, validation failures and preserved drafts; do not turn the form matrix
  into an unsupported protocol claim.
- Exercise actual import/export panels, chosen-file identity and cancellation,
  with unchanged profiles/files on cancel or failure.
- Close issue #75 gaps with production-flow keyboard, focus restoration, scrolling
  and VoiceOver evidence. Reuse bounded ba15/editor evidence without claiming it
  covers these gaps. See [editor evidence](../editor-interactions/README.md).
- Implement and accept Quit/Cmd+Q while connected per D2: user-visible outcome,
  session ownership and cleanup must be clear. Verify close/reopen separately;
  existing [window lifecycle work](../window-lifecycle/README.md) is not connected
  Quit proof. Do not silently infer that app termination stops Core.

Acceptance: retained actual user-flow results, including cancellation/error paths,
and no unresolved blocking usability or safety findings for declared profiles.

### M4 — Routing, GeoData and SSH: conditional release coverage

D1 declares all protocols in scope; D3 selects the GeoData source.
Basic Start/Stop must not wait for every desktop feature.

- **Routing:** source-safe editing is completed groundwork. Actual Core application
  of configured proxy/direct/block rules and associated traffic behavior is
  required for profiles claiming those rules. Broader editor parity can follow.
- **GeoData:** [local file/cache groundwork](../../GEODATA.md) exists. Profiles
  using GeoIP/GeoSite require real Core validation, configuration linkage, daemon
  file readability and applied group/rule evidence. Exercise missing, malformed,
  inaccessible and replaced files without corrupting the previous selection.
  External download follows D3 (Loyalsoldier releases, explicit download,
  release checksum); that is consistency checking, not publisher authentication.
- **SSH:** [file preflight/auth preparation](../../SSH_AUTH.md) exists but is not
  remote host verification or real authentication. SSH profiles require real
  authentication, host verification, connect, cancellation and Stop evidence,
  daemon file access, and reviewed compatible guarded auth IPC where interactive
  challenges are needed. Existing runtime auth gate must not be bypassed.
  SSH is in the first declared set (D1), with live evidence against the
  user-provided test server. It is still not a prerequisite to basic non-SSH
  Start/Stop.

Acceptance: explicit supported/deferred capability list plus passing evidence for
every capability required by each supported profile. Exclusions stay visible.

### M5 — Distribution and issue #13 actual acceptance

Before public distribution, record the exact Core compatibility/provenance chain
(D4b), user approval (D4c), Developer ID signing/notarization once available
(D4a), and clean Mac installation evidence. Development hashes/unsigned local bundles are
not authenticated public delivery. No key use or signing is authorized here.

Provide understandable manual recovery and uninstall instructions and accept them
on the authorized test Mac: stop/cleanup, known installed files and registration,
retained user data and truthful partial-removal reporting. Advanced servicing is
not required to invent an automatic recovery path for this first slice.
Complete [issue #13 actual acceptance](../../acceptance/README.md) against the
declared release set, preserving fixture/live evidence distinctions. Do not close
it on fixture integrity, bundle checks or synthetic tests alone.

## Sequence and boundaries

1. Done: ba22 merged (#78); a first live SSConf Start/Stop passed. Next: ba-24
   (issue #79) development Core launch per D5.
2. Main arranges review/self-hosted CI and requests separately scoped
   system/live authority only when code is ready; then accept real Start/Stop and
   cleanup. No heavy slot is reserved or used by this plan.
3. Fix actual findings, finish M3 and release-required M4 cases, then M5/issue #13.
   Record blockers and decisions here without launching competing implementation.

Deferred from minimal first implementation: automatic update/rollback, advanced
servicing and automatic VPN recovery. These remain broader desktop parity goals;
NE/iOS is a separate stream. Core79/Windows18 native VM cases remain a separate
hold, not a macOS prerequisite. Per user policy, all CI for this
workstream uses self-hosted runners until further explicit instruction.

This documentation-only consolidation performs no builds, tests, GUI, root,
network/VPN, launchctl, key/signing or system operations; it cancels no processes
or CI, creates no sibling tasks, and supplies no new architecture or authority.
