# Focused Netify Flow Accounting Improvements

## Scope and Provenance

Borrowed the connection-lifecycle approach from m0g13r/luci-app-traffic-chart,
trafficchart-agg at commit 127c82c3b87c8dec0c53b07032ee1a74059f84d5
(GPL-2.0-or-later). Integration is written for Openwalla's existing SQLite
collector; no upstream daemon or shaper code is installed.

Source: https://github.com/m0g13r/luci-app-traffic-chart/blob/127c82c3b87c8dec0c53b07032ee1a74059f84d5/luci-app-traffic-chart/files/usr/libexec/trafficchart-agg

## Changes

- First successful sample after collector startup establishes baselines rather
  than replaying existing connections into historical totals.
- Newly observed connections after startup include their initial byte counters.
- Counter resets and closing-to-active TCP tuple reuse count the new connection
  and discard the prior tuple's cached application/destination labels.
- Like the reference, a 1 GiB heuristic treats huge newly observed flows as
  baselines, and large backwards counters conservatively retain positive
  deltas rather than replaying full history. This is a heuristic, not perfect
  connection identity.
- Add TCP state to the existing flow_stats_state table with an additive,
  idempotent migration. Existing history/totals remain intact.
- Failed raw conntrack reads and failed SQLite state/writes do not advance the
  startup baseline. SQL update transactions use bail-on-error.
- Router asset version: 2026.10.24.2. No Flutter app version bump.

## Intentionally Unchanged

UI, nlbwmon device totals, Netify raw-flow collection, Openwalla-Server,
IPv6 accounting, inbound-flow accounting, delayed labels, polling interval,
and existing five-minute missing-state retention. Flows entirely between polls
can still be missed; very long absences and UDP tuple identity remain imperfect.
These are deferred to keep this change small and token usage bounded.

## Verification

Seven real shell/SQLite tests exercise startup/new-flow accounting, growth,
temporary absence, counter resets/stale labels, TCP tuple reuse, huge-flow
baseline handling, failed reads, and migration with retained history.
Shell syntax and diff whitespace checks passed. No APK built and no physical
router benchmark performed. Update installed router components to deploy.
