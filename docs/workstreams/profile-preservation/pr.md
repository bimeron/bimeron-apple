# fix: preserve profile source during visual editing

Opening and saving a managed profile previously normalized line endings and removed its BOM; disabling ShadowTLS discarded its credentials. ConfigDocument now retains source line terminators and the document BOM, compares decoded values before replacing assignments, and edits only changed rule fields. New assignments use `Key = Value`; optional fields can be removed without materializing omitted defaults. Profile Name may be omitted, matching Core's optional-name semantics.

ShadowTLS uses an editor-owned commented draft without a new Core key. Disable/reopen/re-enable retains populated fields and original comments, omits empty disabled assignments, and removes an empty disabled block while retaining its original comments and blank lines. Known incompatible protocol families block active saving without removing the draft. Core remains responsible for detailed transport/cipher compatibility.

Syntax checking now occurs at validation rather than construction so the library can load ambiguous documents for repair. EditorView opens unsupported or ambiguous documents in Raw and prevents conversion to forms until resolved. Duplicate active sections/keys, duplicate active/disabled ShadowTLS blocks, unknown ShadowTLS fields, unsupported quoted escapes, unsafe disabled boundaries and unsupported rule shapes are protected. Local validation still blocks invalid saves; original source remains intact.

Import remains an explicit transformation: inline AccessKey.File and resolve relative file references against the original directory. Byte-identical no-op applies to the resulting imported document; import behavior and source-directory storage are unchanged.

## Validation

Shared acceptance fixtures are integrated through PR #5 (main d879fd6). The adapter loads repository fixtures/acceptance by default; no external fixture path is required.

- `env -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test`: 52 Swift Testing tests passed across the integrated suite, including B's tests; this is not an A-only count.
- `python3 fixtures/acceptance/check.py`: 26 scenarios and 29 files passed, including all negative checks.
- `sh scripts/build-app.sh`: release build passed.
- `test -x dist/Bimeron.app/Contents/MacOS/Bimeron` and `git diff --check`: passed.

A's regressions cover byte equality (BOM, LF/CRLF, mixed endings, EOF), decoded no-op, comments/unknown content, disabled draft persistence through ProfileLibrary, ambiguity loading, omitted defaults, optional clearing, rule edits/toggles/reordering/insertion/deletion, explicit import transformation followed by no-op save, and comment preservation when removing an empty ShadowTLS block. The parameterized byte adapter covers all eight stable A scenario IDs. Missing fixture roots fail clearly rather than silently skipping coverage.

## Limits

Portable acceptance fixtures omit Profile.Version and sometimes required access fields. Their exact Data pairs exercise ConfigDocument and the library's atomic restore/write/load path; ordinary update correctly fails validation and retains original bytes. These fixtures do not establish successful validated import/editor-save acceptance. Separate complete-profile tests cover actual import, update, disabled save/reopen/re-enable/update, byte preservation and secret/comment restoration.

No live editor interaction, Core CLI/service integration, connectivity acceptance or remote CI result is claimed. Detailed ShadowTLS compatibility belongs to Core validation; the existing basic-check warning remains. Unsupported encodings stay in Raw rather than receiving guessed form values.
