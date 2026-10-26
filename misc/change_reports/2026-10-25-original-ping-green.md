# Restore Original Ping Green

- Verified the version before `47131ae` used `#20CF70` for green ping status,
  matching the current dashboard CPU gauge.
- Replace the pale mint `#86EFAC` with that original green in the shared ping
  palette, affecting both timelines and Ping Test bars.
- Preserve the latest band order, dark green, configured thresholds, and all
  yellow/red/gray states. No dashboard layout or router changes.
- Update color and rendered-bar expectations. App version 1.0.549+451.
- No APK built.
- All 20 focused tests, targeted static analysis, and diff checks passed.
