#!/bin/sh

# Standalone installer for the Openwalla DNS monitor.
# Installs and enables the router-side DNS resolution sampler.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla DNS monitor"

require_file "$FILES_DIR/openwalla-dns-monitor.sh"
require_file "$FILES_DIR/openwalla-dns-monitor.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

ensure_openwalla_config
ensure_uci_section dns_monitor dns

install_file "$FILES_DIR/openwalla-dns-monitor.sh" /usr/bin/openwalla-dns-monitor 0755
install_file "$FILES_DIR/openwalla-dns-monitor.init" /etc/init.d/openwalla-dns-monitor 0755
install_rpcd_acl

set_uci_default openwalla.dns_monitor.enabled "1"
set_uci_default openwalla.dns_monitor.target "openwrt.org"
set_uci_default openwalla.dns_monitor.interval "60"
set_uci_default openwalla.dns_monitor.threshold "1000"
set_uci_default openwalla.dns_monitor.timeout "3"
set_uci_default openwalla.dns_monitor.output_file "/tmp/openwalla/openwalla-dns-monitor.txt"
set_uci_default openwalla.dns_monitor.max_lines "2000"
uci commit openwalla

/usr/bin/openwalla-dns-monitor --once || true
enable_restart_service openwalla-dns-monitor

log "DNS monitor installed."
