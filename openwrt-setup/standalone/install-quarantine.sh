#!/bin/sh

# Standalone installer for Openwalla device quarantine.
# Enables quarantine policy in the shared devices collector service.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla device quarantine"

require_file "$FILES_DIR/openwalla-devices-collector.sh"
require_file "$FILES_DIR/openwalla-devices-collector.init"
require_file "$FILES_DIR/openwalla-device-quarantine.hotplug"
require_file "$FILES_DIR/oui/openwalla-mac-vendors.txt"
require_file "$FILES_DIR/Openwalla-1hr-run.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3

ensure_openwalla_config
ensure_uci_section devices devices
ensure_uci_section quarantine quarantine
ensure_uci_section features ui

install_file "$FILES_DIR/openwalla-devices-collector.sh" /usr/bin/openwalla-devices-collector 0755
install_file "$FILES_DIR/openwalla-devices-collector.init" /etc/init.d/openwalla-devices-collector 0755
install_file "$FILES_DIR/oui/openwalla-mac-vendors.txt" /usr/share/openwalla/openwalla-mac-vendors.txt 0644
install_file "$FILES_DIR/Openwalla-1hr-run.sh" /usr/bin/Openwalla-1hr-run.sh 0755
install_file "$FILES_DIR/openwalla-device-quarantine.hotplug" /etc/hotplug.d/dhcp/95-openwalla-quarantine 0755
install_file "$FILES_DIR/openwalla-device-quarantine.hotplug" /etc/hotplug.d/neigh/95-openwalla-quarantine 0755
install_rpcd_acl

set_uci_default openwalla.quarantine.enabled "0"
set_uci_default openwalla.quarantine.interval "15"
set_uci_default openwalla.quarantine.leases_file "/tmp/dhcp.leases"
set_uci_default openwalla.quarantine.state_file "/tmp/openwalla-quarantine-known.txt"
set_uci_default openwalla.quarantine.rule_prefix "openwalla_quarantine_"
set_uci_default openwalla.devices.enabled "1"
set_uci_default openwalla.devices.db_path "/tmp/openwalla-devices.sqlite"
set_uci openwalla.devices.poll_seconds "60"
set_uci openwalla.features.quarantine "1"
uci commit openwalla

/usr/bin/openwalla-devices-collector --init-db || true
/usr/bin/openwalla-devices-collector --once || true
/usr/bin/Openwalla-1hr-run.sh install-cron || true
/usr/bin/Openwalla-1hr-run.sh run || true

enable_restart_service openwalla-devices-collector

log "Device quarantine installed."
