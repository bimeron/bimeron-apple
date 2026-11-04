# docs(acceptance): add shared scenarios and synthetic fixtures

## Description

Add initial item 13 acceptance artifacts for A profile preservation, B CLI
validation and C daemon lifecycle. The manifest ties stable IDs and expectations
to byte pairs and adapter-neutral synthetic transcripts, with pinned desktop
references. A portable offline checker verifies fixture integrity and rejects
corruption. These artifacts do not establish passing application acceptance.

## Validation

Run `python3 fixtures/acceptance/check.py` (includes negative corruption checks)
and `git diff --check`. Actual implementation results are reported in the handoff;
previous baseline build/test/CI results are not current-check evidence.

## Integration still needed

CI owner adds the checker command to an existing workflow. A/B/C add adapter and
application tests using stable IDs, including verified CLI parser samples and
ShadowTLS toggle round trips. Live macOS checks remain pending daemon/launchd
readiness and explicit authorization. No remote issue/PR, push or network run is
part of this local draft.
