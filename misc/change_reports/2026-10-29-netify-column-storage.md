# Netify Router Flow Column Storage

## Scope

- Router Netify collector, its standalone installer, and the app's router flow reader.
- Version: 1.0.561+463. No changes to reboot, State Sync, retention schedules, or the external Openwalla Server database/API.

## Changes

- Removed stored `flow_raw.json` from the router schema. Added `local_port`, `first_seen_at`, `last_seen_at`, `downloaded_bytes`, `uploaded_bytes`, `total_bytes`, `country_code`, `region`, and `direction`.
- Existing history is backfilled before the old table is dropped, in a single SQLite transaction. IDs, AUTOINCREMENT high-water mark, risk/category metadata, and search indexes are retained. Invalid JSON, missing JSON support, or a SQL failure cancels migration rather than deleting history.
- Normalized display identity fields follow the app's existing hostname/application/protocol fallbacks. MAC arrays are reduced to a usable client MAC rather than a stringified list.
- New events retain only structured columns. Existing five-minute accounting remains separate and unchanged.
- The app detects the router table schema on each page request. Older router databases still use their original reader. New databases serialize selected columns as small JSON transport messages; raw JSON is not stored. Existing page completeness checks and pagination remain active.
- Standalone Netify installation stops the previous collector before initialization and reports migration failures instead of silently continuing.
- Added opt-in `--compact-db`: pauses a running collector, initializes/migrates the database, checkpoints WAL, runs VACUUM, and restarts the collector on exit. Compaction is not automatic at every startup and requires temporary free space.

## Deployment And Limitations

1. Install the updated app first. It supports both schemas.
2. Preserve an independent backup before updating the router collector. The migration permanently discards unused raw-payload fields; an old app/collector expecting `json` cannot use the new schema.
3. Update the router Netify component/installer and check `/tmp/openwalla/openwalla-netify-collector.log` for migration completion.
4. Schema replacement frees reusable pages but does not immediately shrink the file. With sufficient working space, run `/usr/bin/openwalla-netify-collector --compact-db` to reclaim file space. The command logs progress/errors to the collector log.

This does not establish or repair the separately reported State Sync backup failure. No physical router, installed database, or APK was changed by this development task.

## Verification

- SQLite integration coverage: legacy-reader compatibility, historical backfill, fresh inserts, repeated initialization, preserved display details and IDs, aliases/timestamp units, malformed-data rejection, transactional rollback, and compaction without row loss.
- 32 focused tests passed across column-storage integration, Netify accounting, page transport, pagination, and watchdog suites.
- Focused Flutter analyzer: no issues. Both edited shell scripts pass `sh -n`; `git diff --check` passes.
