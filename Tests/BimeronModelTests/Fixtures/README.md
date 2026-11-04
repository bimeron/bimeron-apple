# Core profile compatibility fixtures

The CoreProfiles configurations are public, placeholder-only examples copied from
[bimeron-core at 6af5d72](https://github.com/bimeron/bimeron-core/tree/6af5d72bd7e1e98461e78f437509a1994f395fab/examples)
(2026-10-30, MIT). No real access credentials are included.

File-backed profiles are tested with temporary local key files instead of copying
examples that depend on untracked profiles. The Windows-only IKEv2 backend is
outside this macOS packet-profile editor. VMess URI preservation is tested with
an encoded example generated in the test.

These fixtures verify the editor's import/save contract, not protocol negotiation
or complete core validation. Recheck them when adopting a newer core revision.
