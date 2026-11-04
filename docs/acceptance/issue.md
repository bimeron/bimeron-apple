# Local issue definition: item 13 — shared acceptance scenarios and fixtures

Problem: A/B/C need a common desktop-aligned acceptance vocabulary and portable
inputs without coupling their implementation APIs or executing live networking.

Deliverable: stable machine-readable cases for preservation, CLI process results,
and daemon lifecycle; byte-exact expected outputs; pinned desktop provenance;
offline integrity checker integrated into existing CI; explicit pending adapter
tests, real CLI parser samples and live acceptance work.

Acceptance criteria:

- Every required scenario has an ID, owner, fixture, expectation, reference and status.
- Original bytes, BOM/CRLF, unknown content, ambiguity and disabled drafts are covered.
- CLI failures and lifecycle uncertainty cannot be mistaken for permission to start.
- Offline checker rejects meaningful corruption and needs only Python stdlib.
- Existing macOS CI runs the checker after checkout; a passing remote run has not yet been observed.
- A/B/C consumption instructions distinguish artifacts from tested behavior; adapter tests, real CLI parser samples and live acceptance remain pending.

Scope: docs/acceptance, fixtures/acceptance and a checker step in the existing
`.github/workflows/macos.yml` on branch `test/acceptance-scenarios-fixtures`,
baseline main `9ef95ae`. No production code, sibling tests or live Core execution.
Settled architecture is recorded in README; no new architecture choice is
introduced. This local issue definition is ready for parent publication; the
parent owns remote issue/PR operations and the authorized push.
