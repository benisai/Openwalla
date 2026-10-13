#!/bin/sh

# Standalone installer for Openwalla Simple Flow support.
# Installs sqlite support and the conntrack-based flow collector service.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla connection flow support"

require_file "$FILES_DIR/openwalla-connection-flow-collector.sh"
require_file "$FILES_DIR/openwalla-connection-flows-collector.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3

ensure_openwalla_config
ensure_uci_section connection_flows connection_flows

install_file "$FILES_DIR/openwalla-connection-flow-collector.sh" /usr/bin/openwalla-connection-flow-collector 0755
install_file "$FILES_DIR/openwalla-connection-flows-collector.init" /etc/init.d/openwalla-connection-flows-collector 0755
install_rpcd_acl

set_uci openwalla.connection_flows.enabled "1"
set_uci openwalla.connection_flows.db_path "/tmp/openwalla/openwalla-connection-flows.sqlite"
set_uci openwalla.connection_flows.poll_seconds "15"
set_uci openwalla.connection_flows.retention_rows "50000"
set_uci openwalla.connection_flows.exclude_endpoints "127.0.0.1"
set_uci openwalla.connection_flows.ignore_ipv6 "1"
set_uci openwalla.connection_flows.lan_to_wan_only "0"
uci commit openwalla

/usr/bin/openwalla-connection-flow-collector --init-db || true
enable_restart_service openwalla-connection-flows-collector

log "Connection flow support installed."
