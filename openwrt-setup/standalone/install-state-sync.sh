#!/bin/sh

# Standalone installer for Openwalla state sync.
# Installs boot/cron helpers that persist selected runtime state outside /tmp.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla state sync"

require_file "$FILES_DIR/openwalla-state-sync.sh"
require_file "$FILES_DIR/openwalla-state-sync.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

if ! have_cmd sqlite3 && ! have_cmd sqlite3-cli; then
	update_package_feeds
	install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3
fi

ensure_openwalla_config
ensure_uci_section state_backup state_backup

install_file "$FILES_DIR/openwalla-state-sync.sh" /usr/bin/openwalla-state-sync 0755
install_file "$FILES_DIR/openwalla-state-sync.init" /etc/init.d/openwalla-state-sync 0755
install_rpcd_acl

set_uci_default openwalla.state_backup.backup_time "720"
set_uci_default openwalla.state_backup.state_dir "/overlay/openwalla-state"
uci commit openwalla

# Preserve the current runtime state before restarting the sync service. A
# restore here can overwrite newer /tmp data with an older checkpoint during
# a routine reinstall; boot-time restore remains handled by the init service.
if ! /usr/bin/openwalla-state-sync save; then
	log "ERROR: State backup failed; refusing to restart State Sync and restore an older checkpoint."
	exit 1
fi
/usr/bin/openwalla-state-sync sync-cron || true

if [ -f /etc/rc.local ]; then
	if ! grep -q '/usr/bin/openwalla-state-sync restore' /etc/rc.local 2>/dev/null; then
		RC_TMP="/tmp/openwalla/.openwalla_rc_local.$$"
		awk '
			BEGIN { added=0 }
			/^exit 0$/ && !added { print "/usr/bin/openwalla-state-sync restore"; added=1 }
			{ print }
			END {
				if (!added) {
					print "/usr/bin/openwalla-state-sync restore"
					print "exit 0"
				}
			}
		' /etc/rc.local >"$RC_TMP"
		cp "$RC_TMP" /etc/rc.local
		rm -f "$RC_TMP"
	fi
else
	cat <<'EOF' >/etc/rc.local
/usr/bin/openwalla-state-sync restore
exit 0
EOF
fi
chmod +x /etc/rc.local

enable_restart_service openwalla-state-sync

log "State sync installed."
