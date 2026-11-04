# Preserve profile edits (workstream A)

Implement bounded line edits in ConfigDocument and protected Raw editing in EditorView.
Acceptance: byte-identical no-op for imported documents, including BOM, mixed LF/CRLF and EOF; decoded-value comparisons; untouched comments, unknown fields and quote spelling; reversible disabled ShadowTLS drafts; ambiguous content remains available in Raw and cannot be edited through forms.

Import remains an explicit transformation: retain existing absolute reference resolution against the original directory and AccessKey.File inlining. No source-directory storage or Core API expansion.

Implemented: source line endings/BOM retained, decoded no-op edits, reversible commented ShadowTLS drafts and protected Raw conversion. Removing an empty ShadowTLS block retains original comments and blank lines. Syntax errors are deferred from construction to validation so ProfileLibrary.load retains repairable profiles. Empty Profile Name is accepted as optional; required access fields still validate.

D's shared fixtures are integrated through PR #5, merged into main at d879fd6; the rebased A implementation commit is 693a87a. The adapter uses repository fixtures/acceptance by default, with no external fixture path required. There is no remaining fixture integration blocker.

Verification reported after integration:

- `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test`: 52 Swift Testing tests passed across the integrated suite, including B's tests; this is not an A-only count.
- `python3 fixtures/acceptance/check.py`: 26 scenarios and 29 files passed, including all negative checks.
- `sh scripts/build-app.sh`: release build passed.
- `test -x dist/Bimeron.app/Contents/MacOS/Bimeron` and `git diff --check`: passed.

Portable fixtures are intentionally incomplete profiles, so paired-byte tests use the actual restore/write/load path and verify ordinary update rejection leaves bytes intact. Complete synthetic profiles separately cover successful import/update and ShadowTLS save/reopen cycles. Detailed protocol/cipher compatibility remains Core's responsibility. Live editor, service/connectivity acceptance and remote CI results require separate evidence. See pr.md for behavior and verification limits.
