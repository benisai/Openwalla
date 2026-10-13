#!/bin/sh

# Standalone installer for the Openwalla network monitor.
# Installs latency, outage, and physical Ethernet link monitoring.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla network monitor"

require_file "$FILES_DIR/openwalla-network-monitor.sh"
require_file "$FILES_DIR/openwalla-network-monitor.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

ensure_openwalla_config
ensure_uci_section ping_monitor ping

install_file "$FILES_DIR/openwalla-network-monitor.sh" /usr/bin/openwalla-network-monitor 0755
install_file "$FILES_DIR/openwalla-network-monitor.init" /etc/init.d/openwalla-network-monitor 0755
install_rpcd_acl

set_uci_default openwalla.ping_monitor.enabled "1"
set_uci_default openwalla.ping_monitor.target "1.1.1.1"
set_uci_default openwalla.ping_monitor.interval "60"
set_uci_default openwalla.ping_monitor.threshold "100"
set_uci_default openwalla.ping_monitor.warning_percent "95"
set_uci_default openwalla.ping_monitor.timeout "2"
set_uci_default openwalla.ping_monitor.output_file "/tmp/openwalla/openwalla-ping-monitor.txt"
set_uci_default openwalla.ping_monitor.max_lines "2000"
set_uci_default openwalla.ping_monitor.state_file "/tmp/openwalla/openwalla-network-monitor.state"
set_uci_default openwalla.ping_monitor.outage_failures "2"
set_uci_default openwalla.ping_monitor.restore_successes "2"
set_uci_default openwalla.ping_monitor.alert_cooldown "1800"
set_uci_default openwalla.ping_monitor.interface_state_file "/tmp/openwalla/openwalla-interface-monitor.state"
set_uci_default openwalla.ping_monitor.wireguard_state_file "/tmp/openwalla/openwalla-wireguard-monitor.state"
set_uci_default openwalla.ping_monitor.wireguard_active_window "180"
uci commit openwalla

/usr/bin/openwalla-network-monitor --once || true
enable_restart_service openwalla-network-monitor

log "Network monitor installed."
