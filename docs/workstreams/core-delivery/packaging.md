> Historical ba-22 installer design. Superseded by #79; the package builder and
> installer were removed. See [current development launch](../bundled-core-control/README.md).

# Unsigned local development package preparation

Issue: https://github.com/bimeron/bimeron-apple/issues/13.

This offline builder packages explicitly supplied bytes. It does not download,
execute or authenticate Core. Current signed Core release manifests do not cover
macOS; there is no trusted Apple key pin or compatibility policy. The whole pkg
is untrusted transport. Root ownership, embedded hashes and metadata do not cure
that blocker. Do not use this as verified release delivery or public distribution.

Run as an ordinary developer on macOS, using an existing private output directory:

```sh
python3 scripts/core-install/build.py \
  --binary /absolute/path/to/bimeron \
  --sha256 <64-lowercase-hex-digest> \
  --version <expected-version> --revision <expected-revision> \
  --architecture arm64 --owner-uid 501 \
  --output /absolute/private/output/core-local-dev.pkg
python3 scripts/core-install/test.py
```

The builder reports package and binary SHA256. Supply a newly named output; it
never overwrites an existing package. On pkgbuild failure it unlinks only its
reserved output, never recursively deletes user paths. Use a directory controlled
by the builder with no concurrent writers; path checks are not protection from a
malicious process running as the same developer. Temporary staging is disposable.
No Apple Developer Program identity, signing or notarization is used.

Version, revision and architecture are assertions supplied by the developer,
not independently inspected or authenticated. `arm64` and `x86_64` are accepted
package architecture labels; Core CLI reports the latter as `amd64`. No CPU or
compatibility gating is inferred from these labels. Tests intentionally package a
shell fixture without running it; they do not establish real Mach-O compatibility.

## Fixed payload and probe metadata

- `/Library/PrivilegedHelperTools/org.bimeron.core`: root:wheel, 0755.
- `/Library/LaunchDaemons/org.bimeron.core.plist`: root:wheel, 0644.
- `/Library/PrivilegedHelperTools/org.bimeron.core.dev.json`: root:wheel, 0644.

The JSON schema is exactly:

```json
{
  "schema_version": 1,
  "provenance": "local-development-untrusted",
  "binary_path": "/Library/PrivilegedHelperTools/org.bimeron.core",
  "sha256": "<64 lowercase hex digits of binary bytes>",
  "expected_version": "<developer assertion>",
  "expected_revision": "<developer assertion>",
  "expected_architecture": "arm64 or x86_64",
  "owner_uid": 501,
  "metadata_authenticated": false
}
```

An app probe must retain the untrusted classification, inspect ancestry, file
ownership/modes and actual bytes separately, and treat daemon registration,
IPC compatibility and session state as separate observations. Metadata is not a
trust root or evidence of runtime identity. This preparation adds no app integration.

## Eventual explicit installation only

Neither building nor testing installs anything. Only a later, separately authorized
Installer run executes preinstall/postinstall as root. Preinstall supports missing
helper/launchd leaf directories under protected `/Library`, rejects symlinks,
non-root:wheel or group/other-writable ancestry, existing payload/metadata/plist,
and an already registered service. Ancestry and payload ACLs must be absent or
deny-only: allow ACLs are conservatively refused, including read-only grants,
until principal/right analysis is required by a real installation. Postinstall requires the installed directories
and files to be protected and checks all three payload hashes before bootstrap.
The target must be the live `/` volume. A failure after payload copy may leave a
partial install; reruns deliberately refuse it.

The UID is bound to the intended target host, even when built on a different Mac.
Choose its intended local human explicitly: numeric UIDs below 501 are rejected.
At installation it must resolve uniquely in the local directory, have a non-system
name, a home under `/Users/`, and a shell other than false/nologin. These checks
cannot establish human intent; verify the account on the target before installation.
UID reuse or account changes require revisiting this binding.

The root daemon argv is exactly `[/Library/PrivilegedHelperTools/org.bimeron.core,
"daemon"]`, with `BIMERON_CONTROL_UID` and a fixed system PATH. This command shape
was checked against Core `7cc55f07ce2c48be4071b155c3dd58cf925a88ae`,
`cmd/bimeron/daemon_unix.go`; supplied binary metadata does not prove it matches
that source. RunAtLoad starts the control daemon when installed/booted; there is
no KeepAlive respawn loop, VPN start request, or startup recovery claim.

Updates, repair and removal are unsupported until guarded shutdown and confirmed
cleanup are designed and accepted. No uninstall/force script is supplied.
`/var/db/bimeron` and profiles are untouched. Offline checks expand the package,
inspect BOM root:wheel ownership/modes, exact payload paths, plist and metadata,
reject malformed/tampered inputs, and test filesystem refusal helpers in a sandbox.
They never run Installer scripts, launchctl bootstrap, Core, a production socket,
or VPN operations. Real Installer, account resolution, launchd and hardware
acceptance remain untested and need a separately authorized test Mac session.
