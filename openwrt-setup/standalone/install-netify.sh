#!/bin/sh

# Standalone installer for Openwalla Detailed Flow support.
# Installs Netify dependencies and registers the Netify SQLite collector service.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla Netify support"

require_file "$FILES_DIR/openwalla-netify-collector.sh"
require_file "$FILES_DIR/openwalla-netify-collector.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "netifyd"
install_first_available_pkg "netcat" netcat netcat-openbsd
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3

ensure_openwalla_config
ensure_uci_section collector netify
ensure_uci_section flow_stats flow_stats
ensure_uci_section features ui

install_file "$FILES_DIR/openwalla-netify-collector.sh" /usr/bin/openwalla-netify-collector 0755
install_file "$FILES_DIR/openwalla-netify-collector.init" /etc/init.d/openwalla-netify-collector 0755
install_rpcd_acl

set_uci openwalla.features.netify "1"
set_uci openwalla.collector.enabled "1"
set_uci openwalla.collector.host "127.0.0.1"
set_uci openwalla.collector.port "7150"
set_uci openwalla.collector.db_path "/tmp/openwalla-netify.sqlite"
set_uci openwalla.collector.retention_rows "500000"
set_uci_default openwalla.collector.retention_hours "24"
set_uci openwalla.collector.stream_timeout "45"
set_uci openwalla.collector.exclude_protocols "MDNS,DNS,QUIC,DHCPv6,ICMP"
set_uci openwalla.collector.ignore_wan_source "1"
set_uci_default openwalla.flow_stats.enabled "0"
set_uci_default openwalla.flow_stats.db_path "/tmp/openwalla-netify-flow-stats.sqlite"
set_uci_default openwalla.flow_stats.poll "5"
set_uci_default openwalla.flow_stats.bucket_seconds "300"
set_uci_default openwalla.flow_stats.retention_seconds "2592000"
uci commit openwalla

NETIFYD_CONF="/etc/netifyd.conf"
if [ -f "$NETIFYD_CONF" ]; then
	if grep -q "^listen_address\[0\]" "$NETIFYD_CONF"; then
		sed -i "s|^listen_address\[0\].*|listen_address[0] = 127.0.0.1|" "$NETIFYD_CONF"
	else
		grep -q "^\[socket\]" "$NETIFYD_CONF" || echo "[socket]" >>"$NETIFYD_CONF"
		sed -i "/^\[socket\]/a listen_address[0] = 127.0.0.1" "$NETIFYD_CONF"
	fi
	log "Updated netifyd listen_address[0] to 127.0.0.1"
fi

/usr/bin/openwalla-netify-collector --init-db || true
/usr/bin/openwalla-netify-collector --install-prune-cron || true

if ! have_cmd nc; then
	log "WARNING: nc command not found; netify collector will not ingest flows."
fi
if ! have_cmd sqlite3 && ! have_cmd sqlite3-cli; then
	log "WARNING: sqlite3/sqlite3-cli not found; netify collector and UI sqlite queries will fail."
fi

enable_restart_service netifyd
enable_restart_service openwalla-netify-collector

log "Netify support installed."
