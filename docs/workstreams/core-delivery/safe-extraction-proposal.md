# Safe Core archive staging proposal

Status: local design for discussion through main; no production extractor or acceptance authorization. Signature, independent key pin, candidate approval, reviewed compatibility, archive hash and static checks must all succeed first. Their absent production configuration remains closed. Staging is unprivileged and never executes archive content.

## Local issue and scope

Close the gap between authenticated static archive inspection and a future privileged installer without reopening an attacker-controlled archive path, duplicating ZIP interpretation, or modifying existing user data. This branch contains the issue definition and design proposal only. Publication of these completed documents is authorized; production staging, merge, releases, installation and live acceptance remain outside scope.

Reconciled read-only sources: T reviewed code `52be97decbc9d583e22cea8c979ae1914fa5d8eb`, final report `a4acbf146624f5f593189f6ac1a211fa1dc19a14` and Core L `e8de4354e2dc5d0364a2fb93119c50971cdf8a5c`. The local branch base 70e7f21 only checks archive size/hash; T adds CZlib ZIP/static validation. L e8de435 changes outer builder filenames to the manifest-required `bimeron-v<version>-macos-<arch>.zip`; it does not change inner entry policy, quotas or staging layout. No code from either branch is imported. Final T evidence records independent round-four review with no P1/P2 and parent verification against the actual `.build/apple-interop/vectors-round3-fix` corpus of 348 entries: Swift 27 XCTest plus 59 Swift Testing tests and pinned Core `PASS 348 Core archive vectors`. Earlier 94/130-entry status descriptions are superseded and are not final evidence. This reconciliation reads code/evidence and does not rerun those suites. Both CPUs remain static-only evidence, without archive execution.

S's `docs/workstreams/daemon-servicing-recovery/README.md` separates protected Prepared state and durable operation intent from unprivileged input. Its hosting proposal requires copying into root-controlled staging and validating there. This proposal ends before that boundary.

## Options and recommendation

1. **Retain the three decoded contents from T's existing gate. Recommended.** T already inflates every regular entry to inspect it. Change its internal result, after agreement, to retain owned immutable contents and evidence instead of discarding them. Staging writes only these contents under fixed names. One ZIP interpretation and one decode; no new dependency. Cost: up to 276,824,064 bytes of retained payload plus archive and parser working memory. A later optimization can release archive storage after retaining its digest/evidence. Retained archive plus maximum decoded payload alone total 545,259,520 bytes (520 MiB), before compressed-entry copies, Mach-O section copies, source buffers and allocator overhead; this is not a peak RSS bound. Measure peak RSS before accepting this tradeoff.
2. **Retain owned archive bytes and a private canonical entry plan.** Reuse T's exact parser and bounded inflater to decode again, with offsets/method/sizes bound to that same owned buffer. Lower retained output memory with streaming, but more CPU, more cancellation/error logic and risk of divergence. No public arbitrary-offset plan or independent second parser. Prefer only if option 1's measured memory is unacceptable.
3. **General library or system extraction.** Package.swift at the base has no ZIP library; T adds CZlib. Foundation file APIs do not replace ZIP validation. A libarchive-based reader would need explicit memory input, entry parity and manual writes, plus deployment/linking validation; automatic disk extraction adds metadata/path behavior to audit. Shell `unzip`, `ditto`, or another executable introduces a second interpretation and path reopening. Do not select these for this fixed three-file contract. Apple Compression is not a ZIP policy engine and replacing the existing raw-DEFLATE inflater adds no staging benefit.

No platform/library freshness claims are made; comparison is based on local code and installed SDK, with no network lookup under offline scope.

## Binding and evidence from T

The existing `AppleCoreReleaseVerifiedArchive` stores `let data: Data` and a private initializer. A `let` value does not establish ownership of externally mutable NSData/no-copy/mapped backing. Before authentication, create an explicit owned byte copy from a bounded read; authenticate, hash and parse that copy. Do not take a new copy from the original source after checking it. Ordinary Swift value mutation must not mutate the retained evidence. Do not expose mutable pointers or backed views across the boundary.

