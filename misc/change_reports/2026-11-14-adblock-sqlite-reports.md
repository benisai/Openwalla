# AdBlock SQLite Reports

## Changes

- Keep OpenWrt AdBlock as the feed/blocking engine. Replace Openwalla's rotating tcpdump/JSON report pipeline with an optional shell/awk dnsmasq collector and SQLite history.
- Reports starts disabled for new installs. Update/reinstall AdBlock in Router Setup to deploy the helper, parser, procd service, SQLite dependency, and updated ACL. Both standalone and Router Setup use the same installer. Existing native reporting preference is carried over when updating.
- Database: `/tmp/openwalla/openwalla-adblock.sqlite`. No JSON report file; temporary FIFOs and identity snapshots are private and cleaned up on stop. Events contain timestamp, client IP/MAC/name, domain, query type, and matched AdBlock rule.
- Correlate dnsmasq serial/client/process before recording a local negative or zero-address response matched against AdBlock's effective compiled rules. Upstream/cached NXDOMAIN and unrelated local negatives are not labeled as confirmed blocks. Most-specific allowlist and Safe Search exceptions take precedence.
- Observe client ownership from live DHCP leases, DHCPACK logs, and IPv4/IPv6 neighbors. Device database names are joined by MAC, never by an old historical IP. Identity is saved with the event; later IP reuse does not rewrite history. Unknown clients retain their IP.
- One long-lived awk parser and SQLite writer; flush every five seconds or 100 writes. Query correlation is capped at 4,096 pending requests and expires after 30 seconds. Reload compiled policy only when its file signature changes; do not import all feed rules for every query.
- Retain the newest 10,000 events and at most 24 hours by default, pruning each minute. SQLite reuses freed pages. The active-policy index also consumes database space proportional to the enabled blocklists.
- Reports page searches domains/devices on the router and loads 200 rows per page using an ID cursor. Minute refresh reads SQLite only; it does not generate a report or start packet capture. Error refreshes retain visible rows; obsolete search responses cannot overwrite a newer search.
- Reports owns only the DNS logging preference it changes and restores its prior value when stopped. Disabling AdBlock stops collection but preserves the Reports preference. Uninstall stops the collector and restores logging before removing its files.
- State Sync includes this database when installed. Collector shutdown flushes before the State Sync shutdown backup. Without State Sync, `/tmp` history disappears on reboot. A hard power loss can lose uncommitted events.
- Removed only the old AdBlock report task from the one-minute runner; device ping and other maintenance remain unchanged. No Netify or blocking-engine changes.
- Version: `1.0.580+482`.

## Router Controls

```sh
uci set openwalla.adblock_reports.retention_hours='24'
uci set openwalla.adblock_reports.retention_rows='10000'
uci commit openwalla
/etc/init.d/openwalla-adblock-reports restart

/usr/bin/openwalla-adblock-reports configure 1  # enable (AdBlock must be enabled)
/usr/bin/openwalla-adblock-reports configure 0  # disable and restore DNS logging
/usr/bin/openwalla-adblock-reports query --search 'Pixel' --limit 20
```

## Scope and Verification

- Changed only AdBlock reporting model/API/page, its installer/config/ACL/component manifest/uninstall, removal of its old minute task, State Sync registration, focused tests, version and documentation.
- 60 focused AdBlock/ACL/maintenance tests and 23 installer regressions passed. Includes real SQLite/awk integration, IPv6, allowlist/Safe Search exceptions, upstream negatives, retained identity, quoting, cursor pagination, pruning, logging ownership, and shutdown cleanup/flush.
- Static analysis and shell/whitespace checks passed. No APK built and no live router configuration changed.
- First version supports dnsmasq using the system log only. Custom dnsmasq log files and other DNS backends are rejected when enabling; disabling remains available. Encrypted DNS bypassing dnsmasq is not visible. This is best-effort blocked-query history, not complete DNS or connection auditing: log overflow, cache answers and collector downtime can omit events. No original-feed attribution is claimed.
- Live OpenWrt validation and CPU measurements remain necessary. Suggested test: enable Reports, query a known blocked domain twice from a client, verify domain/device rows; query a nonexistent non-blocklisted domain and ensure it is absent; disable/re-enable Reports and reboot with State Sync installed to verify persistence.

## Upstream References

- [OpenWrt AdBlock implementation](https://github.com/openwrt/packages/blob/master/net/adblock/files/adblock.sh): effective dnsmasq rule directory, deny/allow and Safe Search formats.
- [OpenWrt dnsmasq init](https://github.com/openwrt/openwrt/blob/master/package/network/services/dnsmasq/files/dnsmasq.init): UCI `logqueries` enables `--log-queries=extra`; service uses a named per-instance PID file.
- [dnsmasq manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): extra logging adds serial/requester fields for correlation.
