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

## Shared acceptance mapping

Dependency: workstream D commit `f8988b7` on `test/acceptance-scenarios-fixtures`,
`docs/acceptance/README.md`, `fixtures/acceptance/manifest.json` and `cli/*.json`.
These were read in D's worktree; no fixtures are copied or loaded here and no
ancestry change is required. D owns fixture integrity and its CI checker.
Combined acceptance adapter integration remains pending on that dependency.
D stdout/stderr are synthetic observations, not Core wire format; parser sample
provenance is recorded in [parser-samples/README.md](parser-samples/README.md).

The following stable IDs appear in CoreCLITests display names. Coverage here is
low-level process/parser behavior only; D's full acceptance scenarios remain
adapter-test-pending.

| D scenario | B test | Verified here / pending caller obligation |
| --- | --- | --- |
| B-MISSING | missingExecutable | Launch error, unchanged input / disable dependent actions |
| B-VERSION-SUPPORTED | versionContract | Selected version schema decodes / compatibility decision, separate daemon identity |
| B-VERSION-UNSUPPORTED | unknownVersionDecodes | Unknown valid version decodes, unchanged input / incompatible action block; no compatibility policy exists |
| B-VERSION-MALFORMED | malformedJSON, missingFieldsRejected | Invalid JSON and missing required field reject / present unknown compatibility |
| B-CAPABILITIES-SUPPORTED | capabilitiesContract | Source-correct macOS flags decode / enable only confirmed operations |
| B-CAPABILITIES-UNSUPPORTED | unsupportedCapabilitiesDecode | Every false flag retained, config unchanged / block unsupported operations |
| B-CAPABILITIES-MALFORMED | malformedJSON, missingFieldsRejected | Invalid JSON and missing nested field reject / unknown support and action gate |
| B-VALIDATE-VALID | validationPreservesArgumentAndFile | Exact path argument, successful exit, unchanged input / save/start gate; no connected claim |
| B-VALIDATE-INVALID | invalidValidationPreservesInput | Exit 1, diagnostic, unchanged input / preserve separate original and draft, block save/start |
| B-NONZERO-STDERR | nonzeroPreservesDiagnosticsAndInput | Exit 7 retains both streams, unchanged input / bounded user-facing failure presentation |
| B-TIMEOUT | timeoutAndCancellationKillResistantProcess(false) | Bounded termination and PID gone, unchanged input / block action and ignore late caller results |
| B-CANCEL | timeoutAndCancellationKillResistantProcess(true), cancellationBeforeLaunch | Reaped process or no launch, unchanged input / retain UI draft and ignore late caller results |
| B-TRUNCATED | truncatedJSONIsRejected, concurrentOutputIsDrainedAndBounded | Reject truncated JSON, independently bounded streams / never infer support |

No UI save/start gates, document integration, compatibility policy, daemon
readiness, launchd readiness, live networking, or actual Core execution is proved.
The process layer's ownership and cleanup limits above still apply.

Verification for this test/docs adaptation (2026-11-04, macOS arm64):
`swift test --filter CoreCLITests` passed (14 test declarations, including
parameterized cases); `swift test` passed (38 test declarations, including
parameterized cases); `git diff --check` passed.
Existing CI runs Swift tests; no hosted CI run or new release build is claimed.
