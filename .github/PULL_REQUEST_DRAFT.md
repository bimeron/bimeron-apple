# feat: expand profile editor for current core protocols

Fixes #1.

The profile editor previously rejected current core access links, including
Trojan in the add dialog, and exposed VLESS-only transport controls. Adding,
clipboard detection, import, labeling, and editing now share the current access
source/scheme catalog. Complete links retain their encoded settings, while
explicit profiles expose protocol-specific fields for Shadowsocks plugins,
VLESS/Trojan transports, HTTP(S), MASQUE, NaiveProxy, and SSH. Optional ShadowTLS
settings and SSH/CA file pickers are available in the Protocol tab. The add
dialog offers optional known_hosts and private-key file pickers for SSH, with
known_hosts above the private key.

Import converts referenced local file paths to absolute paths without copying
private keys or rewriting SSH URI bytes. Form edits preserve unknown fields,
comments, and routing rules. Switching to local proxy removes incompatible
VPN-only options. English/Russian help explains TCP-only upstreams, DNS rule
limits, and the distinction between saving a profile and validating it in core.

Validation:
- `swift test`: 22 tests pass, including import/edit/reload of 23 public examples
  from bimeron-core 6af5d72, URI and key-file preservation, path relocation,
  source/scheme mismatch rejection, and localization.
- `sh scripts/build-app.sh`: release app bundle builds successfully.
- Native offscreen snapshots checked for the add dialog and representative
  Trojan, VLESS, Hysteria2, MASQUE, and SSH forms using placeholder-only profiles.
- `git diff --check` and localization plist validation pass.

The existing macOS CI workflow runs the tests, release build, and bundle check.
Hosted CI has not run for this local branch; no push is included in this work.
NetworkExtension, daemon IPC, connections, full core validation, updates, and
SSH authentication prompts remain outside this change. Link parameters are
edited as complete links; advanced settings remain available in Raw config.
