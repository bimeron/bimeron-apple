# feat: add standalone Core CLI foundation

Add BimeronCoreCLI for the verified Core v0.3.0-beta.2 `version`, `capabilities`, and `validate` commands. Typed CLI capabilities describe static build/platform support only. Validation passes an existing path directly without writing original or draft configuration bytes.

Process execution drains stdout and stderr independently with bounded capture and diagnostic-preserving errors. Timeout and cancellation escalate from SIGTERM to SIGKILL with bounded cleanup. Controlled local fixtures cover JSON contracts, malformed/truncated output, argument preservation, missing executable, exit errors, large simultaneous output, and interruption of SIGTERM-resistant processes.

Shared integration edit: Package.swift adds only the standalone target and its test target. BimeronApp gains no dependency. Existing CI already runs `swift test` and the release app build; no workflow changes are necessary.

Local acceptance results are recorded in CONTRACT.md. This is a local PR draft only: no remote issue/PR, push, hosted CI run, or real Core execution is part of this workstream.

Acceptance mapping follows D `f8988b7` without copying synthetic fixtures or
changing ancestry. Source-derived parser constants are pinned to upstream commit
`66d84d8f4dcfc6ada625eb11894b19feea51b7ba`; macOS IKEv2 flags are all false.
Tests cover unknown versions, all-false capabilities, required-field rejection,
and invalid validation without adding caller compatibility or UI policy.
See CONTRACT.md for stable scenario IDs and pending adapter obligations.
