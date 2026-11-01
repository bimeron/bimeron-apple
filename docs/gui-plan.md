# Bimeron macOS interface plan

## Visual style

The mark, application icon, and interface colors come from Bimeron Brand Kit v1.
The menu bar uses a template mark when disconnected from the core. Its visible
size follows the approved `PIXEL-PROOF-1X.png` reference. Check actual scale and
contrast on a Mac with light and dark menu bars before release.

References include Windows GUI screenshots, the RouteLine example, and
`bimeron-desktop` documentation at revision
`67658368c2342ec95547cd0f0579a9d5aca28128`. The adjacent `bimeron-core` was
reviewed at revision `cfe0cc537c0c8310e402f2994eb47c7375024a75`.

## First stage: interface and profiles

The native SwiftUI window contains Profiles, Settings, Log, and About pages.
Profiles can be added by key, imported from `.conf`, edited in five sections,
and deleted. Appearance settings take effect immediately. The log records local
actions and can be exported or cleared. Profiles are stored as local `.conf`
files with owner-only permissions. Importing embeds separately referenced key
file contents in the profile copy.

Connection controls and VPN settings are disabled with an explanation. Local
actions must not be presented as a running core connection. This stage does not
validate configurations through the core: local validation covers size, syntax,
and essential fields. Raw configuration text remains available to preserve
parameters that the form does not expose.

## Next stage: connections

After building and testing `bimeron-core` on macOS, add a daemon RPC v1 client
using `/var/run/bimeron/control.sock`. Run the daemon under an appropriate user
with the necessary privileges; the GUI must not run as root. Display only
confirmed core state, including errors, reconnection, and unknown active
profiles. Validate the final `.conf` through the core before saving. Then test
actual connection, stop, profile switching, sleep, and network recovery flows.
NetworkExtension and system extension signing remain a separate architecture
decision.

## Validation

`swift test` covers persistence, failure rollback, permissions, imports,
preservation of unknown fields, and routing rule order. `sh scripts/build-app.sh`
builds a runnable `.app`. Visual acceptance requires checks at minimum window
size, on Retina displays, in light and dark themes, with empty and populated
profile lists. Capture current interface screenshots during visual acceptance;
connection and error screenshots will be needed when integrating the core.
