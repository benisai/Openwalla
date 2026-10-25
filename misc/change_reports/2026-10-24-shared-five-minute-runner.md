# Shared Five-Minute Runner

## Changes
- Deploy and register `Openwalla-5min-run.sh` alongside the one-minute and hourly
  runners in device collector and quarantine installs, including Basic Install.
- Component updates backfill the runner for device collector installations as
  well as Netify-only installations.
- Removing Netify no longer removes the shared runner or its cron entry.
- Netify maintenance logs a skip and returns successfully when Netify is absent.
  Existing enabled/external mode checks and restart order are unchanged.
- Router script version: 2026.10.24.4. No app UI changes or APK build.

## Verification
- Watchdog tests cover missing Netify, shared deployment references, uninstall
  preservation, cron idempotency, memory thresholds, and service recovery order.
- Shell syntax and Dart analyzer checks; no physical-router deployment performed.

## Deployment
Rerun Basic Install or use Router Components > Verify & Update.
