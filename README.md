# Bimeron for macOS

The initial SwiftUI interface supports adding access keys, importing `.conf`
files, editing and deleting profiles, appearance settings, an action log, and a
macOS menu bar menu. The connection screen reports the integration status;
VPN controls will be implemented in the next stage.

On the Profiles page, Cmd+Z undoes the last deletion and Cmd+Shift+Z redoes it.
Deletion history lasts until the app quits. Shift+Up/Down moves the selected
profile by one row. Profile order is stored in `order.json` alongside profiles
and restored on launch.

## Profile editor

The editor follows the access-source contract in
[bimeron-core at 6af5d72](https://github.com/bimeron/bimeron-core/tree/6af5d72bd7e1e98461e78f437509a1994f395fab/docs/CONF.MD)
(October 30, 2026). Adding a key, clipboard suggestions, and `.conf` imports
recognize Shadowsocks/SSConf, SOCKS5, HTTP/HTTPS CONNECT, MASQUE, VLESS, VMess,
Trojan, NaiveProxy HTTP/2 and HTTP/3, Hysteria2 (including `hy2://`), AnyTLS,
SSH, and TUIC v5. These are editable profile formats; this app does not yet
connect through them.

When a supported link is entered, the profile name appears above the link. SSH
links also reveal an optional private-key file picker below it; only the file
path is stored in the profile, not the private-key contents.

The Protocol tab edits complete links without decoding and rewriting their
parameters. This preserves encoded VMess JSON, QUIC options, and extended
XHTTP settings. Access links and passwords are masked by default. Imported
explicit configurations expose fields for their protocol, including Shadowsocks
plugins, VLESS and Trojan transports, MASQUE CA certificates, and SSH identity
and `known_hosts` files. Optional ShadowTLS v3 settings have their own section.
Other fields and comments remain available in Raw config and survive form edits.

SSH and MASQUE file references are saved as absolute paths during import;
private-key and CA-file contents are not copied into profiles. SSH URI file
options are preserved in the link and given absolute `.conf` overrides. The
referenced files must remain available. Choosing proxy mode removes VPN-only
IPv6 and kill-switch settings. macOS does not support a core kill switch or
per-application routing. Domain rules depend on core-observed DNS and do not
cover every DoH, cached-DNS, or direct-IP connection.

Local checks cover profile structure, source/scheme consistency, and basic
network fields. They do not establish URI parameter validity, credential validity,
transport compatibility, file accessibility by a future service, or connectivity.
The tests exercise 23 public core example profiles, complete-link round trips,
file-backed imports, file relocation, and the existing profile-library behavior.

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
