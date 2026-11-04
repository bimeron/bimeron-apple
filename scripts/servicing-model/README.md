# Offline servicing protocol model

This Python standard-library prototype models the accepted design in
[the hosting proposal](../../docs/workstreams/daemon-servicing-recovery/hosting-proposal.md).
It does not implement a service, installer, socket, filesystem adapter or Core API.
`maintenance_status`, `maintenance_shutdown`, durable cleanup results,
`maintenance_recover` and `maintenance_release` are proposed APIs absent from the
inspected Core. No production acceptance or release trust follows from these tests.

Run only the offline tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/servicing-model -v
```

`Model.disk` is a deep-copyable in-memory durable snapshot; owner lock possession,
exit observer, observed exit and readiness are volatile. The Core seal is separate
from owner lifetime and is lost on reboot. `write` publishes a whole snapshot;
`fault='before'` / `'after'`, or `model.fault=(label, boundary)`, crashes the owner
immediately before or after that publication. This is an atomic-record abstraction,
not an fsync, rename, directory durability or power-loss implementation. Partial
artifact publication is modeled independently from record atomicity.

All identities, principals, account mappings, trust/protection flags, cleanup
receipts, restart exclusion, service absence, process exit and readiness are
**synthetic injected evidence**, not observed live facts. Root CLI and single-UID
checks are symbolic policy boundaries, not peer authentication. The fixed lock
identity models a protected persistent inode; no lock file is opened or replaced.
The observer stands for exact boot/process-instance observation, not a PID lookup.
A receipt alone, an exit event alone, or a new boot alone cannot authorize replacement.

Tests cover the durable gate before shutdown, legacy and guarded start denial,
seal before failed cleanup, dirty resource evidence before start, exact scoped
identities, independent cleanup and exit evidence, owner contention/account reuse,
manual recovery after owner death, no same-boot adoption, complete artifact sets,
fresh readiness and commit before release, scoped duplicate operations, candidate
cleanup before rollback, trust/downgrade revalidation, one backup, explicit
untrusted DEV classification, fresh-only installs and two-stage removal retaining
profiles. Regression traces cover launch-intent and candidate-run crashes on both
sides for fresh installs and updates, continuing through explicit recovery to a
released endpoint. They also cover repeated publication and interrupted rollback
selection without losing the original backup, historical operation-ID reuse, and
stale recovery producers after another reboot. Every modeled durable write label
has before/after crash coverage; older boundary tests primarily check immediate
fencing, rather than exhaustive continuation of every possible trace.
Assertions exercise allowed/blocked operations and artifact outcomes.

The model deliberately has no automatic retry, VPN restoration, owner self-update,
legacy-install migration, same-boot process adoption, profile deletion or network
recovery algorithm. The `legacy` start argument identifies the caller path; both
paths deliberately use the same gate. Session identity uses explicit `idle` rather
than missing evidence. Launch intent durably marks a candidate as possibly running
and invalidates prior cleanup/restart exclusion before any symbolic enable/start. Even a crash just after
intent requires reboot, current Core recovery and newly injected restart exclusion.
The transaction retains its immutable prior artifact and selected candidate/rollback
set through repeated publication. Recovery receipts bind the target operation's
boot/instance/session as well as the current recovery producer boot/instance;
reboot invalidates the latter. These fields remain synthetic evidence.

Duplicate admission compares the complete original request against durable retained
history and returns the original operation identity; `outcome` queries its latest
phase without mutation. Conflicting reuse rejects even with current generations.
History is unbounded in this small model; retention/compaction is unspecified.
This is separate from readiness request IDs, which are one-use within the model
lifetime. Terminal committed same-boot recovery requires a fresh handshake before release; changed boot/instance
cannot reuse it and remains blocked pending a separately designed reconciliation.
Finalization represents a separate external root action after owner exit, never
self-deletion. Trust, compatibility and downgrade flags stand for independent
policy decisions; DEV never changes an artifact's trust flag.

Limitations: no wire/schema parser, token expiration, real durable storage, kernel
identity association, launchd behavior, filesystem attack resistance, signing,
provenance, or DNS/routes/utun verification. Receipt persistence is represented by
the snapshot for convenience; a real Core must own and authenticate its separate
result store. Current account identity is supplied at each symbolic acquisition;
there is no account-directory integration. Snapshot inspection and direct mutation
are test fixtures, not supported privileged input channels. macOS safety requires
separate Core contracts, adapter fault tests and explicitly authorized disposable
machine acceptance. These tests do not replace those gates or CI.
