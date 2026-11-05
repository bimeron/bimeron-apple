# Bundled development Core and guarded GUI control (ba-22)

Tracks #77, related to #13. Production shipping is **false**. No signing key,
Apple review, authenticated release pin, updater, rollback, or service repair is
provided by this change.

The development app contains one native Core executable built from Git object
`6b0d97a4ac96a903153a57d544751401b98d6909`, its notices, and a first-install package.
The builder makes an isolated shared clone and checks out that full commit; it
never builds from or modifies the source repository's working tree. The recipe
requires Go 1.26.9, native Darwin architecture, `CGO_ENABLED=0`, `-mod=readonly`,
`-trimpath`, `-buildvcs=true`, and a fixed development version/build ID. Module
network access and automatic toolchain downloads are disabled during the build.
Cached dependencies are required. CI prepares its dependency cache separately.

Build from the Apple repository root:

```sh
BIMERON_CORE_SOURCE=/absolute/path/to/bimeron-core \
BIMERON_GO=/absolute/path/to/go1.26.9/bin/go \
BIMERON_GIT=/absolute/path/to/git sh scripts/build-app.sh
```

The package is generated for the builder's local human UID. Its manifest and
hashes are consistency checks, **not publisher authentication**. Rebuild for the
account that will own control of the service. The GUI opens macOS Installer only
after an explicit Install Core action. Installer requests administrator approval;
the GUI never runs root commands. Existing `core-install/build.py` preflight and
postflight guards reject existing payloads, unsafe ancestry, wrong ownership,
permissions, hashes, and an already registered service before launchd bootstrap.
A failed or partial install requires explicit administrator investigation and
resume; the app never retries privileged operations or repairs it automatically.
There is no automatic VPN start, including at boot, after install, or on reopen.

The app reconciles with a fresh root-authenticated socket handshake every second
while the main window exists. It requires the pinned daemon's self-reported clean
Darwin revision and v1 session guards before enabling Start. This is development
compatibility evidence, not a trust assertion. Start performs another fresh
handshake and passes the selected library config's absolute path unchanged.
Core hashes that path for profile ownership; no config conversion, copying,
normalization, or preference migration occurs. An active session is stopped
before another profile can be started, with the next Start remaining explicit.
Stop uses the daemon instance and session guards; disconnected is displayed only
on authoritative cleanup confirmation. IPC loss remains unknown. Closing/reopening
reconciles and adopts a running session without starting or stopping it.

Offline tests use injected daemon exchanges, synthetic packages/bundles, and
isolated settings. Actual Installer authorization, protected payload installation,
launchd registration, native VPN and cleanup behavior remain separate, explicitly
authorized acceptance work. No such operations are part of source validation.
