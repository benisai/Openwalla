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

update_package_feeds
install_pkg_if_available "adblock"
install_pkg_if_available "luci-app-adblock"
if ! command -v tcpdump >/dev/null 2>&1; then
	install_pkg_if_available "tcpdump-mini" || install_pkg_if_available "tcpdump" || \
		log "DNS reporting requires tcpdump-mini or tcpdump; reports will remain unavailable."
fi

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl
install_file "$FILES_DIR/Openwalla-5min-run.sh" /usr/bin/Openwalla-5min-run.sh 0755
install_file "$FILES_DIR/Openwalla-1min-run.sh" /usr/bin/Openwalla-1min-run.sh 0755
/usr/bin/Openwalla-5min-run.sh install-cron || exit 1
/usr/bin/Openwalla-1min-run.sh install-cron || exit 1

uci -q get adblock.global >/dev/null 2>&1 || uci set adblock.global="adblock"
set_uci openwalla.features.adblock "1"
set_uci adblock.global.adb_enabled "1"
set_uci adblock.global.adb_trigger "wan"
uci commit openwalla
uci commit adblock

enable_restart_service adblock

log "AdBlock support installed."
