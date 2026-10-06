#!/bin/sh

# Standalone installer for Openwalla banIP support.
# Installs OpenWrt banIP packages and enables the app feature/config entries.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt banIP support"

if command -v geoip-shell >/dev/null 2>&1; then
	log "Removing the previous geoip-shell country blocker"
	geoip-shell off >/dev/null 2>&1 || true
	remove_pkg_if_installed "geoip-shell"
	remove_pkg_if_installed "geoip-shell-iptables"
fi

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "banip"
install_pkg_if_available "luci-app-banip"

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl

set_uci openwalla.features.banip "1"
uci commit openwalla

set_uci banip.global.ban_countrysplit "1"
uci commit banip

enable_restart_service banip

log "banIP support installed."
