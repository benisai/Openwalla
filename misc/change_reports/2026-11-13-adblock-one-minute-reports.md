# One-Minute AdBlock Reports and Automatic Refresh

## Request

Investigate the waiting report page, generate reports every minute, and clarify whether JSON should be appended.

## Findings

- The report page previously read its cache only on entry or manual refresh. Its waiting state did not automatically update when a report arrived later.
- A missing JSON cache is distinct from a file-read permission failure. Waiting alone does not identify why no cache was published on the physical router.
- Native report snapshots overlap, so appending them would duplicate queries and totals. The existing bounded latest-snapshot JSON format remains unchanged; no permanent history was added.

## Changes

- Moved report generation from the five-minute runner to the one-minute runner. Netify maintenance stays on its existing five-minute schedule.
- Added a report-specific overlap lock. A ping failure does not prevent report generation.
- Reduced generation/retrieval timeouts to 45 and 10 seconds. Existing low-priority and high-load/low-memory safeguards remain; a busy router may skip a scheduled attempt.
- The one-minute job writes `/tmp/openwalla/adblock-report.last.log`, including disabled/missing dependency states, resource skips, empty/invalid native JSON, and bounded native error output.
- Recreates the configured capture directory. If no capture files exist (for example after reboot), requests AdBlock reload to start capture, then waits for a later run to generate the report.
- Added a manual `Openwalla-1min-run.sh report-adblock` diagnostic action.
- The open report page rereads cached JSON every minute, only while its route is current and the app is foregrounded. It never generates reports from the UI, retains search state, and cancels polling on disposal.
- AdBlock installation deploys both updated runners and registers minute cron. The app's readiness check now verifies the minute runner and cron entry.
- Version: `1.0.573+475`.

## Deployment and Diagnosis

Re-run AdBlock installation once to deploy both updated runners (including removal of the old five-minute generation call). Ensure Block Ads and Reports are enabled.

The cache remains `/tmp/openwalla/adblock-report.json` and is replaced atomically, not appended. The first report can require another run after capture starts and DNS traffic is observed.

Read `/tmp/openwalla/adblock-report.last.log` for the latest router-side outcome, or run `/usr/bin/Openwalla-1min-run.sh report-adblock` for direct output. The exact cause of the user's missing cache is not confirmed without these router diagnostics.

## Scope and Verification

- AdBlock report page and readiness check; one-/five-minute runners; AdBlock installer; focused tests; version and this report.
- Existing user APK changes were not staged or modified.
- Maintenance/report tests and report-page/AdBlock UI tests passed, including reboot-directory recovery, cached-page auto-refresh, locks, diagnostics, and existing ping/Netify behavior.
- Static analysis, shell syntax, and whitespace checks passed.
- No APK built or physical-router changes performed. Real router capture and timing still need verification.