A read-only FD protects against pathname substitution but does not seal an inode against writable descriptors, hard links or another process with the same UID. File locks, chmod, unlink and fstat identity checks alone do not supply immutable bytes. Hashing a file then reopening it is insufficient. A memory-backed owned snapshot is the minimal proposal at this archive limit; it is not protection from a compromised verifier process.

Proposed conceptual interfaces, not production declarations:

```text
T: verify owned archive -> VerifiedCorePayload (private construction)
   authenticated manifest identity + archive size/SHA256
   architecture, version, source revision, compatibility and approval identity
   verifier policy revision and static gate result
   exactly three owned contents, canonical role, byte count and SHA256 each

staging: stage(VerifiedCorePayload, owned staging parent, cancellation)
         -> StagedCoreCandidate (private construction)
   operation ID, original evidence, fixed leaf names, counts/hashes
   held directory/file handles and observed filesystem identities

S: accept StagedCoreCandidate as unprivileged candidate input only
```

T currently returns only manifest fields (tag, revision, core version, architecture, archive name/size/hash) plus the original `Data`; `AppleArchiveGate.check` returns Void and discards decoded contents. The proposed result is therefore an interface change, not an existing capability. Retain the exact contents it already checked and construct the result only after the complete entry loop and final required-entry checks succeed; never emit a successful payload after checking the binary alone. The three fixed roles need no exposed local offsets, archive permission values or descriptor fields.

The current public manifest result also omits the authenticated manifest bytes/signature, key identifier, compatibility fields and verification context (app version/channel and independent approval/policy identity). A future cross-process consumer cannot reconstruct these from a binary hash or tag. The proposed evidence envelope must retain the bounded original manifest/signature and bind the verifier policy/context; the privileged consumer obtains its own trust/approval configuration and re-verifies that evidence rather than trusting a serialized success flag. Whether to retain this envelope in T or a private coordinator-owned verified result remains a decision through main. No new trust default is implied.

Evidence records must preserve the trust classification, including explicitly synthetic/untrusted development evidence. A digest is an identity, not an approval. Stage result serialization is advisory bookkeeping; it is not a forge-proof cross-process capability. S must not classify it as root-protected Prepared, installed, running or ready. A later privileged consumer copies from held handles into its own protected destination and revalidates actual bytes and authenticated evidence there. Transferring a user-writable pathname or changing its owner is not the proposed ownership transfer protocol.

## Canonical interpretation and quotas

T remains the sole ZIP interpreter. Central directory names, flags, method, sizes and local payload offsets govern exactly as the agreed Core/T contract specifies. Current policy accepts exactly three regular files and optionally one empty directory: `macos-<arch>/bimeron`, `macos-<arch>/LICENSE`, `macos-<arch>/THIRD_PARTY_NOTICES.txt`, optionally `macos-<arch>/`. Architectures are `arm64` or `amd64`. T/Core intentionally ignore local-header name/flags/method values; only the bounded local header signature and name/extra lengths locate payload bytes. Do not add a local-metadata equality requirement in staging or select an extraction library that does so implicitly. Extraction must never use local names. With central flag 3, descriptors require a 12-byte minimum without signature or 16 bytes with signature, matching descriptor/central/content CRC; descriptor size words are ignored even for ZIP64. Without flag 3, nonzero central CRC is checked, while zero means unspecified. The authenticated archive SHA256 still binds all bytes in either case; do not describe CRC as unconditional authentication. The optional empty parent is not opened, so its local header/payload is not an extraction instruction. Preserve these T semantics rather than independently reparsing descriptors in staging. The final T review is complete; architectural approval for staging remains pending.

