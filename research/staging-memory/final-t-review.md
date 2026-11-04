# Final pinned T interface review

## Scope and disposition

Read-only review of T code `52be97decbc9d583e22cea8c979ae1914fa5d8eb` and report `a4acbf146624f5f593189f6ac1a211fa1dc19a14`, obtained through scoped `/Users/wrk/.local/bin/git -C /Users/wrk/.t3/worktrees/bimeron-macos/test-local-apple-version-verifier show`. Compared actual `Sources/BimeronCoreCLI/AppleCoreRelease.swift` and `AppleArchiveGate.swift` with U proposal `b12d2854ec9839b7e1eaedbd5197bbcbcb0abae3` and this checkout's W README, prototype, recorded prototype results and memory evidence. Read AGENTS.md and the ponytail skill. Only this review file was written; the parent's reconciliation document is outside this review's write scope.

**No new material staging interface change was found.** The owned decoded-output/evidence seam remains the same explicitly known missing capability documented by U and W. Final T changes materially refine ZIP acceptance semantics, requiring U's factual description and source/evidence pins to be reconciled, not a new W API or parser. This review is not an independent universal parser-parity audit or production approval.

## Actual interface versus proposed handoff

- `verifyManifest` authenticates bounded original manifest bytes and checks signature, key identity, approval and compatibility. Its public result retains only tag, source revision, core version, architecture, archive name, archive size and archive SHA256. Original manifest/signature, key identifier, compatibility fields and verifier context/approval/policy are not carried by that result.
- `verifyArchive(_:manifest:)` checks archive size/hash, calls `AppleArchiveGate.check`, then returns `AppleCoreReleaseVerifiedArchive(manifest:data:)`. The initializer is fileprivate; public `let data: Data` is still the supplied value, without an explicit independent byte snapshot before authentication. Private construction and value immutability do not establish independence from externally mutable backing.
- `AppleArchiveGate.check(_:architecture:revision:version:) throws` still returns `Void`. It decodes and inspects regular entries, then discards their contents; final required-entry validation remains after the loop. Neither a decoded payload nor per-role retained counts/hashes is exported. The new internal `ZIPEntry` and `entryMode` helper are parser implementation details, not a staging handoff.
- W's private synthetic `Payload` copies three decoded inputs only after mock complete-archive/count/quota checks. Its `Evidence` is explicitly `SYNTHETIC_UNTRUSTED_MOCK_AUTHENTICATION`. It models U's proposed future result, not an adapter for the actual T result. The prototype still closes candidate descriptors before return, unlike the proposed held-handle contract. These are known limitations, not newly introduced regressions.

Retaining three owned decoded contents and bounded original evidence after complete success still requires an agreed T/coordinator interface change. No successful per-entry callback, arbitrary offset plan, new parser, or production integration is justified here.

## U reconciliation required by actual final semantics

U's pinned T reference and pending-review/130-vector status are historical. Reconcile them to the exact final code/report below while preserving the distinction between recorded evidence and tests personally rerun.

Final T uses creator-aware Go mode interpretation, including DOS creators and unknown Unix type handling; permission special bits are not themselves file types. Staging must consume canonical validated roles and keep its fixed 0600 output policy rather than reinterpret archive attributes or restore them. The fixed three required files, optional zero-sized parent marker and existing byte maxima remain unchanged.

EOCD search/comment handling, ZIP64 sentinel/fallback handling, offset-base arithmetic, directory scan termination and low-16-bit record count comparison now follow the pinned Go behavior. Do not describe the accepted format as requiring strict central-directory adjacency, exact EOCD-at-end, or universally rejected unusual mode/container metadata. These changes belong to T's interpretation; they do not create extraction instructions for W.

**Concrete stale U statement:** U says “Exact end-of-stream, decoded size and input-consumption checks remain T's responsibility,” and its experiment section describes “exact total_in/total_out checks.” Actual final `inflate` checks `Z_STREAM_END` and exact `total_out`, deliberately permitting unused bytes after the final DEFLATE block within the bounded payload. It does not require exact `total_in`. Stored entries require input count equal to declared decoded size. U must describe the actual acceptance contract rather than impose an extra consumption check through staging. Preserve the already reconciled central-versus-local metadata, conditional CRC and descriptor-size semantics.

These are material semantic/documentation corrections. They are distinct from the unchanged missing owned payload/evidence interface and do not require W to duplicate or amend ZIP parsing.

## Correct final evidence attribution

The final report records:

- Independent round-four read-only review of exact code `52be97decbc9d583e22cea8c979ae1914fa5d8eb`: no actionable P1/P2 findings; independent full Swift suite with 348 signed archive vectors and exact mode reproducer hash confirmation. That reviewer did not rerun Core parity or the release build.
- Parent full Swift suite using `.build/apple-interop/vectors-round3-fix`, **348 entries**, at that same code commit: **27 XCTest + 59 Swift Testing tests passed**; report log `.build/apple-parent-348-final.log`.
- Parent offline pinned Go/Core authenticated parity harness against that exact directory: exit zero, **`PASS 348 Core archive vectors`**; report log `.build/apple-parent-core-348.log`.

Earlier passing runs using `vectors-final` covered **94 entries** and must not count as 348-vector evidence. These are separate recorded review/parent results, not executions performed by this W reviewer; logs and corpus were not rerun here. A finite corpus does not establish universal parser parity.

Producer identity remains exactly `e8de4354e2dc5d0364a2fb93119c50971cdf8a5c`; its outer filename alignment does not change W's inner fixed leaves or quotas. Both CPU archives were checked statically: no archived arm64 or amd64 binary execution is established or required by this review.

## W memory evidence and next experiments

W's evidence does not change. Its synthetic 8 MiB archive and 12.5 MiB payload, three repetitions and 96 MiB live-allocation cap still describe the recorded experiment only. Approximately 38.7 MiB peak RSS with an extra owned copy versus 26.1 MiB for the other modeled modes is not actual T verifier RSS. Archive release reduces logical retention without guaranteeing an immediate RSS reduction.

The conditional budgets remain: archive plus payload 520 MiB, payload alone 264 MiB, archive plus two payload copies 784 MiB, two archive copies plus payload 776 MiB, and two of each 1,040 MiB. Evidence, parser entry/name/compressed-data and Mach-O section copies, transient overlap and allocator/runtime costs remain additional. Final T's entry collection and parser behavior have not been profiled by W; the synthetic figures cannot quantify their peak impact. Existing W evidence therefore supports avoiding a redundant staging copy, not accepting a maximum production memory budget.

**No additional local experiment is necessary to resolve this review.** Repeating synthetic suites or benchmarks would not establish the missing real handoff. After architecture agreement and a real owned-output/evidence seam exist, separately scoped work should verify pre-authentication snapshot ownership, retained decoded-byte identity through final gate failure, evidence retention/bounds, and actual parser/retention lifetimes and peak memory on a suitable host. Maximum-size runs, inflation cancellation design, protected intake and filesystem fault coverage remain future decisions, not newly authorized work.

No T/U/S/G/E/L edits, production integration, parser copy, network, install, CI, remote operations, protected access, key operations, repeated suites/benchmarks or commits were performed. Production trust configuration, independent candidate/review approval, honest source derivation, protected copy/revalidation, installation and runtime readiness remain separate gates.
