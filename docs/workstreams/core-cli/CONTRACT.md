# Core CLI contract and acceptance

Source baseline: [bimeron/bimeron-core v0.3.0-beta.2](https://github.com/bimeron/bimeron-core/tree/v0.3.0-beta.2).

Verified upstream source:
- [Command dispatch](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/cmd/bimeron/main.go): `version`, `capabilities`, `validate <config-file>`; no `--version` or `--json`.
- [Version command](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/cmd/bimeron/version.go): zero arguments returns build JSON. `version -daemon` uses control hello and is excluded.
- [Build schema](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/core/version.go): version, optional revision and commit_time, modified, go_version, platform, architecture. The Swift decoder requires all nonoptional fields and ignores unknown keys.
- [Capabilities command](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/cmd/bimeron/control.go) and [schema](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/core/capabilities.go): zero arguments returns static local platform/build capabilities, without a runtime probe. `CLIPlatformCapabilities` deliberately names this distinction. Its daemon flag does not mean a daemon is running. macOS declares no kill switch.
- [Validation](https://github.com/bimeron/bimeron-core/blob/v0.3.0-beta.2/cmd/bimeron/config.go): exactly one path passed to config.Load. Failure exits 1 with `error: ...` on stderr. Success prints `Configuration valid. No network requests or system changes performed.`

`CoreCLI` launches the supplied executable directly using Foundation Process. It never creates or modifies a configuration. Callers own draft placement so relative file references retain their intended meaning. Core owns routes, DNS, and cleanup; this module does not start a daemon, perform live networking, or operate utun.

Both pipes use nonblocking reads on the asynchronous executor, with bounded work per pass and independent capture limits (default 1 MiB each). Excess bytes are drained and discarded; truncation is explicit. JSON truncated at the cap is rejected even if its prefix could decode. Exit, decode, timeout, cancellation, and read errors retain both streams. Launch errors include the executable and Foundation diagnostic. Timeout starts after successful launch. Cancellation before launch prevents execution. After interruption, SIGTERM escalates to SIGKILL after 200 ms; cleanup stops waiting after one second. A detached timer avoids spinning on cancellation; no blocking process wait or blocking pipe read is used.

Limits: process creation is Foundation's synchronous launch call; cancellation is observed before and after that call. Cleanup targets the direct process, not arbitrary descendants. Inherited descendant pipes get at most 200 ms after direct-process exit; their remaining output may be omitted. This API is for the verified single Core executable, not a general subprocess tree manager. An uninterruptible OS process may outlive the bounded cleanup window. Output contains potentially sensitive Core diagnostics; callers control presentation and logging.

Fixtures are uniquely named in the system temporary directory under BimeronCoreCLITests-prefixed directories and removed after testing. Only test fixtures use shell scripts; production launches no shell. No real Core binary is executed and no network or runtime readiness acceptance is claimed.

Local verification (2026-11-04, macOS arm64):
- `swift test`: passed, 34 test declarations total (24 baseline plus 10 new, with parameterized cases).
- `sh scripts/build-app.sh`: passed, including `swift build -c release` and app assembly.
- `test -x dist/Bimeron.app/Contents/MacOS/Bimeron`: passed.
- `git diff --check`: passed.

An initial release build was invalidated by a source-file move during compilation. The complete build was rerun after edits finished and passed. The initial interruption fixtures used deadlines too short for concurrent Foundation launches; the deadline now starts after successful launch, and the fixture suite is serialized with longer interruption windows. Final tests verify the killed PID no longer exists.
