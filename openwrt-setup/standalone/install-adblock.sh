#!/bin/sh

# Standalone installer for Openwalla AdBlock support.
# Installs OpenWrt adblock packages and enables the app feature/config entries.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt AdBlock support"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"
require_file "$FILES_DIR/Openwalla-5min-run.sh"
require_file "$FILES_DIR/Openwalla-1min-run.sh"
require_file "$FILES_DIR/openwalla-adblock-reports.sh"
require_file "$FILES_DIR/openwalla-adblock-reports.awk"
require_file "$FILES_DIR/openwalla-adblock-reports.init"

update_package_feeds
install_pkg_if_available "adblock"
install_pkg_if_available "luci-app-adblock"
install_first_available_pkg "SQLite CLI" sqlite3-cli sqlite3 || exit 1

report_enabled="$(uci -q get openwalla.adblock_reports.enabled || uci -q get adblock.global.adb_report || echo 0)"
case "$report_enabled" in 0|1) ;; *) report_enabled=0;; esac
ensure_openwalla_config
ensure_uci_section features ui
ensure_uci_section adblock_reports adblock_reports
set_uci openwalla.adblock_reports.enabled "$report_enabled"
set_uci_default openwalla.adblock_reports.db_path /tmp/openwalla/openwalla-adblock.sqlite
set_uci_default openwalla.adblock_reports.retention_hours 24
set_uci_default openwalla.adblock_reports.retention_rows 10000
install_rpcd_acl
install_file "$FILES_DIR/openwalla-adblock-reports.sh" /usr/bin/openwalla-adblock-reports 0755
install_file "$FILES_DIR/openwalla-adblock-reports.awk" /usr/libexec/openwalla-adblock-reports.awk 0644
install_file "$FILES_DIR/openwalla-adblock-reports.init" /etc/init.d/openwalla-adblock-reports 0755
install_file "$FILES_DIR/Openwalla-5min-run.sh" /usr/bin/Openwalla-5min-run.sh 0755
install_file "$FILES_DIR/Openwalla-1min-run.sh" /usr/bin/Openwalla-1min-run.sh 0755
/usr/bin/Openwalla-5min-run.sh install-cron || exit 1
/usr/bin/Openwalla-1min-run.sh install-cron || exit 1

uci -q get adblock.global >/dev/null 2>&1 || uci set adblock.global="adblock"
set_uci openwalla.features.adblock "1"
set_uci adblock.global.adb_enabled "1"
set_uci adblock.global.adb_trigger "wan"
set_uci adblock.global.adb_report "0"
uci commit openwalla
uci commit adblock

enable_restart_service adblock
/usr/bin/openwalla-adblock-reports init-db || exit 1
/usr/bin/openwalla-adblock-reports configure "$(uci -q get openwalla.adblock_reports.enabled)" || exit 1
# Retire only Openwalla's old report cache, not other tcpdump users.
rm -f /tmp/openwalla/adblock-report.json
rm -rf /tmp/openwalla/adblock-report

log "AdBlock support installed."
