# Dashboard Quarantine Banner

- Version: 1.0.565+467.
- Added a compact warning banner above dashboard content, below the router selector, with a count, Dismiss, and View Quarantined Devices actions.
- Counts unique MACs from the existing enabled-firewall-rule quarantine parser, not stale SQLite flags or notification records. Manual blocks/disabled rules do not count. Full dashboard fetches and the existing 10-second summary refresh update the banner.
- Dismiss acknowledges the current MACs for the app session, scoped by router UUID and fingerprint. It survives dashboard tab remounts, does not unblock devices, and new unacknowledged MACs bring the banner back. An observed rule removal allows a later re-quarantine to notify again. Logout clears acknowledgements.
- View opens the existing Quarantine page and refreshes summary status on return. Removing all quarantine rules hides the banner on the next successful refresh.
- Quarantine fields are included in dashboard snapshots for saved/offline viewing. Failed firewall reads preserve the last known status; a failed read cannot carry a different router's quarantine list into the current router. Summary results are discarded after a router/session change.
- Changes are scoped to dashboard presentation/state; quarantine enforcement and notification storage are unchanged.

## Verification

- Combined work with the Smart Queue update passed 59 focused tests: banner actions/dismissal/router isolation/remounts, enabled-rule deduplication, snapshot preservation, failed reads, offline/dashboard/firewall regression, and Smart Queue mapping/interactions.
- Banner layout checked at widths 320, 430, and 1200, at normal and 2x text scaling.
- Focused analyzer and `git diff --check` passed. No APK built or live-router changes made.
