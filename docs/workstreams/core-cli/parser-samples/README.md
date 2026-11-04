# Core parser sample provenance

`Tests/BimeronCoreCLITests/CoreParserSamples.swift` contains source-derived JSON
wire samples, not captured or live Core output. No Core executable was run.
Verified through the GitHub contents API on 2026-11-04: tag `v0.3.0-beta.2`
resolves to `66d84d8f4dcfc6ada625eb11894b19feea51b7ba`.

- [core/version.go](https://github.com/bimeron/bimeron-core/blob/66d84d8f4dcfc6ada625eb11894b19feea51b7ba/core/version.go): `BuildDetails` JSON fields and optional revision/commit_time. Version is a linker-set variable (source default `0.1.0-dev`); the selected release version, Go version and arm64 architecture are illustrative build values, not observed build metadata.
- [core/capabilities.go](https://github.com/bimeron/bimeron-core/blob/66d84d8f4dcfc6ada625eb11894b19feea51b7ba/core/capabilities.go): `PlatformCapabilities()` evaluated for darwin. All IKEv2 flags are false; only Windows sets them. macOS has VPN, proxy, IPv4, IPv6, IP split, domain split and daemon flags true, app split and kill switch false.

Negative parser tests mutate these samples: unknown version `0.0.0`, all-false
capability flags, and removal of required fields. All-false macOS capabilities
are an artificial negative input, not an upstream macOS capability claim.
Malformed/truncated tests use intentionally invalid bytes. Controlled shell
processes emit these samples to exercise the actual CoreCLI parsing boundary.
D's synthetic process-result text is never used as Core wire JSON.
