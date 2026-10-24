# Router Hostname, Timezone, and Wi-Fi Button Color

## Changes

- Edit Wi-Fi now uses light blue (#64B5F6), replacing pink. No Wi-Fi save or
  reload behavior changed.
- Added Change Hostname and Timezone rows to the existing Manage Device list.
- Hostname loads from the router's actual UCI system section, validates input,
  writes only hostname, and updates the app's known router hostname after the
  router confirms saving.
- Timezone has a searchable router-provided list. Both the human-readable
  zonename and matching POSIX timezone string are saved together, preserving
  the router's daylight-saving rules. UTC has an explicit UTC0 fallback.
- Uses native UCI set/apply/readback, without shell interpolation or new
  packages. Router configuration is authoritative; errors are not success.
- Loading, retry, unchanged/disabled Save, saving, and standard toast states
  are included. Back navigation is blocked while saving.

## Official LuCI Reference

https://github.com/openwrt/luci/blob/openwrt-25.12/modules/luci-mod-system/htdocs/luci-static/resources/view/system/system.js

LuCI loads timezone options with `luci.getTimezones`. Its timezone write
handler saves `system.<section>.zonename` and the selected entry's `tzstring`
as `system.<section>.timezone`. Hostname uses that same system section's
`hostname` option. Openwalla follows these fields and uses rpcd UCI apply to
commit and trigger configuration reloads, followed by configuration readback.

## Files

- `lib/screens/interfaces_screen.dart`: button color only.
- `lib/screens/manage_device_screen.dart`: two new navigation rows.
- `lib/screens/router_system_settings_screen.dart`: hostname/timezone editors.
- `lib/services/router_system_settings_service.dart`: UCI validation and saves.
- `lib/state/app_state.dart`: selected-router transport and hostname refresh.
- `openwrt-setup/rpcd-acl.json`: system read and timezone-list permissions,
  plus UCI apply and changes permissions needed by native apply/removal.
- `pubspec.yaml`: app 1.0.533+435.
- `pub_script_version.yaml`: published router assets 2026.10.23.1.
- Focused service, screen, and bundled ACL tests.

Existing routers using a restricted Openwalla ACL need its updated version
installed and a fresh login for the added permissions. No broad wildcard
permission was introduced.

## Verification

- 21 focused tests passed, including timezone mapping, UTC, invalid names,
  rejected calls, missing sections, readback mismatch, management navigation,
  and timezone filtering/selection at a 360 x 640 logical-pixel viewport.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built. Runtime hostname/timezone changes have not been tested on a
  physical router.
