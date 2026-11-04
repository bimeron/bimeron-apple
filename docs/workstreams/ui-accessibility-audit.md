# UI localization and accessibility audit

Baseline: `a84e475`, 2026-11-04. Tracking: issue #12.

## Evidence and limits

This is a static SwiftUI/AppKit review plus automated resource checks, Swift
tests, and a release app-bundle build. No live application, VoiceOver session,
Accessibility Inspector, rendered contrast measurement, or keyboard traversal
was performed. A successful build is not accessibility acceptance.

Both EN/RU tables have 183 unique keys, no duplicate keys, and identical key
sets. All 94 directly written `model.t("…")` keys resolve in both tables.
This check does not establish coverage of dynamic keys or text bypassing
`model.t`. Existing localization tests exercise language choice and persistence.

## Narrow fix

`ProfilesView` previously suppressed its keyboard focus effect. Remove that
suppression so the native focus effect can appear. Add the selected trait to
the profile selection button, which previously expressed selection only through
color and a stripe. Add full-name help for names truncated to one line. Keep
the existing selection, scrolling, shortcuts, and edit action unchanged.

These are standard view modifiers; no tests that merely repeat the modifier
declarations were added. Their actual assistive-technology behavior still needs
the manual checks below.

## Findings routed to other owners

- **G, ProfilesView connection action:** `allowsHitTesting(false)` does not
  disable the Connect button semantically, and a Return shortcut remains.
  G owns honest disabled-state gating and shortcut removal or its integrated
  equivalent. K does not change connection or installation controls.
- **H, EditorView routing:** empty control labels on the enabled toggle,
  type/action pickers, and destination field provide no explicit names.
  Use localized control names and distinguish row context. Actual table-header
  announcement behavior is unverified.
- **H, EditorView localization:** the initial form-editing issue bypasses
  translation; dynamic model error messages lack translation keys. `Domain`
  also bypasses the selected-language lookup. Preserve serialized enum values
  when translating display text. Coordinate new keys before changing catalogs.
- **H, editor tabs:** the selected tab uses an underline without an explicit
  selected accessibility trait.
- **H, ConfigTextEditor:** the native NSTextView has no explicit localized AX
  label; verify propagation from SwiftUI or set the native label.
- **J, Settings diagnostics action:** source colors `#287BFF` on white compute
  to approximately 3.91:1 contrast for ordinary text, below 4.5:1. This is a
  calculation, not a rendered measurement. Prefer accessible text styling in
  the owned section rather than a global palette rewrite.
- **J, log timestamps:** `Date.formatted` uses the current locale rather than
  the app-selected language. Clarify presentation/export policy before changes.

The palette already selects native dark-mode background colors. No rendered
light/dark acceptance is claimed. Fixed Add sheet width, routing columns,
Settings action rows, and minimum-window profile actions need clipping checks;
source constraints alone do not prove visible clipping.

## Manual regression checklist (not run)

Repeat in RU/EN and light/dark modes at the 720-by-600 minimum main-window size
and a larger window. Include long profile names, empty/one/many profiles,
Increase Contrast, and Keyboard Navigation enabled.

1. Tab and Shift-Tab among sidebar, profile area, row actions, and footer.
   Confirm a visible focus indicator, including when selection is cleared.
2. Use arrows to select profiles, Shift-arrows to reorder, Space to edit, and
   Escape to clear selection. Confirm scrolling follows selection. Verify
   focused action buttons still activate normally and sheets retain their own
   Enter/Escape handling.
3. With VoiceOver, select profiles using row activation and arrows. Confirm
   the selected state updates, the complete profile name is available, and
   the separate Edit action remains reachable. Hover a truncated name and
   verify full-name help.
4. Confirm unavailable Connect is announced as disabled and Return cannot
   activate it after G's separate change. Verify disabled Remove for no
   selection, disabled settings placeholders, and empty-log export/clear.
5. Inspect long RU text and errors in Add, SSH fields, routing rows, Settings,
   and the profile footer for truncation or unreachable actions. Verify native
   Raw editing has an accessible name and readable syntax colors in both modes.
6. Verify routing controls and selected editor tabs with VoiceOver after H's
   separate fixes. Open unsupported-routing and ambiguous-ShadowTLS profiles
   in RU to check dynamic errors rather than only literal-key coverage.
