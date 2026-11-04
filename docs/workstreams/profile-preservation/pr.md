# fix: preserve profile source during visual editing

Opening and saving a managed profile previously normalized line endings and removed its BOM; disabling ShadowTLS discarded its credentials. ConfigDocument now retains source line terminators and the document BOM, compares decoded values before replacing assignments, and edits only changed rule fields. New assignments use `Key = Value`; optional fields can be removed without materializing omitted defaults. Profile Name may be omitted, matching Core's optional-name semantics.

ShadowTLS uses an editor-owned commented draft without a new Core key. Disable/reopen/re-enable retains populated fields and original comments, omits empty disabled assignments, and removes an empty disabled block while retaining its original comments. Known incompatible protocol families block active saving without removing the draft. Core remains responsible for detailed transport/cipher compatibility.

Syntax checking now occurs at validation rather than construction so the library can load ambiguous documents for repair. EditorView opens unsupported or ambiguous documents in Raw and prevents conversion to forms until resolved. Duplicate active sections/keys, duplicate active/disabled ShadowTLS blocks, unknown ShadowTLS fields, unsupported quoted escapes, unsafe disabled boundaries and unsupported rule shapes are protected. Local validation still blocks invalid saves; original source remains intact.

## Import decision

Import remains an explicit transformation: inline AccessKey.File and resolve relative file references against the original directory. No source-directory storage or import behavior changes. Byte-identical no-op applies to the resulting imported document.

## Validation

- `BIMERON_ACCEPTANCE_FIXTURE_ROOT=/Users/wrk/.t3/worktrees/bimeron-macos/test-acceptance-scenarios-fixtures/fixtures/acceptance swift test`: 38 tests passed, including 13 preservation regressions and one parameterized adapter covering all eight stable A IDs.
- An explicitly nonexistent fixture root fails with a diagnostic naming D and the required environment override; no fixture coverage is silently skipped.
- `swift build -c release`: passed.
- `git diff --check`: passed.
- Tests cover byte equality (BOM, LF/CRLF, mixed endings, EOF), decoded no-op, comments/unknown content, disabled draft persistence through ProfileLibrary, ambiguity loading, omitted defaults, optional clearing, rule edits/toggles/reordering/insertion/deletion and explicit import transformation followed by no-op save.

## Limits

No live editor interaction, Core CLI/service integration, connectivity acceptance or CI run was performed. Detailed ShadowTLS compatibility belongs to Core validation; the existing basic-check warning remains. Unsupported encodings stay in Raw rather than receiving guessed form values. This draft describes workstream A only; CLI/daemon integration and acceptance evidence belong to the other workstreams. Push and PR creation are authorized, but publication remains blocked on the fixture integration described below. Merge is not authorized. No remote writes, account changes or commits are included in this local change.

## Integration dependency (blocking standalone PR/CI readiness)

D's fixture commit `f8988b7` is contained in D's final local HEAD `ce2654d8d5b94bded4db230d317df76e66998ca3` on `test/acceptance-scenarios-fixtures`. It is not in this branch or local main (`9ef95ae`). D issue #3 tracks that workstream. A has made no ancestry or workflow changes. D must be integrated before a standalone A PR can claim default CI coverage. No fixtures are duplicated here.

The adapter defaults to `<repository>/fixtures/acceptance`; an explicit `BIMERON_ACCEPTANCE_FIXTURE_ROOT` points directly at D's `fixtures/acceptance` directory for independent local verification. Missing fixtures fail clearly. The eight scenario IDs are preserved as parameter values in test output. Exact Data input/expected pairs exercise ConfigDocument and the library's atomic restore/write/load path. D's portable fixtures omit Profile.Version and sometimes required access fields, so ordinary update correctly fails validation and retains original bytes; these fixtures do not establish successful validated import/editor-save acceptance. Separate complete-profile tests cover actual import, update, disabled save/reopen/re-enable/update, byte preservation and secret/comment restoration. No live UI acceptance is claimed.
