# Stable Offline Fallback

- Separate explicit Offline browsing from automatic connection-loss fallback.
  Explicit Offline remains read-only and does not reconnect itself.
- Dashboard errors retain available data without declaring the router offline.
  Only transport/timeouts trigger a bounded three-second system.board probe;
  only confirmed connection loss enables the global read-only guard.
- Retry confirmed/intermittent connection failures every ten seconds while
  authenticated. A successful probe re-enables live reads and refreshes the
  dashboard. Normal refresh can recover too; cancel retries on success,
  logout, session replacement, explicit Offline entry and disposal.
- Share in-progress dashboard fetches and recovery operations. Generation checks
  reject outdated fetch/restore results after logout or a new session.
- Treat router display-name persistence as optional, not a connection failure.
  Pause telemetry reads during confirmed loss and ignore late telemetry results.
- Preserve panel-specific saved-data warnings without making them read-only.
  The dashboard banner distinguishes saved panels from confirmed offline status.
- Keep authentication, router identity checks, disk cache format and per-router
  scoping unchanged. No router scripts changed or APK built.
- Version 1.0.557+459. No physical-device connection-loss test performed.
- Verification: 48 focused connection-recovery, background-save, offline-state,
  preload, Devices/Notifications UI and notification-model tests pass. Includes
  a real timer-driven recovery test, request deduplication, ordinary-refresh
  recovery and late-failure-after-logout isolation.
- Targeted analyzer and diff checks are clean.
