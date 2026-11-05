# Core-to-GUI production Connect boundary

Status: ba-21 policy accepted, 2026-11-05. The user explicitly accepted V86 option 3 (explicit user acceptance) after the manual-recovery recommendation. Apple baseline: `73f6325be47ee3828237788355b587c4673d7ad6`. This document changes no runtime behavior. Shipping remains **false / no-key**.

## Accepted decision

Accepted V86 option 3: explicit root resume for an interrupted committed servicing operation that needs current-producer reconciliation. Acceptance covers the policy below, without approving its production mechanism. This resolves the committed-operation/new-producer availability choice rather than deferring it to another design deliverable.

## Evidence and current boundaries

- `AppleCoreStaging.swift` and its synthetic staging tests implement disposable, unprivileged candidates with held handles and verifier-owned evidence. As [authenticated-staging.md](../core-delivery/authenticated-staging.md) specifies, a protected consumer must copy and revalidate actual protected bytes and original evidence under independently configured trust policy. Candidate publication is neither protected Prepared state nor installation/readiness approval.
- `Sources/BimeronDaemon/{DaemonClient,DaemonLifecycle,DaemonProtocol,DaemonSocketTransport}.swift` and their tests provide generation invalidation, guarded session control and root-peer checks. The transport permits hello/status/stats_snapshot/start/stop; ordinary hello establishes neither installed artifact identity nor maintenance release. `cleanupConfirmed` accepts disconnected with no active session, including absent Session: useful for the existing lifecycle contract, insufficient for resource cleanup proof.
- Core master evidence is pinned to merged Core94 `9808682119424ec5e7546d0d99e38e4776c55c69`, not inferred from a branch name. ADR0034 was also inspected on local `origin/feat/internal-maintenance-coordinator` at `4581fba252dcb56f8dee94c6d25d5d20bc3c10af`, and ADR0034 plus `core/maintenance.go` were rechecked at later Core93 `6b0d97a4ac96a903153a57d544751401b98d6909`. The merged internal slice is not an unmerged proposal. The separate `docs/workstreams/core-maintenance-contract/contract.md` remains a production contract **proposal**.
- ADR0034 attaches a package-private coordinator that starts sealed, has **no OPEN/RELEASE**, and uses a fake-store boundary. Successful Stop produces `recovery_required`, never verified cleanup success. Unattached Engines retain their behavior. Public v1 failed shutdown remains usable, without a protocol version change; its failure must not acquire the internal maintenance seal by implication.
- [Servicing model results](../daemon-servicing-recovery/model-results.md) report 27 synthetic model tests. They do not prove filesystem durability, executable/process association, launchd exclusion, or DNS/routes/utun recovery. ADR0034's recorded local toolchain failure is not a passing test result; hosted CI evidence must be reported separately.

## Options and decision

1. **Reuse cached release/readiness.** Lowest downtime, but old boot/instance evidence cannot authorize a current producer or prove recovery. Reject.
2. **Automatically release a fresh instance after new checks.** Better unattended availability, but expands post-crash authorization and risks accepting incomplete current-producer/resource proof. Defer; it is outside the accepted manual-recovery scope.
3. **Explicit root resume with current recovery/readiness — accepted (V86 option 3).** Retain committed artifacts and authorization identity; reconcile before release. Material drawback: interrupted servicing can require administrator action and reboot, extending downtime even when committed bytes are intact.

Preserve four boundaries: approved trusted input; verified protected installation; current daemon readiness while admission is closed; release permitting a new explicit Connect. None implies the next. Ordinary hello, root-peer identity and disconnected status cannot substitute for this production contract or open ADR0034.

## Accepted policy

For a committed operation interrupted before release completion, or with an unresolved release outcome requiring a new producer:

1. Keep admission closed and retain the immutable committed artifact set, original operation and generation. Do not republish artifacts or replace the backup solely to refresh runtime identity.
2. Require explicit root resume scoped to that committed operation, generation, artifact identity and expected current producer. GUI reopen, ordinary hello and a lost reply confer no new servicing authority; query/reconcile the existing outcome rather than replay a mutation.
3. Require Core-owned recovery using retained evidence, followed by fresh readiness bound to the current producer, installed bytes/build and compatible contract. Missing evidence, conflicting resource state or failed recovery remains blocked. A fresh empty Engine, successful Stop or new boot alone cannot prove cleanup.
4. Reject same-boot adoption after loss of the exact observer/process association; require the accepted reboot/manual-recovery route. Reboot proves prior-boot processes cannot still execute, then recovery must separately establish cleanup. A retained exact current-process association may support fresh reconciliation; PID absence is insufficient.
5. Permit release only after the owner/Core contract verifies the current recovery/readiness outcome and committed identity. Cached readiness never authorizes a different producer. Release performs no VPN start; Connect requires new explicit user intent.

This interrupted-operation rule does **not** require root resume on every ordinary clean reboot after an already completed release. Normal startup still needs fresh validation of installation, terminal gate and clean recovery evidence; previous readiness is never a startup credential. Dirty or ambiguous state stays blocked under the recovery policy. Neither path automatically restores VPN.

## Approval and staged boundary

Acceptance selects **policy only**; production privileged actions remain **UNAPPROVED**. Namespace, persistence format/durability, wire protocol, cleanup ledger/postconditions and release handshake remain **UNAPPROVED**. Candidate/version selection, public pin and trust/release roles also remain **UNAPPROVED**. ADR0034 remains sealed with no opening transition. Production Connect stays blocked until a separately approved owner/Core readiness-and-release contract is implemented and proven.

Subsequent mechanism review must show interrupted commit/release, reply loss, changed producer and ordinary clean reboot separately. Implementation approval, contract/fault tests, platform adapters and separately authorized native-Mac/live acceptance are later gates. Replacement still requires scoped successful cleanup **and** exact exit with restart exclusion; readiness replaces neither. No implementation, new maintenance fake API, installation, keys or execution is authorized here.

Reuse the accepted [hosting constraints](../daemon-servicing-recovery/hosting-proposal.md): separate root demand/boot owner with explicit root CLI; Core directly under launchd; future fresh-capable installations only; fail-closed manual recovery/reboot, no same-boot adoption; one backup; no owner self-update; two-stage uninstall; no automatic VPN. Do not reopen them through the release design.

ba-18 may cover only existing client contracts: unknown after IPC loss with explicit hello reconciliation; stale success/error cannot mutate a newer generation or clear its pending operation; repeated commands are suppressed while pending. Those fake cases grant no installation/release readiness. Preserve ba-14 card/focus behavior. Issue #13 remains open and Core #79's native-VM hold remains in force (owner-reported status, not independently refreshed here).

## Exact accepted decision

> Accepted on 2026-11-05 (explicit user acceptance): V86 option 3 as policy only: explicit root resume for interrupted committed-operation reconciliation, preserving committed artifacts and original operation/generation, requiring recovery plus fresh current-producer readiness, with no cached readiness, identity-only republishing, same-boot adoption after observer loss or automatic VPN; ordinary clean already-released reboot does not itself require root resume, and detailed namespace/wire/persistence/ledger/handshake/trust/candidate/version/pin/roles, mechanism/implementation and production privileged actions remain UNAPPROVED.

Inspection here was read-only source/document/test review; no tests, builds, GUI, native or live acceptance ran. Existing synthetic results are historical evidence, not new validation or release acceptance.
