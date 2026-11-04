# W reconciliation with final T static gate

Local design/prototype only; no production staging authorization. This supersedes the earlier README statement that T mode/EOCD/ZIP64 review was pending. Historical experiment/review records remain unchanged.

## Exact inputs and evidence

Read-only inspection used T code `52be97decbc9d583e22cea8c979ae1914fa5d8eb` and final evidence report `a4acbf146624f5f593189f6ac1a211fa1dc19a14`, path `docs/workstreams/core-delivery/local-apple-packaging-evidence.md`, in `test-local-apple-version-verifier`. Exact producer remains Core `e8de435`. T reports independent review four with no actionable P1/P2 findings. Final parent verification used `.build/apple-interop/vectors-round3-fix`, actually 348 entries: 27 XCTest and 59 Swift Testing tests, followed by pinned Core `PASS 348 Core archive vectors`. Earlier parent runs on `vectors-final` loaded 94 entries and are not evidence for 348. These are attributed T results, not suites rerun by W. Both CPU archives were checked statically; neither was executed.

## Interface decision

No material handoff interface change was found. `AppleCoreRelease.verifyArchive(_:manifest:)` still hashes the supplied Data, calls `AppleArchiveGate.check`, and returns `AppleCoreReleaseVerifiedArchive` containing only `manifest` and `data`. Construction is fileprivate. `AppleArchiveGate.check` still returns Void, creates decoded `contents` in the entry loop, validates them and discards them, then checks the final required entry set. It does not return the three owned contents or authenticated evidence envelope required by W's proposed seam.

`AppleCoreReleaseManifest` still retains tag, source revision, core version, architecture and archive name/size/hash. It does not retain original signed manifest/signature, key identifier, compatibility fields or approval/policy/context identities. The verifier takes manifest bytes, signature, trusted key, approval and app/channel/architecture context separately. Current concrete ingress bounds are manifest <=65536 bytes and canonical signature exactly89 bytes; these can inform future envelope design but do not bound every proposed context field or authorize a trust configuration.

Consequently W must not adapt the existing public archive result by reopening/reparsing ZIP or calling another decoder. The synthetic gate remains the only prototype input. A future T/coordinator interface change, after architecture approval, must retain exactly the already-checked owned decoded contents and original evidence and return them only after the final complete-entry-set check. Existing public `let Data` still does not establish independently owned backing. The ownership copy must precede actual authentication; W's mock gate demonstrates only control flow and decoded snapshot behavior.

No U worktree edit or new U task is needed for an unchanged interface. This reconciliation records the final acceptance semantics that any later U revision must reference instead of treating U's older parser description as current: final T deliberately permits unused bounded DEFLATE input after EOS, checks exact output size, and models signed compressed-section bounds. It does not require `total_in == input.count`. Creator/type/permission and EOCD/ZIP64 behavior belongs to exact final T, not a copied staging policy. W must not tighten acceptance by adding its own input-consumption or metadata parity checks.

## Memory and prototype decisions

No benchmark rerun or increased allocation is justified by this interface reconciliation. The existing small-fixture results remain measurements of modeled Data retention and bounded staging writes, not of final T's parser peak. Final T still copies compressed slices with `subdata`, allocates inflated output and inspects binary sections; its working memory is additional. Retaining outputs in a future interface can prolong their lifetimes beyond the current per-entry loop, so existing T passing tests do not validate the proposed retention peak.

The maximum remains archive256 MiB plus decoded264 MiB =520 MiB before copies, evidence and RSS. W's measured fixture remains archive8 MiB plus decoded12.5 MiB; largest modeled simultaneous storage33 MiB. The 96 MiB synthetic cap was not raised and no full-size stress was run. No inference that final T uses only520 MiB is valid.

Recommendation remains one decode with three private owned contents, release archive storage when all verifier consumers are done, retain original evidence, and stage with bounded writes/readback. Main must still decide retained-output versus repeat-decode tradeoff, complete peak budget, envelope ownership/bounds, cancellation during inflation and protected-boundary revalidation. S receives an unprivileged candidate only. Production pin/candidate/review configuration is absent; T's completed local code review does not supply it. No extraction, installation or runtime readiness follows.

Changes in W are documentation only for this reconciliation. Existing prototype and measurements are unchanged; no T/U/S/G/E/L or production Sources were modified. No network, remote mutation, CI, installation or archive execution occurred.

Independent Sol LOW read-only reconciliation is retained in `final-t-review.md`. It independently confirms the unchanged seam and unchanged W measurements, and flags stale U parser wording for a future design-document update. Under this task's interface-change condition, U was not modified or awakened; the semantic correction is recorded here for main. No new architecture choice was taken.
