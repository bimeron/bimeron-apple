# Local PR21 / main integration

## Inputs and merge

Isolated worktree: `/Users/wrk/.t3/worktrees/bimeron-macos/pr21-main-local-20261104`; unique branch: `integrate/pr21-main-local-20261104`.

Merge `157420f427eec5670e468563483995a0a3cefb10` has these ordered parents:

1. Actual PR21 head `450ff05b26fa47b00960b2ada8fea12d0dec8268` (matching the local `origin/feat/profile-forms-parity` ref at preflight).
2. Actual main `a9f026090c901b82fff295735a5bafa2599eb633`, merged with `--no-ff`.

Only the English and Russian localization append blocks conflicted. Both H editor/import and J diagnostics keys and values were retained. Each resulting dictionary equals the exact union of both inputs, without duplicates. AppModel, ProfilesView and Package.swift merged automatically. Key source paths match the reviewed rehearsal tree at `bfa86381313eb2ec132c803c20528613dbdb1914`; no rehearsal history was cherry-picked. K focus/help, H creation routing, J explicit update/validation hooks, all package targets and disabled runtime SSH authentication remain intact. Creation was not relabeled as an update.

The only follow-up code change injects main's existing `IsolatedAppSettings` into the three H creation/import AppModel instances. Its existing cleanup and isolation regression are reused; no duplicate helper or unrelated modernization was added.

## Offline evidence

Ignored evidence: `.build/pr21-integration-evidence/`. Test subprocesses and scripts were inspected: enabled CLI tests use temporary synthetic shell executables (including bounded output and cancellation fixtures); daemon tests use synthetic exchange/state inputs. Profile mutations use temporary directories, settings use disposable suites. Core and acceptance-root overrides were removed only from child command environments, without changing external variables. No external package dependencies exist.

- Full `swift test --disable-automatic-resolution --skip-update --disable-dependency-cache --cache-path .build/integration-cache --manifest-cache local`: exit 0; 85 Swift Testing tests passed, 23 XCTest tests passed, zero failures; opt-in real-Core creation test skipped. Existing settings isolation/cleanup and actual synthetic CLI save/validation diagnostic regressions passed (`swift-test.log`).
- Fixture checker: exit 0; 26 scenarios, 29 files, three negative corruption/coverage/lifecycle checks passed (`fixtures.log`).
- Offline release bundle: exit 0. Inspected local script copy pins this worktree and adds the same offline flags; tracked build script is unchanged (`build-app-offline.sh`, `release-bundle.log`).
- `plutil`: bundle Info.plist and both localization files valid. Bundle executable, icon, resource translations, PkgInfo and macOS 14.0 metadata verified (`plist.log`, `bundle.log`). Bundle was not launched.
- Localization: 233 unique nonempty translations per language, equal key sets; all 128 literal `t()` keys covered (`check-localization.py`, `localization.log`).
- Exact ordered parents, input-history union, localization union and unchanged PR21 workflow verified (`check-integration.py`, `ancestry-workflow.log`). Workflow SHA256: `5ada769ca1130ed7c126f893247954a88cc970ffba1776a272fe6d8e6ca47c94`; both push and pull-request exact-SHA allowlist paths retained byte-for-byte.
- Whitespace checks passed. Toolchain: Apple Swift 6.1.2; only expected `--skip-update` deprecation warning. Before this report, diff against main: 18 files, 1026 insertions, 52 deletions; final diff adds only this report. The follow-up against the merge changes only the H test file (5 insertions, 3 deletions) and this report.

## Boundaries

Reachable history adds only the integration merge and local follow-up to the exact two input histories; no additional L/T/V/W history was introduced. Draft20 `70e7f218c62d8ebcf04813e59d4fac3ecd5e95db` and supplied Core85 `643d4863d468a0a922d792b52aa74b477cfee065` are absent from reachable history. Original owner worktrees and refs were not changed. Git used only `/Users/wrk/.local/bin/git`, with configured identity `solarcadence <4gknw59gyj@privaterelay.appleid.com>` and no invented co-author.

No remote write, push, CI, watcher, issue/PR creation, external variable mutation, system configuration, install, production app launch, live network, Core, VPN, SSH session or real keys were used. Parent owns publication, event-job verification and guarded PR21 merge/deletion. PR20 preparation remains separate and unstarted. These offline checks do not establish visual keyboard/accessibility behavior, real Core compatibility, network success or runtime authentication readiness. Exact final head and final diff counts are supplied in the handoff because a commit cannot contain its own hash.
