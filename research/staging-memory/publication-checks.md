# Bounded research publication checks

The publication scope is the isolated synthetic prototype and evidence only. Local issue and options remain in README; this PR is not production staging implementation or architecture approval.

Integrated upstream `859f15b33e915be75506faf6409488da2936dccb` into the existing research branch with a merge commit, preserving original commits `d86fe22` and `8e3968a`. No conflicts or implementation changes were needed. The diff against that base contains only this research directory. Shared CI and runner allowlists were not edited.

Parent review rechecked fixed roles, explicit mock trust classification, unchanged production boundaries and final T evidence attribution. Prior independent LOW reviews are retained in this directory; the residual-reporting P2 correction remains in the prototype. No substantial integration required a new implementation child.

Post-integration local checks passed:

- Swift compilation of prototype.swift and memory.swift with temporary binaries/module cache.
- Full standalone prototype assert suite, including multi-chunk writes, ownership, gate/quota rejection, cancellation, exclusive collision preservation, cleanup and mock evidence retention.
- Small memory semantics subprocess: all checks true. No full allocation benchmark repeated.
- Python AST parse and historical memory-results.json integrity: 15 recorded subprocess runs.
- Scoped Git whitespace check and diff scope review.

The research scripts are not invoked by the existing application CI workflow. Hosted CI status must be reported from the PR separately; no hosted pass is claimed here. Historical small-fixture RSS measurements do not validate final T peak or maximum allocations. Mock evidence is not authentication; ACL/metadata policy, fault injection, hostile same-UID concurrency, held-handle candidate return, protected intake and crash durability remain outside this prototype. No install, merge to main, release, live operation or keys are involved.
