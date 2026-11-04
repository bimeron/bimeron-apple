# Implement the standalone Core CLI foundation (workstream B)

The app needs typed access to Core's local inspection and configuration validation commands before editor integration can be designed. Add an independent BimeronCoreCLI SwiftPM target with no app dependency, shell invocation, networking, daemon ownership, or configuration writes.

Acceptance:
- Decode `version` and static `capabilities` using the verified v0.3.0-beta.2 contract.
- Pass an existing configuration path as one argument to `validate`; leave original and draft placement to the caller.
- Drain both output streams concurrently with bounded retained bytes; expose truncation and preserve diagnostics on failure.
- Bound timeout and cancellation cleanup, including SIGTERM-resistant children.
- Verify launch, exit, decode, argument preservation, high output, timeout, cancellation, and unchanged input with local fixtures.
- Run the existing test and release build checks locally; record limits without claiming live Core acceptance or hosted CI execution.

Architecture agreed before implementation: Core owns routes, DNS, and cleanup. CLI capability declarations cannot establish runtime or daemon readiness. No UI or document integration belongs to this workstream.
