# Minimum working macOS version — ba-23

## Purpose and ownership

Deliver an explicitly started, working macOS VPN for declared supported profiles,
then prove real operation and safe cleanup. This is a minimum working product
plan, not a minimum macOS OS-version decision or the full desktop parity backlog.
Desktop parity remains the broader goal.

Main coordinator: `b9e3eb8c-abd0-4eed-af22-a85d67ba4d12` (migrated from
`mcp:beafc30d-18e2-4108-a06d-f148d371a337`).
Active implementation owner **ba-22**:
`mcp:c181aa1b-d247-4cbd-bb9a-396c4435b9a5`, branch
`feat/ba22-bundled-core-control`, Apple base
`8a0c37ecd532c5d99c613387ca2713aa6eaaee71`.
That owner retains bundled Core, minimal first installation and actual GUI
Start/Stop. This document assigns no second writer, implementation or system work.
Future code needs a separate bounded assignment: LOW sole writer, MEDIUM review.
Planning uses Sol MEDIUM. Root main remains untouched; ready-source publication
and guarded merge belong to main.

## User decisions (2026-11-05)

- **D1 — First-release profile set: all access protocols.** Every protocol in
  `AccessProtocol` (SS, SSConf, SOCKS5, HTTP, MASQUE, VLESS, VMess, Trojan, Naive,
  Hysteria2, AnyTLS, SSH, TUIC), plus routing and GeoData, are in scope. Live M2
  evidence is feasible for SSConf, VLESS, possibly Hysteria2 (user's manual
  checks), and SSH (user-provided test server with root access and a key; address
  and credentials are kept outside this public repository). The remaining
  protocols receive exact-Core validation and synthetic coverage only. Release
  documentation must list the live-verified and not-live-verified protocols separately;
  advertising the latter is accepted residual risk, not a live pass.
- **D2 — Quit while connected: confirmation dialog.** Quit/Cmd+Q while connected
  offers "Disconnect and quit" and "Cancel". The app quits only after Stop and
  observed cleanup succeed; on Stop failure it stays open and shows the error.
  The existing disabled Settings toggle "Disconnect VPN and stop the core service
  on quit" becomes functional: when enabled, Quit disconnects without asking.
  "Quit and keep VPN" is not offered in the first slice.
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
  whichever was used. Neither is a shipping pin.
- **D4c — Approval:** the user alone approves Core pins and releases.

## Baseline and credited evidence

Apple baseline is `8a0c37e`; ba15–20 are merged. Ba21 at that revision accepts
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

Read-only source inspection at this baseline confirms the Connect action in
`Sources/BimeronApp/ProfilesView.swift` is disabled. The last reported root GUI
build was `73f6325`; it is not evidence of a current binary. Core latest known
remote revision is `6b0d97a` (coordinator report); local master is stale. No fetch
or remote verification was performed for this plan. Ba22 must establish the exact
compatible source/build rather than infer it from either reference.

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

### M1 — Bundled Core and explicit Start/Stop (ba22 owns implementation)

- Pin compatible exact Core source, build, version, architecture and provenance;
  validate CLI and guarded IPC capabilities. Package the verified payload in the
  app bundle. Missing/incompatible/tampered payloads must fail understandably.
- Complete protected first installation and launchd integration, explicit owner
  binding and permission checks. Reuse the
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

D1 declares all protocols in scope; D3 selects the GeoData source. Each
protocol is labeled live-verified or not-live-verified per D1.
Basic Start/Stop must not wait for every desktop feature; a profile must not be
advertised as supported until its required capabilities pass.

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

1. Let ba22 finish its owned slice and report exact source/artifact readiness.
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
