# Installer Compatibility Without Base64

## Bug

The detached installer assumed the router had a `base64` executable. Some
standard OpenWrt images omit it, so uploading the bundled job wrapper failed
before installation could start. Log polling depended on the same command.

## Changes

- `lib/services/router_install_service.dart`: upload the wrapper through a
  quoted shell heredoc with write-failure and nonempty-file checks, rather
  than base64 decoding. Shell variables in the wrapper remain literal.
- `openwrt-setup/files/openwalla-install-job.sh`: return plain log text after
  the JSON status header, with offsets measured in complete lines. Polling
  reads at most 200 complete lines at a time and defers partial final lines.
- The app counts received lines rather than bytes. Unicode, indentation,
  backslashes, blank lines, and carriage returns remain text, with no external
  encoder/decoder dependency. A single unusually long log line can exceed the
  previous 64 KiB chunk size; the limit is now 200 lines, not a byte limit.
- Resuming a saved job upgrades the shared status reader before polling it;
  the job's private worker and installer process are not restarted.
- The shared fix covers Router Setup, feature installs, removals, component
  updates, package actions, and standalone background installs. No firewall,
  device discovery, or unrelated UI changes.
- Updated protocol tests and standalone documentation. The earlier detached-job
  report describes the original byte/base64 protocol; this report supersedes it.

## Verification

- Full Flutter suite: 204 tests passed. Flutter analysis, shell syntax, and
  Git whitespace checks passed.
- Regression coverage runs the actual generated app bootstrap and detached
  worker while a fake `base64` executable always fails with exit 127. Both a
  fresh installation and resuming a job through an outdated reader complete
  without ever invoking it.
- Coverage also checks line pagination, partial-line writes, Unicode, whitespace,
  reconnection, duplicate-job prevention, and missing jobs after reboot.
- App version: `1.0.529+431`; script version: `2026.10.22.3`.
- No APK built; physical-router verification remains necessary. Deploy a new
  app build to get the corrected upload code. Installing base64 is not required.
