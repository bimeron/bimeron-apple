# Offline editor interaction mode

Build without launching AppKit:

```sh
HARNESS_BUILD_ONLY=1 HARNESS_MODE=editor scripts/local-ui-harness/run.sh
```

Only after acquiring exclusive screen access, execute:

```sh
HARNESS_MODE=editor scripts/local-ui-harness/run.sh
```

The existing 150-second watchdog remains unchanged. The mode has fixed loops over
14 variants, two languages and two appearances; no retries repeat mutations.
The runner copies unchanged production sources into a temporary package, retains
source hashes and build evidence, and requires sandbox write/network denial before
launch. Editor mode does not update the integrated audit's latest-run pointer.

The editor-only mode uses an explicit temporary ProfileLibrary, MemoryDefaults and
the runner's mock validator. It never instantiates AddProfileView, opens file
panels, reads the clipboard, sends global keys, requests permissions or uses real
Core/profile data. Native control inspection logs synthetic values only.

Runtime assertions cover:

- Server and port text acceptance in all 14 creation variants, checked against Raw
  explicit fields, parsed URI endpoints or decoded VMess JSON.
- Selected secret/UUID control text acceptance and native secure-control type;
  secret/UUID persistence and draft restoration are not asserted.
- Revisit of all variants after intervening edits to verify independent drafts.
- Generated Raw authority, exact Restore bytes, mock save dismissal and exact
  persisted bytes without duplicate profiles.
- English/Russian, light/dark mock rejection, sheet-level secure-control existence/removal on reveal,
  own-window Tab focus, and dirty cancel/keep/discard when AX exposes the dialog.
- Stored bytes remain unchanged after rejection and cancel; storage equality does
  not establish protection or retention of a dirty edit.

Initial control dumps include both own-process AX and native editable control
metadata. Field lookup requires a unique own-process sheet and a uniquely labeled
AX text field (native title relation or immediately preceding static-text sibling).
Its AX frame must uniquely match an editable native field in that sheet, with every edge within
two points after screen-coordinate conversion (rather than comparing width/height deltas). Geometry only identifies the native
view; editing uses its own window field editor, never coordinate clicks. Missing
or ambiguous labels or geometry fail closed without model mutation. This mapping
requires coordinated GUI validation on the target macOS/SwiftUI runtime.
Opaque cancel dialogs are logged as UNSUPPORTED, cleaned up, and throw an explicit
BLOCKED error after a separate storage-equality check; they cannot reach COMPLETE.

Build success proves compilation only. GUI assertions, localization, focus,
masking and screenshots require execution; no source inspection or mock result
establishes real Core compatibility. Picker-field acceptance, full per-field
coverage, routing tables, Return/Escape behavior and visual quality are not claimed.

Build-only verification on base f48d9c8 succeeded. No GUI execution was performed
while implementing this mode. Build evidence for that verification:
`/private/tmp/bimeron-isolated-ui.wt7bBQ/evidence`.

Locator repair build-only verification succeeded; evidence:
`/private/tmp/bimeron-isolated-ui.gn96Lp/evidence`. No GUI was launched.
VMess Password edits are excluded using the generated field list, generated ID
labels use ProtocolField metadata, and Raw authority reads the current generated
URI host instead of depending on the variant index.

## Bounded GUI repair evidence (2026-11-05)

Two launches were used; both builds and unchanged sandbox preflight passed.
At the time of these launches, production Sources and Package.swift were identical to f48d9c8.

1. `/private/tmp/bimeron-isolated-ui.K7jHcD/evidence`, exit 1:
   diagnostic Server AX screen rect `(99.5, 491.5, 528.5, 16)` versus native
   `(97.5, 491.5, 532.5, 16)`. Each horizontal edge differs by two points;
   the previous width-delta guard rejected the four-point width difference.
2. `/private/tmp/bimeron-isolated-ui.HalW8Z/evidence`, exit 1:
   unique own-sheet four-edge matching passed Server/Port edits and endpoint
   assertions for all 14 variants, then all 14 independent draft revisits.
   Selected Password edits and TUIC/VMess User ID edits passed native focus/text
   acceptance and secure-control assertions. Exact generated Raw restoration and
   mock save bytes/count passed. Name editing and initial sheet-level secure-control existence
   passed for English/light only.

The second run stopped the main sequence at `Missing toggle`: retained AX exposes
`Show access key` as static text followed by an unlabeled checkbox, while the
existing toggle helper requires a labeled checkbox. This is a harness locator
blocker, not an established production accessibility defect. Reveal, subsequent
main-sequence rejection/focus/cancel assertions did not execute.

The same second launch then independently executed own-sheet native Raw editing,
exact-byte mock save with one persisted profile, and localized mock rejection
with unchanged persisted bytes for EN/RU in light/dark appearances. This fallback
did not edit a dirty draft before rejection and establishes storage equality only. Cleanup used
`endSheet`; it establishes no cancel/discard acceptance. The original blocker is
re-thrown, so these passes do not produce a COMPLETE result or exit zero.

The retained second-run source prints a misleading secure-control PASS for
non-secret fields because its condition was vacuously true. A subsequent harness
logging-only correction emits that assertion only for requested secrets; it has
not received another GUI launch. The later claim-narrowing and blocked-Cancel
changes have likewise not received a GUI launch. No all-field, VoiceOver, physical keyboard,
visual quality, or real Core validation acceptance is claimed. No production
fix, commit, push, or additional GUI launch was performed.
