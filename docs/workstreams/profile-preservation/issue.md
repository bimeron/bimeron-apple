# Preserve profile edits (workstream A)

Implement bounded line edits in ConfigDocument and protected Raw editing in EditorView.
Acceptance: byte-identical no-op for imported documents, including BOM, mixed LF/CRLF and EOF; decoded-value comparisons; untouched comments, unknown fields and quote spelling; reversible disabled ShadowTLS drafts; ambiguous content remains available in Raw and cannot be edited through forms.

Import is an explicit transformation: retain existing absolute reference resolution against the original directory and AccessKey.File inlining. No source-directory storage or Core API expansion.

Verification: local preservation regressions, full Swift tests and release build. Live service acceptance and CI require separate evidence. A push and PR creation are explicitly authorized; merging is not. Publication remains deferred until D integration makes standalone tests and default CI ready.

Implemented locally: source line endings/BOM retained, decoded no-op edits, reversible commented ShadowTLS drafts and protected Raw conversion. Syntax errors are deferred from construction to validation so ProfileLibrary.load retains repairable profiles. Empty Profile Name is accepted as optional; required access fields still validate. New regressions exercise import transformation and subsequent byte-identical saves without changing import policy.

Detailed protocol/cipher compatibility remains Core's responsibility. Model checks reject known incompatible wrapper families and retain drafts on failure. See pr.md for local verification and outstanding live/CI evidence.


Integration dependency: D fixture commit f8988b7, contained in final D HEAD ce2654d8d5b94bded4db230d317df76e66998ca3, is not integrated into this branch or local main. The byte adapter requires integrated fixtures/acceptance or an explicit BIMERON_ACCEPTANCE_FIXTURE_ROOT pointing at D's fixture directory. Missing fixtures fail; external-path success is not default CI readiness. Integration and publication are coordinated separately; A has made no ancestry/workflow changes. Portable fixtures are intentionally incomplete profiles, so paired-byte tests use the actual restore/write/load path and verify ordinary update rejection leaves bytes intact; complete synthetic profiles separately cover successful import/update and ShadowTLS save/reopen cycles.
