#!/bin/sh

# Standalone installer for the Openwalla speedtest monitor.
# Installs a speedtest binary and configures scheduled speed test sampling.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla speedtest monitor"

require_file "$FILES_DIR/openwalla-speedtest-monitor.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "speedtest" speedtestcpp python3-speedtest-cli

ensure_openwalla_config
ensure_uci_section speedtest_monitor speedtest

install_file "$FILES_DIR/openwalla-speedtest-monitor.sh" /usr/bin/openwalla-speedtest-monitor 0755
install_rpcd_acl

set_uci_default openwalla.speedtest_monitor.enabled "1"
uci -q delete openwalla.speedtest_monitor.run_date >/dev/null 2>&1 || true
set_uci_default openwalla.speedtest_monitor.run_hour "3"
set_uci_default openwalla.speedtest_monitor.run_minute "15"
set_uci_default openwalla.speedtest_monitor.bin "/usr/bin/speedtest"
set_uci_default openwalla.speedtest_monitor.output_file "/tmp/openwalla/openwalla-speedtest-monitor.txt"
set_uci_default openwalla.speedtest_monitor.max_lines "365"
uci commit openwalla

/usr/bin/openwalla-speedtest-monitor --init-file || true

SPEEDTEST_MARKER="# OPENWALLA_SPEEDTEST_MONITOR"
CRON_PATH="/etc/crontabs/root"
TMP_CRON="/tmp/openwalla/.openwalla_speedtest_cron.$$"
HOUR="$(uci -q get openwalla.speedtest_monitor.run_hour 2>/dev/null || echo 3)"
MINUTE="$(uci -q get openwalla.speedtest_monitor.run_minute 2>/dev/null || echo 15)"
ENABLED="$(uci -q get openwalla.speedtest_monitor.enabled 2>/dev/null || echo 1)"
case "$HOUR" in ''|*[!0-9]*) HOUR=3 ;; esac
case "$MINUTE" in ''|*[!0-9]*) MINUTE=15 ;; esac
if [ "$HOUR" -gt 23 ]; then HOUR=3; fi
if [ "$MINUTE" -gt 59 ]; then MINUTE=15; fi
if [ -f "$CRON_PATH" ]; then
	grep -v "$SPEEDTEST_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
else
	: >"$TMP_CRON"
fi
if [ "$ENABLED" = "1" ]; then
	echo "$MINUTE $HOUR * * * mkdir -p /tmp/openwalla; /usr/bin/openwalla-speedtest-monitor --scheduled >/tmp/openwalla/openwalla-speedtest-monitor.last.log 2>&1 $SPEEDTEST_MARKER" >>"$TMP_CRON"
fi
cp "$TMP_CRON" "$CRON_PATH"
rm -f "$TMP_CRON"
reload_cron

log "Speedtest monitor installed."
