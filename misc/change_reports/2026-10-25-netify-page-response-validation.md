# Netify Page Response Validation

- Found that flow fetch errors became empty lists and unparseable JSON rows
  were silently removed. The screen interpreted either as end of history.
  The exact failure on the user's router is not confirmed without live logs.
- Append a completion marker to router SQLite page queries so truncated output
  cannot masquerade as a complete short page, including truncation between rows.
- Retry incomplete or unreadable pages in smaller pieces down to one row;
  propagate persistent errors to the screen's retry/error state. Validate RPC
  command success for these queries without changing other SQLite callers.
- Propagate external server errors and malformed records instead of returning
  empty history. Continue using the existing offset API and its known limits
  when database inserts/deletions occur during paging.
- Show exact loaded and matching database counts in the flow footer.
- Version 1.0.553+455. No router deployment or APK build required/performed.
- Seven focused transport and screen tests pass, including truncated pages,
  true short/empty pages, command failures, corrupt JSON, continuous loading,
  retry offsets and stale filter responses. No physical router verification.
- Targeted analyzer and diff checks are clean.
