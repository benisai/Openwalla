# Port Forward Destination Picker and Immediate Toggle

## Request

Remove Advanced, allow manual or dropdown destination IP entry, and immediately save the port-forward switch.

## Changes

- Removed Advanced and its firewall zone discovery call. Existing custom source/destination zones remain unchanged; new rules default to WAN/LAN.
- Added a dropdown inside the destination field with Router and devices from the selected router's shared Devices loader. Duplicate/invalid addresses are excluded; entries show names and IPs.
- Choosing an address fills the editable field. Manual entry still works if discovery fails. Router addresses with a URL scheme or port are normalized when possible.
- Existing rule switches save only `enabled`/`disabled`, commit firewall configuration, and use the existing firewall apply path. Other unsaved edits stay pending.
- Pending operations lock controls; failures retain the previous switch position and show an error. Returning after a successful toggle requests a parent-list refresh, including when discarding other edits.
- For a new rule, toggling validates and saves the complete rule, then returns to the list. Invalid/incomplete forms are not submitted.
- Version: `1.0.569+471`.

## Scope

- `lib/screens/port_forward_screen.dart`
- `lib/state/app_state.dart` (port-forward enable operation only)
- Two existing port-forward test files
- `pubspec.yaml` and this report

## Verification

- 35 focused tests passed across port-forward UI/backend, firewall forwarding models, and interface visibility.
- Covered picker selection/manual editing, duplicate/invalid devices, discovery failures, custom-zone preservation, immediate toggle success/failure, pending operation locking, parent refresh, and new-rule validation.
- Static analysis passed for changed Dart files.
- Rendered and inspected the updated dark-theme screen; responsive tests cover light/dark themes at 320, 430, and 1200 widths with large text and keyboard insets.
- No APK built and no live router settings changed. Physical-router testing remains necessary.
