# Statistics presentation

`StatisticsView(snapshot:translate:locale:)` accepts an explicit optional value snapshot of
`ConnectionStatistics`, the existing application translation closure, and an explicit
locale. Profiles passes `Locale(identifier: model.language)` so byte totals, rates,
and elapsed values follow the selected app language rather than the system locale. Profiles
currently injects `nil`: unavailable traffic replaces the previous fabricated zero.
There is no live adapter, polling, activation, or AppModel statistics state.

The caller must independently confirm the association between statistics and daemon
instance/session identity before calling `confirm`. Before injecting each snapshot,
the caller must advance the model using elapsed time from the same monotonic origin,
including idle periods, and publish updates when current data expires. The view does
not advance time or introduce stale thresholds. See the connection-statistics caller
contract for generation tokens, event drops, and resynchronization requirements.

Current totals require a confirmed token, no pending resync, and `latest`. Rates also
require connected status. Missing values remain unavailable; valid zero is retained.
History is the model's bounded retained evidence, including explicit unavailable
counter/rate gaps. It is never used as a fallback for current values. Elapsed values
refer to the caller's monotonic origin, not session duration or wall time. Historical
rates remain historical evidence after current observations become unavailable.

The disclosure contains a height-limited history list and is collapsed initially.
Labels identify upload/download totals and bytes-per-second rates without relying
on color or directional glyphs.

## Validation

`StatisticsPresentationTests` uses synthetic in-memory observations only. It covers
missing/unconfirmed snapshots, fresh zero, fractional rates and elapsed time,
staleness, dropped-event resync, bounded gaps, disconnected retained totals, and
English/Russian byte, rate-number, and elapsed formatting.

Parent validation before the locale correction passed all four presentation tests.
The added locale regression and correction await parent validation.

Parent validation command (not run by the implementation child):

```sh
swift test --skip-update --jobs 2 --filter StatisticsPresentationTests
```

No GUI, live daemon, network, or VPN acceptance is claimed.
