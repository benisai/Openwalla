# Preserve Network Events During Delete All

Superseded: preservation logic was reverted at the user's request. Delete All
was removed from the notifications menu instead. See
`2026-10-23-remove-notifications-delete-all.md`.

## Request and Source

Network Performance Recent Events fetches notifications, including archived
records, and filters using OpenwallaNotification.isNetworkPerformanceEvent.
The expanded Recent Events page uses the same predicate. Protected categories
are network_health, interface, dns, and speedtest.

## Changes

- Delete All soft-deletes only notifications outside those categories.
- Share the category set with the existing Recent Events predicate. SQL follows
  its explicit-category precedence and legacy ping/network-monitor/interface/
  Ethernet-message inference. Category matching normalizes ASCII whitespace
  and case, including older rows with blank category values.
- Inspect the notifications table schema before updating, supporting older
  databases without category. Fail without deleting if required columns cannot
  be verified. Require the SQL completion marker before reporting completion.
- Operate directly on all database rows, not a capped page of loaded records.
- Preserve active/archived status of protected events. Do not restore records
  already deleted before this update.
- Update the confirmation to explain that Network Performance history is kept,
  and show a standard error toast if deletion cannot complete.
- App version 1.0.538+440. Router assets and database schema are unchanged.

## Files

- `lib/state/app_state.dart`: category set, SQL policy, bulk-delete operation.
- `lib/screens/notifications_screen.dart`: confirmation and error handling.
- `test/notification_bulk_delete_test.dart`: real SQLite policy regression tests.
- `pubspec.yaml`: version.

## Verification

- 15 focused tests passed (bulk deletion and existing notification behavior).
- Tested current and legacy schemas, active and archived rows, legacy inferred
  categories, explicit overrides, repeated deletion, pre-deleted network rows,
  category case/whitespace, and more than 500 notifications.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-router test performed.