Final T also uses pinned Go directory discovery/base-offset, ZIP64 extra-field, signed section-range and creator-mode semantics. Entry counts mean the three or four entries actually enumerated by T, not a new extractor interpretation of EOCD counts or physical header signatures. Unknown Unix type encodings can map to regular files under Go, while recognized links/special types fail the role policy; setuid/setgid/sticky metadata does not itself change Go regularity. Staging must not restore any such bits or metadata, and must not scan ignored container bytes for additional output entries. These parser details stay private to T; the recommended interface still exports only three fixed roles and owned contents after whole-archive success. Option 2 must reuse this final parser rather than recomputing offsets from a stricter container model.

Output is a newly created private candidate directory containing the fixed leaves `bimeron`, `LICENSE`, `THIRD_PARTY_NOTICES.txt`. The archive parent is an accepted marker, not an output path instruction. No normalization, Unicode folding, percent decoding, path joining from archive strings or directory recursion occurs. Reject any extra/duplicate entry, case alias, absolute path, slash/backslash variant, NUL, dot component, traversal, link, device, socket or FIFO through the exact allowlist and entry type checks. Never restore hard links, symlinks, alternate streams or resource forks. Do not broaden archive acceptance to accommodate extraction.

Exact proposed limits, matching current producer/consumer payload bounds:

- Authenticated compressed archive: 1 through 268,435,456 bytes.
- Three required nonempty regular entries; three or four total ZIP entries; optional directory has zero uncompressed bytes.
- Binary: 1 through 268,435,456 bytes; each notice: 1 through 4,194,304 bytes.
- Total decoded/written contents: at most 276,824,064 bytes. Exactly the three validated byte counts must be written, with per-entry and aggregate counters checked before each write/allocation; overflow is failure.
- At most one active staging operation per coordinator, one candidate directory and three output files per operation. No sparse seeks or preallocation based on untrusted size; short writes/EINTR handled, ENOSPC aborts. Available-space estimates are advisory and do not replace counters.

No compression-ratio limit is added: fixed decoded limits and T's bounded inflater govern. End-of-stream and exact decoded size remain T's responsibility. Final T intentionally accepts unused bytes after the final DEFLATE block within its bounded input, matching pinned Go; staging must not impose total_in == compressed input length or decode the unused suffix as another file. Cancellation is checked before each entry, every at most 64 KiB output write and immediately before publish. Cancellation latency during T's existing one-shot inflater is not bounded by those write checks; stream conversion or isolation would be a separate choice. No hard wall-clock/RSS guarantee is claimed by these byte quotas.

## Destination ownership and permissions

The caller cannot choose an arbitrary destination path. The coordinator holds a descriptor for an app-owned staging parent, acquired with no-follow component traversal, directory/type/UID/mode/ACL verification. Parent and candidate have effective UID ownership, mode 0700, and no ACL entries; reject unexpected inherited ACLs. Use an exclusive unpredictable candidate name via descriptor-relative mkdir, then open no-follow and verify identity; do not adopt EEXIST. The parent and candidate must have no concurrent authorized writers.

Create the three fixed leaves relative to the held candidate descriptor with `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC`, mode 0600; require regular type, expected UID, link count one and no ACLs via descriptor checks. Do not restore archive owner/group, permission bits, setuid/setgid/sticky bits, timestamps, flags, ACLs, xattrs or quarantine metadata. Output binary remains nonexecutable 0600 in unprivileged staging; any eventual 0755 installed mode belongs to the later privileged contract. Notices also remain 0600. Reject unexpected output metadata rather than stripping metadata from an existing user object.

Descriptor-relative writes and fixed names prevent archive-driven traversal. Private ancestry prevents other UIDs from injecting names under the stated ownership model. They cannot defeat a malicious same-UID process that can rename entries, grant ACLs or write files. This is a stated boundary, not a root-safety claim. Final fstat/hash checks detect ordinary substitutions but do not turn same-UID staging into immutable protected storage.

