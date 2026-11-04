# Local Core delivery and daemon installation

## Agreed direction

The user approved an unsigned local installer package, a root-owned standalone
Core executable and a system launchd daemon, with one explicitly selected IPC
owner. Apple Developer Program membership is unavailable. Apple signing,
notarization and public distribution acceptance remain separate requirements.
No host installation, launchd mutation, VPN operation or Core release publication
is authorized by implementation approval.

Source baseline: Apple a84e475d76fcc96f9735daaa57bebc46bea9007c. Core guarded
protocol source: 7cc55f07ce2c48be4071b155c3dd58cf925a88ae. This source revision
is not evidence of a published compatible binary. Released beta.2 is unsuitable
for guarded daemon mutations.

## Release-contract blocker

The current schema-1 signed Core manifest covers Windows/Linux archives only.
macOS hashes appear only in unsigned SHA256SUMS. No authoritative Apple public
key pin or reviewed Apple compatibility range is available. The user subsequently approved preparing publisher manifest coverage, an Apple
compatibility policy and an app consumer, without publication or private-key use.
The exact additive wire contract is being coordinated with the Core publication
stream; never treat existing Windows/Linux review as Apple approval. A local
development package can be prepared from explicitly supplied bytes and a pinned
local hash, but cannot be described as authenticated release delivery.

## Initial vertical slice and gates

1. Consume an explicitly trusted Ed25519 public key and signed Core release
   manifest. Verify archive size/hash before safe extraction, then record and
   verify the selected binary hash, version, architecture and revision. No
   implicit downloads, executable discovery or unsigned fallback.
2. Build an unsigned local pkg offline. Use a root-owned executable under
   /Library/PrivilegedHelperTools and root-owned launchd configuration under
   /Library/LaunchDaemons. Configure BIMERON_CONTROL_UID explicitly; do not
   infer an owner from Installer's root environment. Reject unsafe owners,
   symlinks, writable destinations and unsupported upgrades.
3. Treat component integrity, service registration/running state and compatible
   IPC as separate observations. Authenticate root peers before sending data.
   Require protocol 1 and top-level daemon_session_guards:true. Preserve Core
   status.State and Session.id/active; do not infer connectivity from install.
4. Provide available validation Core to the app only after integrity checks.
   Keep developer override explicit. Keep Connect disabled during this slice;
   runtime hookup follows proven installation and lifecycle readiness.
5. Updates, repair and removal must not overwrite a running component or discard
   recovery state. Until guarded stop plus authoritative cleanup and safe service
   shutdown are implemented and tested, refuse those operations rather than
   provide force flags. Preserve /var/db/bimeron and profiles.

## Verification and boundaries

Use synthetic signed archives, malformed manifests, tampered bytes, unsafe archive
paths, incompatible metadata, wrong permissions and injected IPC responses for
negative tests. Offline package expansion checks payload paths, owners/modes,
plist arguments and explicit owner configuration. Never run package scripts,
bootstrap host services or access the production socket in ordinary tests.
Existing Swift tests, acceptance fixture checker and release app build remain CI
gates. Actual Installer/launchd/root peer and utun/routes/DNS cleanup acceptance
requires a separately authorized test Mac session.

The single-owner contract excludes automatic fast-user switching or shared local
VPN control. Socket access authorizes the owning UID, not a particular signed app.
Core auth_reply uses a one-use challenge, not instance/session mutation guards;
GUI scoping cannot replace server-side atomic guards. Auth runtime integration
remains gated and cancellation belongs to the guarded lifecycle stop owner.

## Parallel ownership

This stream owns installation/readiness and connection UI. H owns forms/editor;
I owns SSH/auth contract; J owns logs/export policy and diagnostics; K owns narrow
accessibility fixes. Coordinate small AppModel/export hooks before integration.
