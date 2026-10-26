# Continuous Netify Flows

- Remove the 2000-row display cap on Network and Device Flows.
- Initially load up to 2000 rows, then load another 2000 near the bottom.
  Retain sequential 250-row requests to limit router response sizes.
- Preserve filters, search, pull-to-refresh and lazy row rendering. Stop on
  an incomplete page rather than relying on a potentially stale summary count.
- Guard overlapping batches and ignore results from replaced filter/refresh
  generations. Offer retry on thrown pagination errors without clearing rows.
- Keep the existing offset-based backend API. Concurrent database insertions or
  retention deletions can still shift offsets; snapshot/cursor pagination is
  outside this UI change. Backend empty-on-error responses remain indistinguishable
  from end of history.
- Version 1.0.552+454. No router script changes or APK build.
- Verification: three focused widget tests pass (4250-row traversal and end,
  retry at the same offset, and stale-response isolation on filter change).
  Targeted analyzer and diff checks are clean. No physical router test performed.
