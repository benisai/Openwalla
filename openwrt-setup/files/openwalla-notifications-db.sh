#!/bin/sh

# Openwalla notifications database helper for OpenWrt.
# Initializes and maintains /tmp/openwalla/openwalla-notifications.sqlite for router-side
# events. Other Openwalla scripts call this helper to insert, archive, delete,
# or query notifications that the mobile app displays.

set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
mkdir -p /tmp/openwalla
DB_PATH_DEFAULT="/tmp/openwalla/openwalla-notifications.sqlite"
DB_PATH="$(uci -q get openwalla.notifications.db_path 2>/dev/null || true)"
[ -n "$DB_PATH" ] || DB_PATH="$DB_PATH_DEFAULT"

SQLITE_BIN=""
if command -v sqlite3 >/dev/null 2>&1; then
	SQLITE_BIN="$(command -v sqlite3)"
elif command -v sqlite3-cli >/dev/null 2>&1; then
	SQLITE_BIN="$(command -v sqlite3-cli)"
else
	echo "sqlite3/sqlite3-cli not found"
	exit 1
fi

init_db() {
	mkdir -p "$(dirname "$DB_PATH")"
	"$SQLITE_BIN" "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS notifications (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	timestamp INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
	app TEXT NOT NULL DEFAULT '',
	msg TEXT NOT NULL DEFAULT '',
	archived INTEGER NOT NULL DEFAULT 0,
	"delete" INTEGER NOT NULL DEFAULT 0,
	category TEXT NOT NULL DEFAULT '',
	severity TEXT NOT NULL DEFAULT '',
	title TEXT NOT NULL DEFAULT '',
	details TEXT NOT NULL DEFAULT '',
	metadata TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_notifications_timestamp ON notifications(timestamp);
CREATE INDEX IF NOT EXISTS idx_notifications_archived ON notifications(archived);
SQL
	for column in \
		"category TEXT NOT NULL DEFAULT ''" \
		"severity TEXT NOT NULL DEFAULT ''" \
		"title TEXT NOT NULL DEFAULT ''" \
		"details TEXT NOT NULL DEFAULT ''" \
		"metadata TEXT NOT NULL DEFAULT ''"; do
		name="${column%% *}"
		"$SQLITE_BIN" "$DB_PATH" "SELECT $name FROM notifications LIMIT 0;" >/dev/null 2>&1 || \
			"$SQLITE_BIN" "$DB_PATH" "ALTER TABLE notifications ADD COLUMN $column;"
	done
	echo "initialized: $DB_PATH"
}

case "${1:-}" in
--init-db)
	init_db
	;;
*)
	echo "Usage: $0 --init-db"
	exit 1
	;;
esac
