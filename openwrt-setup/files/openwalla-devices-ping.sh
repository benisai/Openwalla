#!/bin/sh

# Positive reachability checks supplement DHCP, Wi-Fi and neighbor discovery.
# Missed replies are not proof of disconnection; the collector owns expiry.
set -u

RUNTIME_DIR="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
DB_PATH="${OPENWALLA_DEVICES_DB:-$(uci -q get openwalla.devices.db_path 2>/dev/null || true)}"
DB_PATH="${DB_PATH:-/tmp/openwalla/openwalla-devices.sqlite}"
LOCK_DIR="$RUNTIME_DIR/openwalla-devices-ping.lock"

find_sqlite_bin() {
	command -v sqlite3 2>/dev/null || command -v sqlite3-cli 2>/dev/null
}

valid_client() {
	case "$1" in
	[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]) ;;
	*) return 1 ;;
	esac
	printf '%s\n' "$2" | awk -F. '
		NF != 4 { exit 1 }
		{ for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i>255) exit 1 }
		$1 == 0 || $1 == 127 || $1 >= 224 { exit 1 }
	'
}

probe_client() {
	local mac ip neighbor now
	mac="$1"; ip="$2"
	ping -n -c 1 -W 2 "$ip" >/dev/null 2>&1 || return 0
	# A historical IP may now belong to another client. Never refresh that MAC.
	neighbor="$(ip -4 neigh show to "$ip" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="lladdr") print tolower($(i+1))}')"
	[ -z "$neighbor" ] || [ "$neighbor" = "$mac" ] || return 0
	now="$(date +%s)"
	printf "UPDATE devices SET last_seen=MAX(last_seen,%s), status=CASE WHEN quarantined=1 OR status='blocked' THEN 'blocked' WHEN scheduled_block=1 THEN 'block-scheduled' ELSE 'online' END WHERE lower(mac)='%s' AND ip='%s' AND hidden=0;\n" \
		"$now" "$mac" "$ip" >"$LOCK_DIR/$mac.sql"
}

run_scan() {
	local sqlite_bin mac ip count pid result address_file
	[ -f "$DB_PATH" ] || return 0
	[ "$(uci -q get openwalla.devices.enabled 2>/dev/null || true)" != 0 ] || return 0
	sqlite_bin="$(find_sqlite_bin)" || { echo "[openwalla-ping] SQLite is unavailable." >&2; return 1; }
	command -v ping >/dev/null 2>&1 || return 1
	command -v ip >/dev/null 2>&1 || return 1
	mkdir -p "$RUNTIME_DIR" || return 1
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		echo "[openwalla-ping] A scan is already running; skipping."
		return 0
	fi
	trap 'rm -rf "$LOCK_DIR"' EXIT
	trap 'for pid in $pids; do kill "$pid" 2>/dev/null || true; done; wait; exit 1' INT TERM
	pids=""
	if ! "$sqlite_bin" -batch -noheader -separator '|' "$DB_PATH" \
		"PRAGMA busy_timeout=3000; SELECT lower(mac),ip FROM devices WHERE hidden=0 AND ip!='';" >"$LOCK_DIR/clients"; then
		return 1
	fi
	{
		for address_file in /sys/class/net/*/address; do
			[ ! -r "$address_file" ] || cat "$address_file"
		done
		ip -4 addr show | awk '/^[[:space:]]*inet / {sub(/\/.*/,"",$2); print $2}'
	} | tr '[:upper:]' '[:lower:]' >"$LOCK_DIR/router-addresses"
	count=0
	while IFS='|' read -r mac ip; do
		valid_client "$mac" "$ip" || continue
		grep -Fxq "$mac" "$LOCK_DIR/router-addresses" && continue
		grep -Fxq "$ip" "$LOCK_DIR/router-addresses" && continue
		probe_client "$mac" "$ip" &
		pids="$pids $!"
		count=$((count + 1))
		if [ "$count" -eq 5 ]; then
			wait
			pids=""; count=0
		fi
	done <"$LOCK_DIR/clients"
	wait
	pids=""
	# Serialize writes rather than having five workers contend with the collector.
	{
		printf 'PRAGMA busy_timeout=3000;\nBEGIN IMMEDIATE;\n'
		for result in "$LOCK_DIR"/*.sql; do
			[ ! -f "$result" ] || cat "$result"
		done
		printf 'COMMIT;\n'
	} | "$sqlite_bin" -batch -bail "$DB_PATH" >/dev/null
}

run_scan
