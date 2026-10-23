# Detached Router Installation Jobs

## Outcome

Installation runs on the router independently of the phone's SSH session. The
app starts a job, then uses short-lived SSH requests to read status and new log
bytes. Phone sleep or a lost monitoring connection does not cancel the worker.
No package-installation logic was duplicated or rewritten.

## Shared Coverage

- Welcome/core setup and all individual feature installs through
  `installOpenwallaSetupFeatures`.
- Router Setup profiles, Custom Install, and component removals.
- Router Components updates (status-only checks remain ordinary SSH calls).
- Package manager update/install/remove actions.
- Every standalone installer through the common helper's opt-in
  `--background` argument, including the compatibility DNS wrapper.
- Direct Router Setup CLI with `--background` as the first argument.
- Short maintenance commands and the ACL recovery installer are unchanged.

## Router Worker

- Shared source: `openwrt-setup/files/openwalla-install-job.sh`.
- The app bundles and uploads the wrapper; no prior helper installation or
  custom RPC ACL is needed to start an SSH installation.
- Each job owns `/tmp/openwalla/install/<job-id>/command.sh`, `install.log`,
  `status.json`, process metadata, and a private copy of the worker script.
- All input/output descriptors are redirected and SIGHUP is ignored. No
  optional BusyBox nohup applet, service, or persistent daemon is required.
- Status is written atomically with the actual shell exit code. States are
  `starting`, `running`, `completed`, `failed`, and `interrupted`.
- A shared lock rejects concurrent wrapped jobs. Reusing a job ID resumes it;
  it never reruns that job, including after completion.
- Status checks detect dead workers, account for Linux PID reuse, and keep the
  lock while an orphaned installer process is still alive.
- Per-job lock ownership avoids a stale reader deleting another job's lock.
- Log polling returns at most 64 KiB per request, using byte offsets and base64
  framing. The app preserves UTF-8 characters across chunks.

## App Monitoring

- `RouterInstallService` handles launch, polling, reconnection, and results.
- A pending job ID and command are stored in secure storage scoped to the
  router UUID before submission. Lost launch replies retry that same ID.
- The app polls every three seconds and retries monitoring transport failures.
  After its retry budget, it retains the job identity for later reconnection.
- After closing/reopening the app, repeat the same installer selection to
  resume its saved job. Automatic navigation/reopening of the installer UI was
  not added. A running older selection cannot be replaced by another selection.
- Completion depends on status plus exit code, not log text. Existing feature
  checks and dashboard configuration still happen after a successful result.
- Optional SSH execution timeouts bound installer monitoring requests and
  close their connections; ordinary SSH callers retain their previous defaults.

## Files Changed

- Added the shared router worker and `lib/services/router_install_service.dart`.
- Updated installer routing in `lib/state/app_state.dart`,
  `lib/screens/router_setup_screen.dart`, and
  `lib/screens/router_components_screen.dart`.
- Added optional execution timeouts in `lib/services/ssh_service.dart` and
  updated the ACL service test double to match that optional parameter.
- Added CLI opt-in handling in `openwrt-setup/setup-openwrt-router.sh` and
  `openwrt-setup/standalone/lib/openwalla-standalone-common.sh`.
- Added shell integration and app-service regression tests.
- Updated README installation guidance, standalone documentation, asset
  registration, and versions.

## Verification and Limits

- Full Flutter suite: 202 tests passed; Flutter analysis: no issues.
- Shell syntax and Git whitespace checks passed.
- Integration tests exercise actual detached shell processes and temporary
  files, including hangup survival, duplicate launches, concurrent rejection,
  dead supervisors, real exit status, argument quoting, bounded log reads, and
  both CLI entry points. App tests cover launch-reply loss, reconnection,
  persisted job identity, changed selections, reboot/missing state, and UTF-8.
- Tests run locally, not against a physical OpenWrt router or real SSH daemon.
  Router testing should include locking the phone during a package install.
- Router reboot clears `/tmp` job records and interrupts installation. Missing
  state is reported without automatically rerunning package commands.
- Existing Router Setup timestamped logs in `/root/openwalla/install-logs/`
  remain intact. Standalone job logs remain temporary and last until reboot or
  manual cleanup. Job-directory retention cleanup was not added.
- Foreground CLI installs remain available for compatibility; do not run one
  alongside a wrapped background job. These cannot share the wrapper's lock.
- App version: `1.0.528+430`; scripts: `2026.10.22.2`. No APK was built.
