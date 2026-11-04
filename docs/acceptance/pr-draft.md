# docs(acceptance): add shared scenarios and synthetic fixtures

## Description

Add initial item 13 acceptance artifacts for A profile preservation, B CLI
validation and C daemon lifecycle. The manifest ties stable IDs and expectations
to byte pairs and adapter-neutral synthetic transcripts, with pinned desktop
references. A portable offline checker verifies fixture integrity and rejects
corruption. The existing macOS workflow runs the checker after checkout, without
new dependencies or workflows. These artifacts do not establish passing application acceptance.

## Validation

Local checks passed: `python3 fixtures/acceptance/check.py` (includes negative
corruption checks) and `git diff --check`. CI is configured; a passing remote run
has not yet been observed. Previous baseline build/test/CI results are not
current-check evidence.

## Integration still needed

A/B/C adapter and application tests using stable IDs remain pending, including
verified real CLI parser samples and ShadowTLS toggle round trips. Live macOS
acceptance remains pending daemon/launchd readiness and explicit authorization.
No Core or network execution was performed. This draft is ready for parent
publication; the parent owns remote issue/PR operations and the authorized push.
