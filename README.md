# Bimeron for macOS

The initial SwiftUI interface supports adding access keys, importing `.conf`
files, editing and deleting profiles, appearance settings, an action log, and a
macOS menu bar menu. The connection screen reports the integration status;
VPN controls will be implemented in the next stage.

On the Profiles page, Cmd+Z undoes the last deletion and Cmd+Shift+Z redoes it.
Deletion history lasts until the app quits. Shift+Up/Down moves the selected
profile by one row. Profile order is stored in `order.json` alongside profiles
and restored on launch.

## Build and run

Requires macOS 14 or later and Xcode with Swift 6. Tested with Xcode 16.4.

```sh
swift test
sh scripts/build-app.sh
open dist/Bimeron.app
```

For development, use `swift run Bimeron`. Profiles are stored as `.conf` files
with owner-only permissions in
`~/Library/Application Support/Bimeron/Profiles/`. Importing leaves the original
file unchanged. If a configuration references a separate key file, its contents
are embedded into the imported profile copy.

This version validates configuration structure and essential fields locally.
Final validation by the core, VPN connections, traffic statistics, system
notifications, and automatic connections require integration with `bimeron-core`.
The core working directory is adjacent to this project; this local build does
not pass profiles or secrets to it.
