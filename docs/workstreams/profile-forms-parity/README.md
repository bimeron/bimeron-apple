# Profile editor parity (H)

Implements issue #14's editor scope against Desktop `296130e` (`ProfileEditorDialog::parameterFields` / `buildText`) and Core `66d84d8f4dcfc6ada625eb11894b19feea51b7ba`. The second Core audit directory is a source export without Git metadata, so it is not used as revision evidence.

The Add dialog accepts an access URI or configuration path, matching surrounding quotes, `~`, and `file://`. Browse selects a file; Create in editor opens a new unsaved draft. URI addition and file import retain their existing **local-only** checks. The UI explicitly describes this distinction. Imports keep existing inlining and relative file-reference handling.

Creation offers SS, SOCKS5, VLESS, SSH, Trojan, HTTP, HTTPS, Naive H2, MASQUE, Hysteria2, VMess, TUIC, AnyTLS and Naive QUIC. Each variant retains an independent document and parameter draft. Switching protocols does not clear another protocol's credentials or transport settings. Hysteria2, VMess, TUIC, AnyTLS and Naive QUIC generate the same URI contracts as Desktop: VMess uses base64 JSON; the other four use percent-encoded credentials and query values, with bracketed IPv6 hosts. Unsupported options remain editable through Raw or an imported opaque URI. Generated URI parameter forms are only for newly created profiles.

Imported URIs are never decoded and re-encoded for saving. VLESS inspection is read-only and masks credentials and potentially identifying extension values until Show access key is enabled. Explicit forms mask passwords and VLESS identifiers. Protocol selectors offer supported cipher, plugin, transport, security and flow choices while retaining previously configured values. Inactive options remain present; compatibility guidance and authoritative Core validation prevent silent field deletion. ShadowTLS rejects known incompatible explicit settings and Naive QUIC locally; Core remains authoritative for opaque URI details, plugin combinations, SS2022 key lengths, transport conflicts and advanced XHTTP settings. Toggling a disabled ShadowTLS draft on and back off restores its original block bytes during the editing session, including comment spacing and line endings.

New editor profiles must pass actual Core CLI validation of a protected `0600` staged file in the profile directory. The staged bytes are checked again after validation. Cancellation before the exclusive atomic commit prevents creation; rejected, tampered or cancelled drafts produce no partial profile. Existing editor updates continue to use F's protected staging, original-byte conflict check and atomic replacement. Raw text and existing comments, unknown fields, BOM and mixed line endings remain protected by the document model. Editing a generated link in Raw keeps Raw authoritative: switching back to parameter controls requires restoring the generated draft, rather than silently overwriting Raw changes.

No validator fallback is supplied. An absent Core executable fails closed for editor saves and creation. The resolver remains owned by G: an absolute `BIMERON_CORE_EXECUTABLE` or bundled helper is required. There is no bundled Core binary in this checkout. This work does not install Core, connect to SSH/VPN servers, change a running daemon, add dependencies, package helpers or change GeoData.

Validation covers creation draft isolation, URI encoding (IPv6 and special credentials), VMess JSON, opaque VLESS inspection and lossless unrelated edits, unified path normalization, ShadowTLS compatibility/restoration, exact staged bytes and permissions, cancellation, tampering, validator rejection, cleanup and fail-closed AppModel integration. Existing A/F preservation and editor-save tests continue to run. A fake CLI verifies transport invocation only; it is not evidence that real Core accepts a generated configuration. A real-Core fixture pass requires an existing executable, which was not found in either audit checkout.

## Verification result

- `swift test`: 69 tests passed (baseline: 59).
- `scripts/build-app.sh`: release app build passed.
- `git diff --check`: passed; EN/RU catalogs have identical 220-key sets and no duplicates.
- No real Core executable was present in the audited checkouts; real generated-fixture CLI acceptance and interactive VoiceOver/layout checks were not performed. No network connections were started.

One intermediate full test run hit the existing malformed-JSON CoreCLI fixture's timeout under build load; subsequent complete runs passed. The first compiler attempt also exposed a Swift IRGen crash when a method reference was used directly as a `Binding` setter; using an explicit closure resolved it.
