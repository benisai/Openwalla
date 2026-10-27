# Background Login Cache Saves

- Remove awaited optional saves from the dashboard/login completion path:
  ping history, performance settings, dashboard JSON and secure Wi-Fi sharing.
- Live results and dashboard completion no longer wait for these persistence
  futures. Saves start in the background; they are not a second router fetch.
- Preserve the existing JSON write queue, atomic replacement, router UUID and
  fingerprint scoping, secret filtering and secure Wi-Fi storage. Each save
  captures the router and payload before returning to its caller.
- Background save errors are handled and logged. Newly fetched data remains
  visible; if the app is terminated before persistence finishes, the previous
  completed cache may be used on the next launch.
- Failed-read fallback and snapshot restoration wait for already queued JSON
  writes so they use the latest completed live result, not an older snapshot.
  Successful live reads still do not wait for persistence.
- Keep startup cache restoration, authentication, fingerprint verification and
  live dashboard fetching unchanged. No batching or new cache architecture.
- Version 1.0.555+457. No router deployment or APK build.
- Four new regression tests pass with deliberately blocked/failing saves,
  including live ping/settings, dashboard completion and router switching.
- Verification: all 33 focused background-save, JSON cache, secure Wi-Fi and
  offline-state tests pass. Targeted analyzer and diff checks are clean.
  No physical-device startup timing measurement performed.
