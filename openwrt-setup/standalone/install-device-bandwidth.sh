#!/bin/sh

# Standalone installer for Openwalla per-device bandwidth support.
# Installs sqlite/nlbwmon tooling plus the bandwidth collector and summary helper.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla device bandwidth collector"

require_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh"
require_file "$FILES_DIR/openwalla-device-traffic-summary.sh"
require_file "$FILES_DIR/openwalla-device-bandwidth-collector.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3
install_pkg_if_available "conntrack"

ensure_openwalla_config
ensure_uci_section device_bandwidth device_bandwidth

install_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh" /usr/bin/openwalla-device-bandwidth-collector 0755
install_file "$FILES_DIR/openwalla-device-traffic-summary.sh" /usr/bin/openwalla-device-traffic-summary 0755
install_file "$FILES_DIR/openwalla-device-bandwidth-collector.init" /etc/init.d/openwalla-device-bandwidth-collector 0755
install_rpcd_acl

set_uci_default openwalla.device_bandwidth.enabled "1"
set_uci_default openwalla.device_bandwidth.db_path "/tmp/openwalla/openwalla-device-bandwidth.sqlite"
set_uci_default openwalla.device_bandwidth.poll_seconds "60"
set_uci_default openwalla.device_bandwidth.bucket_seconds "900"
set_uci_default openwalla.device_bandwidth.retention_seconds "86400"
uci commit openwalla

/usr/bin/openwalla-device-bandwidth-collector --init-db || true
/usr/bin/openwalla-device-bandwidth-collector --once || true
enable_restart_service openwalla-device-bandwidth-collector

log "Device bandwidth collector installed."
