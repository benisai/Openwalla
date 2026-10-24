# Remove Notifications Delete All

- Reverted the network-event preservation SQL and removed its specific tests.
- Removed the Delete All menu entry, confirmation dialog, and UI handler.
- Archive All and individual archiving remain unchanged. Archived events remain
  available to Network Performance Recent Events.
- Existing AppState deletion API is restored to its prior behavior; the
  notifications screen no longer calls it.
- No existing notification records or router scripts were modified.
- App version: 1.0.539+441.

Verification: existing notification tests passed; static analysis and diff
whitespace checks passed. No APK built or physical-device test performed.
