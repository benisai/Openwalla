#!/bin/sh

# Standalone installer for the Openwalla devices collector.
# Installs sqlite/nlbwmon support and registers the device inventory service.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla devices collector"

require_file "$FILES_DIR/openwalla-devices-collector.sh"
require_file "$FILES_DIR/openwalla-device-access.sh"
require_file "$FILES_DIR/openwalla-devices-collector.init"
require_file "$FILES_DIR/openwalla-device-quarantine.hotplug"
require_file "$FILES_DIR/oui/openwalla-mac-vendors.txt"
require_file "$FILES_DIR/Openwalla-1hr-run.sh"
require_file "$FILES_DIR/Openwalla-1min-run.sh"
require_file "$FILES_DIR/openwalla-devices-ping.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3
install_pkg_if_available "nlbwmon"
install_pkg_if_available "conntrack"

ensure_openwalla_config
ensure_uci_section devices devices

install_file "$FILES_DIR/openwalla-devices-collector.sh" /usr/bin/openwalla-devices-collector 0755
install_file "$FILES_DIR/openwalla-device-access.sh" /usr/lib/openwalla/device-access.sh 0644
install_file "$FILES_DIR/openwalla-devices-collector.init" /etc/init.d/openwalla-devices-collector 0755
install_file "$FILES_DIR/openwalla-device-quarantine.hotplug" /etc/hotplug.d/dhcp/95-openwalla-quarantine 0755
install_file "$FILES_DIR/openwalla-device-quarantine.hotplug" /etc/hotplug.d/neigh/95-openwalla-quarantine 0755
install_file "$FILES_DIR/oui/openwalla-mac-vendors.txt" /usr/share/openwalla/openwalla-mac-vendors.txt 0644
install_file "$FILES_DIR/Openwalla-1hr-run.sh" /usr/bin/Openwalla-1hr-run.sh 0755
install_file "$FILES_DIR/Openwalla-1min-run.sh" /usr/bin/Openwalla-1min-run.sh 0755
install_file "$FILES_DIR/openwalla-devices-ping.sh" /usr/bin/openwalla-devices-ping 0755
install_rpcd_acl

set_uci_default openwalla.devices.enabled "1"
set_uci_default openwalla.devices.db_path "/tmp/openwalla/openwalla-devices.sqlite"
set_uci openwalla.devices.poll_seconds "60"
set_uci_default openwalla.devices.offline_after_seconds "90"
uci commit openwalla

/usr/bin/openwalla-devices-collector --init-db || true
/usr/bin/openwalla-devices-collector --once || true
/usr/bin/Openwalla-1hr-run.sh install-cron || true
/usr/bin/Openwalla-1min-run.sh install-cron || true
/usr/bin/Openwalla-1hr-run.sh run || true

if ! have_cmd sqlite3 && ! have_cmd sqlite3-cli; then
	log "WARNING: sqlite3/sqlite3-cli not found; devices collector and UI sqlite queries will fail."
fi
if ! have_cmd nlbw; then
	log "WARNING: nlbw command not found; devices collector will still inventory devices but traffic totals will stay at 0."
fi

enable_restart_service openwalla-devices-collector

log "Devices collector installed."
