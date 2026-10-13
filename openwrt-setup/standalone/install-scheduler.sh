#!/bin/sh

# Standalone installer for Openwalla device scheduling.
# Installs the scheduler helper, initializes schedule tables, and adds the
# cron entry that applies scheduled internet blocks every minute.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla scheduler"

require_file "$FILES_DIR/openwalla-scheduler.sh"
require_file "$FILES_DIR/openwalla-parental.sh"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3

ensure_openwalla_config
ensure_uci_section features ui
ensure_uci_section scheduler scheduler

install_file "$FILES_DIR/openwalla-scheduler.sh" /usr/bin/openwalla-scheduler 0755
install_file "$FILES_DIR/openwalla-parental.sh" /usr/bin/openwalla-parental 0755
install_rpcd_acl

set_uci openwalla.features.scheduler "1"
set_uci openwalla.scheduler.enabled "1"
set_uci openwalla.scheduler.rule_prefix "openwalla_schedule_"
ensure_uci_section parental parental
set_uci openwalla.parental.db_path "/tmp/openwalla/openwalla-parental.sqlite"
uci commit openwalla

/usr/bin/openwalla-scheduler --init-db || true
/usr/bin/openwalla-parental --init-db || true

SCHEDULER_MARKER="# OPENWALLA_SCHEDULER"
CRON_PATH="/etc/crontabs/root"
TMP_CRON="/tmp/openwalla/.openwalla_scheduler_cron.$$"
if [ -f "$CRON_PATH" ]; then
	grep -v "$SCHEDULER_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
else
	: >"$TMP_CRON"
fi
echo "* * * * * mkdir -p /tmp/openwalla; /usr/bin/openwalla-scheduler apply >/tmp/openwalla/openwalla-scheduler.last.log 2>&1 $SCHEDULER_MARKER" >>"$TMP_CRON"
echo "* * * * * mkdir -p /tmp/openwalla; /usr/bin/openwalla-parental apply >/tmp/openwalla/openwalla-parental.last.log 2>&1 $SCHEDULER_MARKER" >>"$TMP_CRON"
cp "$TMP_CRON" "$CRON_PATH"
rm -f "$TMP_CRON"
reload_cron

log "Openwalla scheduler installed."
