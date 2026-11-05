# BA-16 protocol forms audit

Source-only audit at `73f6325be47ee3828237788355b587c4673d7ad6`.
No build, test, Core executable, GUI, network, or runtime operation was performed.

The inspected local contract is `README.md` in this directory, backed by
`../core-cli/CONTRACT.md` and `../core-validation/README.md`. Its historical
Core validation evidence is not a new validation result for this change.
The CLI contract remains `validate <file>`; no document mutation API is assumed.

## All 14 creation variants

All variants expose Server and Port. Blank creation ports use the documented
protocol default while imported or Raw-entered ports remain explicit.

| Variant | Port | Form fields beyond endpoint | Representation |
| --- | --- | --- | --- |
| SS | 8388 | Encryption, password, prefix, plugin, plugin options | Explicit shadowsocks |
| SOCKS5 | 1080 | Username, password | Explicit socks5 |
| VLESS | 443 | User ID, encryption, flow, SNI, REALITY public key/short ID/spider path, fingerprint, transport/security/ALPN, WebSocket, gRPC, XHTTP options | Explicit vless |
| SSH | 22 | Username; optional identity and known_hosts file controls | Explicit ssh |
| Trojan | 443 | Password, SNI, transport/security/ALPN, WebSocket and gRPC options | Explicit trojan |
| HTTP | 8080 | Username, password | Explicit http |
| HTTPS | 443 | Username, password | Explicit https, shared HTTP form |
| Naive H2 | 443 | Username, password, SNI | Explicit naive |
| MASQUE | 443 | Username, password, SNI, CONNECT-UDP path, CA file | Explicit masque |
| Hysteria2 | 443 | Password, SNI, ALPN, fingerprint | Generated hysteria2 URI |
| VMess | 443 | User ID, encryption, transport, security, transport path/host/mode/extra, SNI, ALPN, fingerprint, REALITY public key/short ID/spider path | Generated base64 JSON URI |
| TUIC | 443 | User ID, password, SNI, ALPN | Generated tuic URI |
| AnyTLS | 443 | Password, SNI | Generated anytls URI |
| Naive QUIC | 443 | Username, password, SNI | Generated naive+quic URI |

`EditorProtocol`, `ProtocolField`, `ProtocolDrafts`, `EditorView`,
`AddProfileView`, `AccessProtocol`, and relevant `ConfigDocument` methods were
read before changes. Field mappings match the locally documented contract;
the initial source audit established no protocol-form defect.
Passwords, IDs, REALITY key/short ID, and SS plugin options have secret metadata.
Explicit choice controls retain unknown current values. Inactive transport
fields remain in the document, with compatibility feedback and Core validation.
Unsupported generated options remain available through Raw or opaque imports.

## Preservation and existing coverage

`EditorCreationTests` already covers draft isolation, URI credential/IPv6
encoding, VMess JSON defaults, inactive values, default-port tracking, generated
save guards, changed/conflicting Raw sources, and byte-preserving restoration.
`OfflineCoreCreationTests` has an opt-in validation case for all 14 variants.
`AccessLinkTests` and `SSHFileSelectionTests` cover optional SSH paths, default
suggestions, path preflight, role-specific sanitized errors, and omission for
other protocols. These behaviors were left unchanged.

The new `ProtocolDraftMatrixTests.swift` broadens behavior coverage to round trips
from each of the 14 variants through every other variant, retaining unknown
AccessKey fields, comments, BOM, mixed line endings, and a missing final newline.
It also checks Raw-save authority, blocked form saves/switches, unchanged selected
parameters, and exact generated-source restoration for all five generated
variants. These tests have not been compiled or executed.

Raw imports are not decoded/re-encoded. Generated field edits update only the
generated source value in the current document. Raw changes to that source block
returning to stale parameter controls unless explicitly restored. Unrelated Raw
fields remain intact. Existing SSH preflight and compact status/focus code were
not modified. No routing changes or proposed EditorView hunks are needed.

## BA-17 file-selection follow-up

BA-17 confirmed that Browse assigned `url.path`, after which
`ProfileInput.normalized` could trim a trailing space from the selected filename
and import a different sibling. With main's authorization, the Browse assignment
now uses `url.absoluteString`, preserving filename whitespace through URL
encoding. The existing `response == .OK` and `let url` guard is unchanged.
This is the only production change in this workstream.

BA-17 owns the new `ProfileImportFileSelectionTests.swift` regression coverage
for distinct `Profile.conf` and `Profile.conf ` siblings, URL input identity,
and unchanged bytes. BA-16 does not duplicate that test or claim it was run.

## Remaining verification

### Coordinated verification update

After the source audit, a fresh independent Sol MEDIUM review found no issues
requiring changes, including the Browse URL hunk. The ba17 regression file was
not present in this worktree and was not reviewed or executed here.

The owner then ran exactly two separately authorized commands in exclusive
local slots, without source or assertion changes between them:

1. `swift test --disable-automatic-resolution --scratch-path .build-ba16 --filter 'BimeronModelTests/(protocolDraftSwitchingPreservesEveryVariantBytes|everyGeneratedDraftKeepsChangedRawLinkAuthoritative)'`
   exited 0 but selected zero tests. This is compilation evidence only.
2. `swift test --disable-automatic-resolution --scratch-path .build-ba16 --filter 'protocolDraftSwitchingPreservesEveryVariantBytes|everyGeneratedDraftKeepsChangedRawLinkAuthoritative'`
   exited 0 and passed two Swift Testing functions with 19 argument cases:
   14 variant matrix cases and five generated Raw authority cases. The reused
   build took 0.29 seconds; the test run took 0.080 seconds.

Logs are retained in `evidence/ba16/initial-filter.log` and
`evidence/ba16/corrected-filter.log`. The XCTest wrapper selected zero tests in
both runs; the corrected run's separate Swift Testing result selected and
passed the intended functions. This is synthetic model behavior evidence,
not native GUI, Core acceptance, or live connection proof. Both execution
slots were released immediately after command exit. No broader checks ran.

The existing broader model/app tests have not been rerun locally. No standalone
`swift build`, app build script, setup, offline Core validation, or
GUI/keyboard/focus/VoiceOver check was performed. Runtime acceptance and complete
Core option validation remain outside this audit. Issue13 remains open and the
Core79 native VM proof hold is unchanged.
