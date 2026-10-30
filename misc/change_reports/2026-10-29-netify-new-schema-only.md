# New-Schema-Only Router Netify Storage

- Version: 1.0.563+465.
- Per request after resetting the router, removed the legacy JSON-table migration and app reader fallback. This supersedes the compatibility/deployment guidance in the earlier column-storage report.
- Fresh initialization creates only the column-based `flow_raw` table. The app queries those columns directly, with JSON used only for transport encoding.
- A minimal initialization check rejects incompatible tables with a clear log message. No history is automatically converted, dropped, or reset.
- Removed migration-only tests and fixtures. Retained fresh creation/reinitialization, flow-field preservation, optional-value handling, compaction, unsupported-schema failure, protocol filtering, accounting, and pagination coverage.
- HTTP/HTTP-S default filtering, explicit compaction, and external-server behavior remain unchanged. No reboot/backup changes.

## Verification

- 23 focused tests passed across column storage, protocol filtering, accounting, page transport, and pagination.
- Focused analyzer passed; both edited shell scripts passed `sh -n`; `git diff --check` passed.
- No APK built or live-router changes made. Install the updated app and router collector on the reset router; no migration step is needed.
