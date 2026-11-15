# Protection-Dependent Panels

## Changes

- Geo-Blocking shows Blocked Countries and Router Status only while protection is enabled.
- Quarantine shows the Quarantined Devices heading, count, list, or empty state only while automatic quarantine is enabled.
- Existing control panels remain accessible for re-enabling protection. Hiding content does not clear selected countries or device records.
- Failed disable requests retain the enabled sections, using the existing confirmed-state behavior.
- Version: `1.0.576+478`.

## Scope and Verification

- Two screens, a focused widget-test file, version, and this report only.
- No backend, firewall, router-script, or installer changes.
- 22 focused tests passed, including initial disabled states, disable/re-enable transitions, retained selections/device data, failed updates, existing Geo-Blocking helpers, and dashboard quarantine banner regressions.
- Static analysis and diff whitespace checks passed.
- No APK built or live-router settings changed. Existing user APK changes were left untouched.
