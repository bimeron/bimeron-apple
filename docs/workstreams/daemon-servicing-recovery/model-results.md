# Offline servicing model: results and review

2026-11-04. Completed authorized local model/protocol prototype, not a privileged service implementation. The three hosting/recovery/scope constraints in [the hosting proposal](hosting-proposal.md) are approved for this stage. No further architecture approval is inferred.

## Delivered and reproduced

[Model and runnable instructions](../../../scripts/servicing-model/README.md), using Python standard library only. `model.py` separates in-memory durable snapshots from volatile owner/observer/readiness evidence. `test_model.py` supplies deterministic synthetic failures; no service, root path, socket, Core daemon or network is accessed.

Parent reproduced:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/servicing-model -v
```

Result: **27 tests passed**. The suite includes before/after crashes at all 15 modeled durable write labels, plus continued recovery traces for the reviewed launch/publication/rollback failures. This is not exhaustive state-space exploration. Staged `git diff --check` also passed. Production Sources, Package.swift and existing app test targets are unchanged. No CI was run under the pause.

The tests establish behavior of the model under its assumptions:

- The durable maintenance gate precedes shutdown; guarded and legacy starts share boot/start admission rules. Dirty-resource intent precedes symbolic VPN start.
- Symbolic root CLI/single-UID/account binding and persistent lock identity reject unauthorized principals, changed accounts and concurrent owners. These are policy inputs, not actual peer authentication.
- Installation/operation/generation/boot/instance/session mismatch rejects mutation and cleanup proof. Exact historical operations can query retained outcomes; conflicting operation-ID reuse rejects.
- Maintenance seals admission before Stop, including failed cleanup. Replacement requires both a scoped successful durable cleanup result and independent full-exit observation, with restart exclusion. None alone suffices.
- Durable launch intent precedes possible candidate execution, invalidates earlier cleanup/restart exclusion, and forces conservative recovery after ambiguous launch. Recovery receipts also bind the current producer boot/instance.
- Complete artifact publication and fresh injected readiness precede durable commit and identity-bound release. Mixed sets, stale readiness, unsupported compatibility and untrusted release artifacts reject. Explicit DEV does not promote trust.
- Owner crash loses volatile exit observation. Manual approval is required, and uncertain prior execution cannot be adopted in the same boot. Reboot still requires Core recovery, not merely a new disconnected engine.
- Rollback requires candidate cleanup/exit and trust/downgrade revalidation; repeated publication preserves the immutable previous successful artifact set and selected rollback action. Only one backup generation is retained.
- Two-stage uninstall retains profiles and servicing tool after Core removal; finalization needs a separate symbolic root action, owner exit and service absence. No automatic VPN restoration or owner self-update exists.

## Review findings and disposition

Implementation and both independent reviews used explicitly selected GPT-6.1-Sol LOW children; parent planning/integration remained MEDIUM. First implementation had 23 passing tests. Parent adversarial inspection and independent review found four gaps despite that result:

1. Candidate runtime identity changed before durable run evidence, allowing a fresh-install recovery path to republish without cleanup/exit. Fixed with durable launch intent before any possible execution and conservative may-run state. New before/after intent/run continuations cover both fresh install and update.
2. Recovery could overwrite the sole successful backup with the candidate, including after interrupted rollback selection. Fixed with immutable transaction-bound prior artifacts and durable selection preserved through repeated publication/reboot.
3. Restart-exclusion evidence could survive candidate enable/start. Fixed by invalidation in launch intent; new recovery requires renewed synthetic exclusion evidence.
4. Only the latest operation identity was retained. Fixed with durable request/outcome history; exact historical queries do not mutate state and conflicting reuse rejects.

Parent also requested current recovery-producer binding; tests now reject receipts from an earlier boot/instance even when the original target identity matches. All five changes were exercised in the 27-test suite.

Independent review round 2 reported **no remaining findings within the authorized offline model scope**, reran all 27 tests, and reported 18 additional in-memory before/after crash continuations across gate, cleanup success/failure, publication, rollback selection/publication, resume and removal, checking backup/profile retention through allowed endpoints. Those inline review traces are supplemental review evidence, not additional checked-in regression tests or platform acceptance.

T3 delegated task identifiers for audit:

- Implementation: `node:delegated-task:command%3Amcp%3A831b8db2-8a03-4288-a590-a04d78b0f4a2%3Adelegate-task%3As-model-implementation-1`
- Review 1: `node:delegated-task:command%3Amcp%3A831b8db2-8a03-4288-a590-a04d78b0f4a2%3Adelegate-task%3As-model-review-1`
- Fixes: `node:delegated-task:command%3Amcp%3A831b8db2-8a03-4288-a590-a04d78b0f4a2%3Adelegate-task%3As-model-fixes-1`
- Review 2: `node:delegated-task:command%3Amcp%3A831b8db2-8a03-4288-a590-a04d78b0f4a2%3Adelegate-task%3As-model-review-2`

## Remaining gaps before a production proposal

The model assumes atomic durable snapshots. It does not implement record parsing, token lifetime, bounded history/compaction, secure file descriptors/ACL/TOCTOU defenses, flush ordering or real power-loss recovery. History is intentionally unbounded in this small prototype. It supplies no executable authentication, kernel peer/process association, launchd restart/disable semantics, exit observation, signing, provenance or actual DNS/routes/utun cleanup proof. Evidence objects are trusted synthetic fixtures, not cryptographic attestations.

Committed recovery with a changed boot/instance remains explicitly fail-closed; a current matching instance can reconcile using fresh readiness before release. This availability gap needs a concrete reconciliation contract before production. Same-boot process adoption remains excluded by the approved constraint. No legacy installation migration, owner self-update or destructive user-data migration is included.

Proposed maintenance_status/shutdown/recover/release and durable cleanup result APIs are **unavailable in inspected Core**. Core owners must first review the admission/startup gate, dirty-resource evidence, cleanup invariant, recovery ownership and separate durable result contract. A real implementation must also reconcile publication/launch intent with the actual process identity rather than preselected symbolic instance names.

Recommended next proposal, requiring separate approval: implement and review Core-side contracts first, with pure contract/fault tests and a specified committed-reboot reconciliation path, before any macOS privileged owner or installer adapter. Then review actual authorization/filesystem/service adapters and obtain separately authorized disposable-Mac acceptance. This report authorizes none of those steps. Delivery trust remains blocked pending the independent provenance/pin/candidate work; no weaker policy is substituted.

No remote writes, push, issue/PR, CI, merge, release, installation, launchctl, real daemon startup, network, keys or system settings/service changes were performed. Paused owners were not contacted. No UI observations were collected; no product defect or live acceptance is claimed from the model findings.

## Publication readiness

The user subsequently authorized publication of completed bounded work. Integrated
`origin/main` at `859f15b33e915be75506faf6409488da2936dccb` with a normal merge,
preserving the original three S commits. Integration had no conflicts; the net
PR diff contains only the three design/report documents and three offline model
files. The 27 model tests and diff whitespace check passed again after integration.
The prior independent review remains applicable because model code is unchanged.
No production implementation or architecture expansion is included.

Existing CI and runner allowlists are unchanged. The inherited workflow does not
run the Python model suite; its local result above is separate from hosted CI.
Hosted status must be reported from the PR, not inferred from these local checks.
Publication authorization does not authorize merge, install, release or live tests.
