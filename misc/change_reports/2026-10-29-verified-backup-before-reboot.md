# Verified Backup Before Reboot

- Found three fail-open paths: reboot swallowed backup exceptions, the app did
  not validate helper exit status, and the helper silently ignored copy failures.
  SQLite failures could also fall back to a raw DB copy that omitted WAL data.
- Normal app reboot now requires the updated helper's save-for-reboot action,
  exit code zero and explicit OPENWALLA_STATE_SAVED acknowledgement before sending
  the reboot RPC. Allow five minutes for the backup RPC; timeouts cancel reboot.
- Verify SQLite online backups (sqlite3 or sqlite3-cli) with quick_check and
  publish them via per-file rename. Never fall back to copying a live database.
- Apply the same SQLite-safe handling to vnStat databases and exclude WAL/shared
  memory sidecars from those checkpoints; retain legacy non-SQLite usage files.
- Propagate required backup/copy failures; publish the save timestamp only after
  all selected saves succeed, then flush filesystem writes before acknowledging.
  Refuse known volatile /tmp and /var backup destinations. Each database is
  replaced atomically; this is not a single multi-database transaction.
- Countdown shows backup progress and the cancellation reason. Failed reboot
  attempts resume polling. Factory-reset behavior deliberately remains separate.
- Bind reboot to the router/session that was backed up; a changed session or
  router selection while waiting cancels the command rather than rebooting a
  different target. Invalidate older dashboard/recovery requests before backup.
- State Sync installer ensures SQLite CLI availability and refuses to restart
  (which restores state) if its initial checkpoint fails.
- Deployment: update the app AND reinstall/update State Sync on the router.
  Older/missing helpers cannot satisfy the new protocol, so app reboot is blocked
  rather than risking data. Other reboot methods outside the app are unchanged.
- Version 1.0.558+460. No APK build or physical-router reboot performed.
- Verification: 16 focused reboot/checkpoint tests and 24 background-save/offline
  regression tests passed. Includes a real SQLite WAL writer, corruption/copy
  failures, acknowledgement/exit-status checks and session-change cancellation.
  Targeted Dart analyzer, shell syntax and diff checks are clean.
