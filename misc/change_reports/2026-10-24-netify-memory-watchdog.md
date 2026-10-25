# Netify Memory Watchdog

## Scope
- Added `Openwalla-5min-run.sh`, installed by the Netify installer and component updater.
- Added matching uninstall cleanup and bumped router components to 2026.10.24.3.
- No Flutter UI changes or APK build.

## Behavior
- Runs every five minutes; output replaces `/tmp/openwalla/openwalla-5min-run.last.log`.
- Reads resident memory (RSS) from `/proc`, including each service's child processes.
- Restarts when either service exceeds 25% of total router RAM, not system-wide RAM usage.
- Optional UCI override: `openwalla.collector.memory_limit_percent` (1-100, default 25).
- Obtains service process IDs from procd via ubus/jsonfilter; does not depend on top or pgrep.
- Stops the local collector, restarts Netify, then starts the collector only if restart succeeded.
- Recovers missing Netify or a missing local collector. Skips disabled Netify services.
- Honors collector enabled/external settings, so external mode never starts the local collector.
- Uses a lock against overlapping runs. A reboot clears the runtime lock.
- Restarting the collector rebaselines flow counters; traffic during recovery may not be counted.

## Verification
- Shell syntax checks and focused mocked-service tests cover memory limits, child memory,
  dependency order, missing processes, external/disabled modes, restart failure, and cron idempotency.
- No physical-router memory-pressure test performed.

## Deployment
Run Router Components > Verify & Update, or rerun the Netify standalone installer.