## Publication and failure behavior

Write only the private incomplete directory. Check complete writes, file counts, hashes, identity, modes/link counts/ACLs and flush/close results. Publish on the same filesystem using descriptor-relative `renameatx_np(..., RENAME_EXCL)` to a new operation name; never use plain replacing rename, delete an existing candidate, or fall back to cross-volume copy. EEXIST preserves both old data and the new incomplete candidate for owned cleanup. EXDEV is an error. Other consumers only receive a result after successful publication.

The successful exclusive rename is the publication linearization point. Cancellation observed before it aborts and cleans owned incomplete state; cancellation arriving after it returns the published result rather than ambiguously reporting a rollback. If a post-rename bookkeeping/flush error occurs, report a distinct published-but-unconfirmed outcome carrying operation identity for reconciliation; do not delete an uncertain published artifact automatically.

Atomic visibility is not crash durability. Default proposal treats unprivileged staging as disposable: after a crash no candidate is accepted merely because its name exists; revalidate it or create a fresh operation. S's protected journal/durability protocol begins later. If durable staging is required, file and directory synchronization and macOS power-loss behavior need a separate experiment and agreement.

On parsing, write, metadata or cancellation failure, close descriptors and remove only the operation's known three files and empty directory via held parent handles with identity checks. Never follow a substituted link, recursively delete a caller path, glob temp roots or delete profiles/settings/rejected input archives/previous candidates. If identity differs, an unexpected child appears, or cleanup fails, retain the residual, report cleanupIncomplete plus operation ID, and stop cleanup. Stale directories require an ownership/evidence-aware reconciliation policy, not blind age-based deletion. No installer, launchd or VPN side effect occurs.

## Bounded offline evidence

Sol LOW ran synthetic text experiments on macOS 26.5 arm64 in its own temporary directory. All assertions passed: an FD retained ORIGINAL after source pathname replacement; a writable hard-link alias changed that FD's bytes to MODIFIED; exclusive no-follow creation refused an existing symlink with EEXIST and preserved sentinel bytes/inode/mtime; RENAME_EXCL refused an existing empty directory without replacing either; a free-name publish retained directory inode and content.

Artifacts for this session: `/private/tmp/safe-core-experiment-ztpa8cz_/experiment.py` and `results.txt`. These sequential primitive experiments do not test archive extraction, concurrent hostile races, crash durability, root safety or live acceptance. Only synthetic text was written; no payload executable was run. SDK `usr/include/sys/stdio.h` declares RENAME_EXCL and renameatx_np; T's existing raw inflater uses `inflateInit2_(-MAX_WBITS)` and an exact total_out check; final T permits unused bounded DEFLATE input after stream end.

## Decisions and ready next work

Main should discuss option 1 versus memory-driven option 2, the 0600 nonexecutable output policy, disposable staging semantics, and the explicit same-UID boundary. Recommendation is option 1 with those policies. This proposal does not grant implementation approval.

After agreement, T can expose its validated contents/evidence without changing ZIP acceptance; staging can be implemented and tested independently against synthetic privately constructed fixtures; S can specify its candidate intake and protected copy/revalidation boundary. Required staging tests include each quota boundary, duplicate/traversal/link fixtures rejected by T, malicious local-header names never selecting output, external-buffer mutation after verification, write/ENOSPC/close failures, cancellation before/after publication, existing-target preservation, ACL inheritance refusal, cleanup identity mismatch, and interrupted-operation reconciliation. Benchmark peak RSS and staging time at maximum permitted payload sizes. None of these tests authorize root installation or supply missing pin/review approvals.

Dependency assessment: reconciliation introduces no approved independent production task. T static review is complete; W owns the separately authorized measurements/prototype and S owns protected servicing. This design thread does not duplicate W's work. Ownership/memory evidence choices remain pending with main, so staging code, benchmarks requiring a new extraction design, and changes to T/S are not started.
