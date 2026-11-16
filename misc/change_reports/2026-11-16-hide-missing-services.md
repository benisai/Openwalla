# Hide Missing Services

- Services now lists only entries with `installed == true`. Missing helpers no longer appear as cards.
- Installed running, stopped and boot-disabled services remain visible and manageable. Existing detection, backend results and detail-screen safeguards are unchanged.
- Refresh applies the filter again, discovering newly installed services and removing services that were uninstalled. No installed services uses the existing empty state; loading errors retain the error state.
- Scope: Services list filtering, focused widget tests, version and report only. No router/helper/ACL changes or APK build. User-owned APK and attachment changes were left untouched.
- Version: `1.0.586+488`.
- Verification: seven focused Services list/status tests passed, plus static analysis and whitespace checks.
