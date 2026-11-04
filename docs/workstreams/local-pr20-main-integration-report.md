# Local PR20 preparatory source integration

## Inputs and scope

Worktree: `/Users/wrk/.t3/worktrees/bimeron-macos/t3-bbef89f8`.
Branch: `integrate/pr20-preparatory-20261104`.

The no-fast-forward merge has ordered parents:

1. Actual PR20 head `51cdb65cf69cc737e9a9677b636801e0049a4477`, matching the local `origin/feat/core-delivery-daemon-install` ref.
2. Exact main `cc23d9e458e0bbf6a67ac39007b1f6026c2e821e`.

The user authorized accepted preparatory source integration. This does not establish delivery, installation, runtime or release readiness. Issue #13 remains open; Core85 and main issue closure are not authorized.

The merge was automatic with no conflicts. No manual source resolution or production feature was added. AppModel is byte-identical to main, retaining H creation/import/editor validation routing and J explicit update/validation diagnostics. Existing H tests retain main's disposable IsolatedAppSettings helper. The only source difference from main outside PR20's additive consumer/package paths is ProfilesView: Connect uses `.disabled(true)` and has no Return shortcut. K focus/help remains intact. I SSH library/test targets and unconditional runtime-send rejection remain intact. Both localized dictionaries are the exact union of the two inputs.

PR20 `.github/workflows/macos.yml` is byte-identical, SHA256 `5ada769ca1130ed7c126f893247954a88cc970ffba1776a272fe6d8e6ca47c94`. Both push and PR exact-head routes remain unchanged. No external variables were changed. Only the two pinned histories and this integration commit are included; no additional owner history or rehearsal commits were imported. Prior integration reports were reference material only.

## Offline evidence

Ignored evidence: `.build/pr20-integration-evidence/`.

Tests and package builder were inspected before execution. Package tests build and expand temporary synthetic packages, inspect payload/BOM/plists and syntax-check generated scripts. They source only pure guard functions against temporary paths; generated Installer scripts are never executed. Consumer tests use synthetic keys/bytes and the committed publisher synthetic signed vector, without release downloads or live trust. Swift subprocess tests use temporary synthetic shell fixtures and injected daemon state/exchanges. Child test environments omit real-Core and external fixture overrides; external settings remain unchanged.

- Full offline Swift suite: 85 Swift Testing tests and 30 XCTest tests passed, zero failures. The latter include all seven AppleCoreRelease consumer tests. Real-Core opt-in creation test skipped.
- Command: `swift test --disable-automatic-resolution --skip-update --disable-dependency-cache --cache-path .build/integration-cache --manifest-cache local` (`swift-test.log`). No external package dependencies.
- Acceptance fixtures: 26 scenarios, 29 files; three negative corruption/coverage/lifecycle checks passed (`fixtures.log`).
- Package tests: two passed; synthetic candidate was packaged but never executed (`pkg.log`). Synthetic package SHA256: `1bcee729e4db148391a8082f50e08104603ac353b9ea3abd559bf6a20f82719c`; candidate SHA256: `40acf6722e4642b73e4bd363c932b1f45d14e09e00e165d5dfcba302e0f14228`.
- Release app bundle built offline using an ignored copy of the existing build script with this worktree pinned and the same offline Swift flags (`build-app-offline.sh`, `release-bundle.log`). Tracked script unchanged; bundle not launched.
- Bundle Info.plist and both localization files pass plutil. Executable, icon, PkgInfo, macOS 14.0 metadata and bundled translations verified (`integration.log`).
- Both languages contain 233 unique nonempty keys with equal key sets; all 128 literal t() keys covered. Dictionary union, AppModel equality, disabled Connect/no Return shortcut, retained focus and runtime SSH gate checked (`check-integration.py`, `integration.log`).
- Whitespace, exact ordered parents and reachable-history union checked locally. Final commit and diff counts are supplied in the handoff.

## Remaining gates

No shipped trust pin, candidate approval, download, safe extraction, executable selection, runtime hookup, readiness or servicing is established. Existing explicit developer validation override remains unchanged. No public release, signing or notarization is authorized. Synthetic evidence does not resolve the documented real-build provenance blocker, prove actual Installer/launchd behavior, keyboard/accessibility behavior, live Core compatibility or network success.

No remote writes, push, CI runs/watchers, host installation, service bootstrap, production app/Core execution, live network, VPN or real keys were used. Git operations used only `/Users/wrk/.local/bin/git`, with the configured identity and no invented co-author. Parent owns allowlist review, fast-forward publication, both push/PR CI checks, preparatory-only readiness labeling and guarded PR20 merge/remote branch deletion. No issue completion is claimed.
