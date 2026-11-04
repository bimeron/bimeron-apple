# Local Core CLI timeout investigation — unresolved

Date: 2026-11-04. Owned worktree: `fix-local-core-cli-timeout-test`.

Tested source: `ace5610e9e3817fb9238f256915898f95ab38f48` (H21). These historical runs do not validate the later integrated main `859f15b` or subsequent changes. The original evidence commit `8fc813e` is preserved locally; this publication branch contains only the report and supporting logs.

The historical timeout failure is not reproduced or closed. No production or test source change is proposed for merge. Only investigation documentation and logs are committed; no fix is claimed. The cancellation-only proposal was rejected as an inadequate fix for the reported timeout failure.

## Scope and safety

Read the audit README, `LocalUIAuditTests.swift`, `evidence/tests.log`, and `evidence/core-retry.log` in the sibling `test-local-profile-ui-audit` worktree without editing it. All test commands explicitly unset `BIMERON_CORE_EXECUTABLE`; real offline Core validation arguments skipped under their existing contract. No real Core runtime, external networking, remote writes, installations, preferences changes, or other worktree edits were performed. The copied render harness used its existing isolated UserDefaults suite and injected profile library; its output destination was changed to this owned workstream. The temporary harness, rendered PNGs, synthetic profile directory, source instrumentation, and experimental test changes were removed after the runs.

## Exact counts and commands

All full-suite runs used `env -u BIMERON_CORE_EXECUTABLE swift test --disable-automatic-resolution`, with the copied render harness present. Reported test counts include the offline test whose arguments skip when the environment variable is absent.

| Evidence | Runs | Result |
| --- | ---: | --- |
| `evidence/before-full-{1,2,3}.log` | 3 | 81 tests passed per run; 0 recorded issues |
| `evidence/instrumented-full-{1,2,3}.log` | 3 | 81 tests passed per run; 6 interruption cases had matching startup/readiness files and PID/ready stderr; 0 issues |
| `evidence/after-full-{1,2,3}.log` | 3 | 81 tests passed per run with the cancellation-only proposal; 0 issues |
| `evidence/traced-full-{1..15}.log` | 15 | 81 tests passed per run; 30 interruption cases had matching startup/readiness files and PID/ready stderr; 0 issues |
| `evidence/gated-before-ready.log` | 1 focused run | 1 parameterized test, 2 arguments, 4 expected experimental issues reproducing missing ready/PID; both independent PID probes confirmed the child was gone |

Total full-suite repetitions: 24; 1,944 reported test executions; 48 resistant-process interruption arguments. No historical timeout failure occurred. The “after” runs evaluate only a partial proposal and do not establish a timeout fix.

## Experiments and findings

The unmodified fixture installs a TERM-ignore trap, writes PID and ready to stderr, then spins. Its one-second timeout does not guarantee shell readiness. Cancellation is requested after a fixed 700 ms, which has the same scheduling assumption.

The gated experiment replaced the shell body with `echo $$ > "$2.started"; while :; do :; done; trap ...`. The loop intentionally prevents reaching the trap or stderr writes. Instrumentation read the independent PID file after interruption and checked `kill(pid, 0)`/`ESRCH`. Both timeout and cancellation produced empty stderr and the original missing-ready/PID expectations, while both processes were gone. This proves those expectations can fail without pipe-output loss. It does not prove the historical failure had this cause.

The normal instrumented fixture first wrote `$$` to `$2.started`, then installed the trap and wrote PID/ready stderr, then wrote `$2.ready`. Catch blocks logged both files and captured diagnostics. All six instrumented and thirty traced interruption arguments showed readiness and captured PID/ready. Temporary CoreCLI tracing also logged monotonic time since `Process.run()` returned, `isRunning`, PID, captured stderr byte count, and presence of the startup marker at interruption. All fifteen timeout arguments captured 12 stderr bytes before stopping, with timeout detection near one second. The tracing did not record first-byte or launch-duration timestamps, so it cannot resolve a startup delay in an occurrence that was not reproduced.

The original audit log shows rendering completed before the resistant-process test started. Direct concurrent rendering at the failure instant is therefore not established, although wider system load remains possible. The historic combined test took 1.919 seconds and recorded exactly the two timeout-argument issues; no side-channel readiness evidence was collected then.

The drain loop retries after observing process exit unless EOF or its bounded exit/stop grace has elapsed. A drain/exit ordering race is conceivable at a grace boundary, but no lost-output occurrence was demonstrated. No production pipe-drain change is justified by these results.

## Proposed follow-up, not implemented

The rejected cancellation-only experiment replaced the fixed cancellation delay with a readiness-file handshake after trap installation and diagnostics, retaining ready/PID/reaping checks and a bounded readiness watchdog. Its longer cancellation-only CLI deadline isolates cancellation from timeout; it does not change the timeout argument. Review identified that this alone leaves the reported timeout problem unresolved, so it was reverted. The unpublished patch remains in the original local evidence commit; it is not part of this publication.

A deterministic timeout-resistance test could use an internal deadline clock dependency: hold the deadline until a readiness handshake, then advance it past the unchanged one-second timeout, preserving ready/PID/reaping assertions and real TERM-to-KILL grace handling. A separate real-clock timeout-before-ready test would retain startup-timeout coverage. Drawback: this introduces a production test seam and still does not establish the historical cause. This architectural option requires parent discussion; no clock seam was implemented.

All production CoreCLI constructor callers were enumerated in `Sources/BimeronApp/AppModel.swift`, app editor tests, the offline Core test, and the CoreCLI fixture. No callers were changed. No production behavior change is claimed.

## Handoff

Keep the timeout issue open. Review the preserved logs and choose whether deterministic clock control is warranted or whether a future observed failure should first collect readiness/output side channels. Broad repetition was stopped after fifteen traced runs. No background test/render/fixture process was intentionally left running; final process inspection found none associated with the owned test execution. No CI equivalence is claimed.
