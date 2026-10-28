# Devices And Notifications Preload

- After successful login, warm the Devices and Notifications page reads without
  awaiting them. Honor the saved single-router/aggregate Devices preference.
- Share in-progress requests and completed results in a small memory-only cache
  with a 15-second freshness window. Scope entries by router UUID/fingerprint,
  online/offline mode and aggregate router membership.
- Pages display existing preload data immediately, including empty device lists,
  while stale data refreshes quietly. Pull-to-refresh bypasses the freshness window.
- Preloading reads notifications only; marking seen and badge refresh happen when
  the Notifications page opens. Display the list before those operations finish.
- Invalidate shared results on logout/login, notification archive operations,
  device access changes and Devices-page identity/removal actions. Generation
  checks prevent old screen reads from undoing local notification/device edits.
- Retain existing disk snapshots, discovery logic and firewall source of truth.
  No additional periodic polling, disk-cache architecture or router scripts.
- Version 1.0.556+458. No APK build or physical-router timing verification.
- Verification: 42 focused preload, Devices/Notifications widget, background-save,
  offline-state and notification-model tests pass; targeted analyzer and diff
  checks are clean. Includes pending-request reuse, freshness/forced refresh,
  invalidation, router isolation and no mark-seen operation during warmup.
