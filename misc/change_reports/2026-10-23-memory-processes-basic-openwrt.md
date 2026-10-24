# Memory Processes on Basic OpenWrt

## Cause

The memory snapshot command used `sort -t "|" -k1,1nr`. Those flags require
BusyBox FEATURE_SORT_BIG, disabled by default in OpenWrt. With minimal sort,
the pipeline produces no rows; the app displays No process memory data. CPU
uses a separate top-based command and does not depend on these sort options.
This is a confirmed command compatibility defect; the exact firmware on the
user's router has not been inspected directly.

Official references:

- https://github.com/openwrt/openwrt/blob/openwrt-25.12/package/utils/busybox/Config-defaults.in
- https://github.com/mirror/busybox/blob/master/coreutils/sort.c

## Fix and Scope

- Replace field-based sorting with `sort -nr`, supported by minimal BusyBox.
  RSS is already the first integer on each line, so descending numeric order
  is preserved without -k or -t.
- Extract the existing command into AppState.buildProcessMemoryCommand to
  exercise the actual command in regression tests. Keep the 1-25 row limit.
- App version 1.0.536+438. No installer, RPC permissions, router scripts,
  packages, CPU processing, memory parser, or UI layout changes.
- Existing installations need the updated app, not another router install.

## Verification

- Four command tests run real shell pipelines against mock proc fixtures,
  with a sort shim rejecting extended options. The old command reproduces
  empty output; the fixed command ranks RSS, preserves arguments, handles
  kernel-thread fallback names, and respects limits.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built. Actual minimal-BusyBox/physical-router verification remains.
