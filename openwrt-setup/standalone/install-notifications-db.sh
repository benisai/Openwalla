#!/bin/sh

# Standalone installer for the Openwalla notifications database.
# Installs sqlite support and initializes the router-side notification store.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla notifications DB helper"

require_file "$FILES_DIR/openwalla-notifications-db.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3

ensure_openwalla_config
ensure_uci_section notifications notifications

install_file "$FILES_DIR/openwalla-notifications-db.sh" /usr/bin/openwalla-notifications-db 0755
install_rpcd_acl

set_uci_default openwalla.notifications.db_path "/tmp/openwalla/openwalla-notifications.sqlite"
uci commit openwalla

/usr/bin/openwalla-notifications-db --init-db || true

log "Notifications DB helper installed."
