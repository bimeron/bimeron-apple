# Local PR19 and main integration

## Exact inputs and scope

Branch `impl/pr19-main-offline-20261104` in `/Users/wrk/.t3/worktrees/bimeron-macos/impl-pr19-main-offline-20261104` starts at PR19 `9cbd851c4639ac184bb86b3447ea9b1f793e5f35`. Merge `42ad54a4606816fccca0af12ae739faf356d536e` has that first parent and exact main `f9735226271137883776c041c09a8b046555d2ee` as second parent. The `--no-ff` merge had no conflicts.

The PR19 workflow `.github/workflows/macos.yml` is byte-for-byte preserved, including its existing allowlists. All package targets remain, including isolated BimeronSSHAuth; the app has no SSHAuth dependency and runtime sending still throws unconditionally. Main's keyboard focus restoration and Connect help remain. Diagnostics bounds, snapshot export consent, save/validation hooks and lifecycle observation semantics remain unchanged. No application code was changed after the merge.

Only the relevant test isolation fix from rehearsal `bfa86381313eb2ec132c803c20528613dbdb1914` was adapted: diagnostics AppModel instances now inject disposable settings suites. The regression verifies independent language/theme persistence and suite cleanup. H-only tests and the rehearsal report/history were not copied.

## Offline verification

Local ignored evidence is in `.build/integration-evidence/`. Before running tests, subprocess paths were inspected: CLI and save tests execute synthetic scripts in temporary directories, daemon client tests inject exchanges, and SSH file tests use temporary placeholder files. AppModel tests inject disposable settings; profile-mutating tests inject temporary libraries. Models using the default library only construct it and do not load it. No production settings or profiles were loaded or changed.

- `env -u BIMERON_CORE_EXECUTABLE -u BIMERON_ACCEPTANCE_FIXTURE_ROOT swift test --disable-automatic-resolution --skip-update --disable-dependency-cache --cache-path .build/integration-cache --manifest-cache local`: exit 0; 64 Swift Testing tests and 23 XCTest tests passed (`swift-test.log`).
- `python3 fixtures/acceptance/check.py`: exit 0; 26 scenarios, 29 files, three negative integrity checks (`fixtures.log`).
- `sh .build/integration-evidence/build-app-offline.sh`: exit 0; release build and bundle assembly (`release-bundle.log`). This inspected local copy only pins this worktree and adds the same offline/local-cache build flags; the tracked build script is unchanged.
- `plutil -lint` passed for the bundled Info.plist and both source translations (`plist.log`). Python assertions verified executable bytes/mode, icon bytes, resource bundle, both translation bytes, PkgInfo and minimum macOS 14.0 (`bundle.log`). The app was not launched.
- Localization assertions passed: 188 unique nonempty keys per language, equal key sets, 115 literal translation calls covered (`localization.log`).
- Exact ordered merge parents and workflow bytes passed; supplied Draft20, H21 and Core85 IDs are absent from reachable history (`ancestry.log`). No fetch was attempted.
- `git diff --check` passed. Toolchain recorded in `toolchain.log`; SwiftPM reported the expected deprecated `--skip-update` warning.

## Limits

No remote writes, push, CI, watcher, issue/PR creation, system changes, installation, production app execution, real keys, live Core, network or VPN operation occurred. Git used `/Users/wrk/.local/bin/git` and the configured identity. Original worktrees and owner branches were not changed. H21 remains for later integration; Draft20 requires new explicit authorization and is excluded, as is Core85. Automated checks do not establish visual accessibility/focus behavior, live compatibility or runtime authentication readiness.
