#!/bin/sh

# Standalone installer for Openwalla internet blocking support.
# Installs the firewall helper used for device pause/block actions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla internet blocking support"

require_file "$FILES_DIR/openwalla-paternal-pause.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

ensure_openwalla_config
ensure_uci_section features ui

install_file "$FILES_DIR/openwalla-paternal-pause.sh" /usr/bin/openwalla-paternal-pause 0755
install_rpcd_acl

set_uci openwalla.features.quarantine "1"
uci commit openwalla

PATERNAL_PAUSE_MARKER="# OPENWALLA_PATERNAL_PAUSE"
CRON_PATH="/etc/crontabs/root"
TMP_CRON="/tmp/openwalla/.openwalla_paternal_pause_cron.$$"
if [ -f "$CRON_PATH" ]; then
	grep -v "$PATERNAL_PAUSE_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
else
	: >"$TMP_CRON"
fi
echo "* * * * * mkdir -p /tmp/openwalla; /usr/bin/openwalla-paternal-pause apply >/tmp/openwalla/openwalla-paternal-pause.last.log 2>&1 $PATERNAL_PAUSE_MARKER" >>"$TMP_CRON"
cp "$TMP_CRON" "$CRON_PATH"
rm -f "$TMP_CRON"
reload_cron

log "Internet blocking support installed."
