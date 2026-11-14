# AdBlock Reports

## Request

Add a Reports switch to AdBlock and open a searchable page when enabled, reading JSON cached on the router.

## Behavior

- Reports is opt-in and saves immediately. Tap its row while enabled to open AdBlock Reports.
- The page displays the generated timestamp, captured time range, query totals, NXDOMAIN count, and up to 1,000 recent query records.
- Search matches domains, client addresses, dates/times, DNS types, interfaces, and result labels. Search runs locally; refresh reads cached JSON only.
- Missing cache shows a waiting state; connection/permission/format failures show an error. Failed refreshes retain the already displayed report.
- JSON is stored at `/tmp/openwalla/adblock-report.json`; raw AdBlock reporting files stay under `/tmp/openwalla/adblock-report/`.
- The shared five-minute runner generates native reports and atomically publishes timestamped JSON. It works independently of whether Netify is installed or healthy.
- Generation is limited to 90 seconds and lower priority when `nice` is available. JSON retrieval is limited to 15 seconds. The existing runner lock prevents overlapping runs.
- Generation skips when one-minute load exceeds the detected CPU core count or available memory is below 16 MB. Failed/skipped work preserves the previous cache and its original timestamp.
- Capture uses AdBlock's five-file, 1 MB-per-file ring, DNS port 53, reverse lookups disabled, and GeoIP disabled. Existing reporting interface selection is preserved; otherwise native LAN detection applies. Temporary report processing uses additional space beyond the capture ring.
- Existing AdBlock save operations now check RPC/command failures, using standard `file.exec` RPC rather than relying on `system.exec`.

## Deployment

Re-run the AdBlock installer once on an existing router, through Router Setup or standalone installation. It deploys the updated five-minute runner/cron entry and ACL, and installs `tcpdump-mini` (fallback: `tcpdump`) if no capture binary exists. Reporting is not enabled by installation alone.

Then enable Reports in AdBlock. The switch checks the capture binary, timeout/jsonfilter utilities, updated runner, and cron registration before enabling. Block Ads must be enabled for capture and report generation. The first report arrives on a subsequent five-minute run once DNS traffic has been collected, subject to resource checks.

The ACL grants read access only to the published JSON path. No new SQLite storage, network uploads, or permanent report history was added. `/tmp` contents disappear on reboot. Rolling reports overlap, so their totals must not be summed into historical usage.

NXDOMAIN is not proof that AdBlock blocked an advertisement; the UI uses the DNS result label instead of claiming exact ad-block counts. Encrypted DNS bypassing the router's ordinary DNS is outside port-53 capture.

## Scope

- AdBlock screen and new reports screen/model
- AdBlock methods in `lib/state/app_state.dart`
- Shared five-minute runner, AdBlock installer, and explicit ACL file-read permission
- Focused tests, version `1.0.571+473`, and this report

## Verification

- 43 focused tests passed: report parsing/search, UI navigation/switches/error states, RPC behavior, scheduler generation/skips/failures/locking, ACL, and existing Netify watchdog regressions.
- Changed Dart files passed static analysis.
- Shell syntax checks passed for the runner and installer.
- Rendered and visually inspected the report page; narrow-screen/large-text widget tests passed.
- No APK built; no live-router settings changed. Actual capture behavior, generation duration, and CPU usage still require testing on the target router.

## Upstream References

- [LuCI DNS reports](https://github.com/openwrt/luci/blob/master/applications/luci-app-adblock/htdocs/luci-static/resources/view/adblock/dnsreport.js)
- [AdBlock report implementation](https://github.com/openwrt/packages/blob/master/net/adblock/files/adblock.sh)
- [OpenWrt 24.10 implementation](https://github.com/openwrt/packages/blob/openwrt-24.10/net/adblock/files/adblock.sh)
- [AdBlock configuration documentation](https://github.com/openwrt/packages/blob/master/net/adblock/README.md)
