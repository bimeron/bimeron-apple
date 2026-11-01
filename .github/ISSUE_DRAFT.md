# feat: add initial SwiftUI profile management UI

Create a native macOS Bimeron interface with persistent profile creation,
import, editing and deletion, plus appearance settings, log and menu bar.
Match the supplied desktop references while keeping native macOS controls.

The agreed first milestone manages profiles without a VPN connection. Its
connection controls must state that integration is pending. Core validation
and daemon RPC are follow-up work.

Acceptance: `swift test` and app bundle build pass; private profile storage,
failed import rollback, lossless raw edits and routing order are covered.
