# Shared acceptance scenarios — initial item 13

Workstream D supplies observable contracts and portable synthetic inputs for A
(profile preservation), B (CLI validation), and C (daemon lifecycle). The machine
index is [manifest.json](../../fixtures/acceptance/manifest.json). IDs are stable;
owners identify workstreams, not existing classes or test targets. Every case is
`adapter-test-pending`. Fixture integrity is executable now; application acceptance
is not established by these artifacts.

## Scope and provenance

Desktop reference: `296130e3e5f255410dd70c0680b37b0ed351165b`, inspected locally at
`/tmp/bimeron-desktop-audit.XrKHna`. Pinned source links are recorded by reference ID
in the manifest:

- `desktop-edit`: [GUI editing contract](https://github.com/bimeron/bimeron-desktop/blob/296130e3e5f255410dd70c0680b37b0ed351165b/docs/gui-profile-editing-contract.md), especially Ownership, Disabled ShadowTLS drafts, and Document boundaries.
- `desktop-edit-test`: [ProfileVlessTest.cpp](https://github.com/bimeron/bimeron-desktop/blob/296130e3e5f255410dd70c0680b37b0ed351165b/tests/ProfileVlessTest.cpp#L598), `ProfileEditorDialog::configText()` save/reopen assertions for disabled ShadowTLS, plus BOM/CRLF rule preservation near line 882.
- `desktop-cli-test`: [DeveloperModeTest.cpp](https://github.com/bimeron/bimeron-desktop/blob/296130e3e5f255410dd70c0680b37b0ed351165b/tests/DeveloperModeTest.cpp#L324), `main` fixture branches for `validate` and `version`. These demonstrate fake subprocess testing, not the new synthetic output format.
- `desktop-connection`: [connection management contract](https://github.com/bimeron/bimeron-desktop/blob/296130e3e5f255410dd70c0680b37b0ed351165b/docs/connection-management.md), Contract and Scheduling and lifecycle.
- `desktop-lifecycle-test`: [ConnectionManagementTest.h](https://github.com/bimeron/bimeron-desktop/blob/296130e3e5f255410dd70c0680b37b0ed351165b/tests/ConnectionManagementTest.h#L1683), existing-session fake status and subsequent lifecycle assertions.

These references motivate the observable contracts, not claims that desktop tests
use these fixtures or prove macOS behavior. Core compatibility reference is
`v0.3.0-beta.2`; no Core execution or Core source audit is included here. The older
[model fixture provenance](../../Tests/BimeronModelTests/Fixtures/README.md) cites
`6af5d72bd7e1e98461e78f437509a1994f395fab`; it is a separate revision and must not
be relabeled as the beta.2 reference.

The fixed design uses a privileged Core daemon owning utun. Core owns routes,
DNS, and cleanup. There is no Network Extension or fallback path. launchd
integration and kill switch readiness remain pending. Desktop service/backend
implementation details do not establish corresponding macOS implementation.

## Fixture semantics and consumption

Read paths relative to `fixtures/acceptance`, using binary reads for `.conf` files.
The manifest records SHA-256 for every input, expected output, and transcript.
The local `.gitattributes` disables config newline normalization and recognizes
intentional CRLF in Git whitespace checks; do not run a formatter on these files.
All content is synthetic with placeholder credentials and `example.invalid`
hostnames. Config examples are preservation inputs, not certified valid Core
configurations; keep validation stubs separate from config parsing.

A: drive the actual import/edit/save/reopen path. Compare no-op and canceled saves
byte-for-byte with the input; compare the explicit Profile.Name edit with the
paired expected file. BOM occurs exactly once; CRLF and absent final newline
survive. Unknown keys, sections, comments and disabled ShadowTLS data survive.
The ambiguous input includes duplicate keys and sections: visual editing must
refuse to choose, retaining original bytes and the Raw draft. Raw edits may still
need Core validation. The disabled ShadowTLS pair verifies retaining the inactive
draft during an unrelated edit; enable/disable/reopen round trips remain an
additional adapter test obligation, as specified by the desktop contract.

B: inject a fake process runner that returns each process-result object. Map
`operation` to the eventual adapter operation without assuming argv or an API
exists. `stdout`/`stderr` are deliberately synthetic strings, not Core output;
`decoded_observation` is a test oracle for the parsing boundary, not a field sent
by Core. For real parser tests, replace synthetic text with separately verified,
version-pinned CLI samples and assert the same outcome. Missing, unsupported,
malformed, failed, timed out, canceled, or truncated results never authorize a
save/start. Timeout/cancel must terminate and reap the owned probe and ignore late
results. A successful static validation does not prove daemon support or a tunnel.
CLI and daemon identity must remain separate. Diagnostics must be bounded and
must not expose actual credentials.

C: translate event strings into fake daemon observations or explicit user
intentions. They are adapter-neutral events, not IPC packets. `expected_commands`
is the complete ordered mutation log; read-only reconciliation is permitted.
Assert commands at event boundaries: no start B before `observe-stopped`, including
while stop is pending. `observe-stopped` means authoritative stopped state with
cleanup confirmed, not merely a stop acknowledgment. Failed stop forbids start B.
`request-connect:A` is an idempotent explicit connect intention, not the desktop
activate-profile toggle. Repeating it while connected cannot create a second
session; repeated disconnect while already stopped cannot send another stop.
Adoption sends no mutations. IPC loss retains uncertainty even if the last known
session was connected; resynchronize before making further mutation decisions.

No sibling APIs, test targets, or IPC schema are assumed. A/B/C can load the JSON
with their own test helpers, preserve the IDs in test names/results, and consume
byte pairs with native binary I/O. Add adapter tests in their own workstreams;
this workstream does not modify sibling tests.

## Offline verification and CI integration

From repository root, with Python 3.9 or newer:

```sh
python3 fixtures/acceptance/check.py
git diff --check
```

The executable uses only the Python standard library, performs no subprocess or
network operations, checks links, hashes, required scenario IDs, byte pairs,
process completion consistency, and lifecycle expectation invariants. It always
runs negative checks in temporary copies: byte corruption, missing required
coverage, and an unsafe failed-stop start expectation with a recomputed hash must
all be rejected. It checks artifact consistency, not an application's behavior.

The existing [macOS workflow](../../.github/workflows/macos.yml) runs the checker
immediately after checkout. CI is configured; a passing remote run has not yet
been observed. No package install, Core binary, privileges, secrets or network
setup is needed for the checker. Add adapter suites when A/B/C land; keep their
results separate from fixture integrity. Real CLI parser samples and live
acceptance remain pending. No benchmark is useful for this small fixture index;
runtime responsiveness belongs to adapter/application tests.

## Pending live manual acceptance — checklist only

Do not run this checklist as part of fixture validation. Execute later in an
explicitly authorized isolated macOS environment after daemon installation and
launchd integration are ready, with a known rollback plan and synthetic profiles.

- Record app/Core version, daemon identity, OS version and test profile identity.
- Verify actual CLI version/capability discovery and valid/invalid validation.
- Import, no-op save, edit and reopen byte-preservation profiles; inspect exact
  bytes and ambiguous Raw behavior without starting their placeholder endpoints.
- With separately provisioned test endpoints, connect/disconnect repeatedly and
  reopen the app to verify adoption without replacing the existing tunnel.
- Interrupt IPC; confirm the UI shows uncertainty and does not claim cleanup or
  start a replacement tunnel. Restore IPC and reconcile authoritative status.
- Switch profiles: verify successful Core cleanup before replacement start. Inject
  stop failure and confirm no replacement starts.
- Observe utun, routes and DNS before/after clean stop and failures; verify Core
  cleanup. Do not infer cleanup from app exit or IPC disconnection.
- Record evidence and unresolved failures. Kill switch and launchd readiness need
  their own completed acceptance evidence before release claims.

No live networking, privileged daemon, route/DNS changes, build, or application
test suite was executed for this documentation/fixture workstream.
