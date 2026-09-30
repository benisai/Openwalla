#!/bin/sh

# Openwalla devices collector for OpenWrt.
# Maintains /tmp/openwalla-devices.sqlite as the app's local device inventory.
# MAC address is the primary key so renamed devices, quarantine state, usage
# totals, and static IP metadata can stay attached to the same client over time.
# Device discovery is gathered from IPv4 DHCP leases, ARP, IPv4 neighbors, and
# wireless station data. When openwalla.quarantine.enabled is set, newly seen
# IPv4 devices are quarantined during this same collection pass.
# Existing hostnames in the DB are preserved, so app-side device renames are not
# overwritten by DHCP/wireless names.
# Run /usr/bin/openwalla-devices-collector --once to trigger an immediate scan
# from the app or shell without waiting for the background polling interval.

set -u

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DEFAULT_DB="/tmp/openwalla-devices.sqlite"
DEFAULT_POLL_SECONDS="15"
DEFAULT_OFFLINE_AFTER_SECONDS="90"
DEFAULT_LAN_NETWORK="lan"
DEFAULT_LAN_DEVICE="br-lan"
DEFAULT_RULE_PREFIX="openwalla_quarantine_"
DEFAULT_STATE_FILE="/tmp/openwalla-quarantine-known.txt"
DEFAULT_NOTIFICATIONS_DB="/tmp/openwalla-notifications.sqlite"
LOG_FILE="/tmp/openwalla-devices-collector.log"
LOCK_DIR="/tmp/openwalla-devices-collector.lock"

DB_PATH="$DEFAULT_DB"
POLL_SECONDS="$DEFAULT_POLL_SECONDS"
OFFLINE_AFTER_SECONDS="$DEFAULT_OFFLINE_AFTER_SECONDS"
LAN_NETWORK="$DEFAULT_LAN_NETWORK"
LAN_DEVICE="$DEFAULT_LAN_DEVICE"
RULE_PREFIX="$DEFAULT_RULE_PREFIX"
STATE_FILE="$DEFAULT_STATE_FILE"
NOTIFICATIONS_DB="$DEFAULT_NOTIFICATIONS_DB"
QUARANTINE_ENABLED="0"
SQLITE_BIN=""

log() {
	printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

init_logging() {
	local dir
	dir="$(dirname "$LOG_FILE")"
	mkdir -p "$dir"
	touch "$LOG_FILE"
	exec >>"$LOG_FILE" 2>&1
}

sanitize_text() {
	local value
	value="${1:-}"
	value="${value#\'}"
	value="${value%\'}"
	value="${value#\"}"
	value="${value%\"}"
	printf "%s" "$value"
}

sanitize_int() {
	case "${1:-}" in
	'' | *[!0-9]*) echo "$2" ;;
	*) echo "$1" ;;
	esac
}

uci_get() {
	uci -q get "$1" 2>/dev/null || true
}

is_enabled_flag() {
	case "$1" in
	1|on|true|yes|enabled) return 0 ;;
	*) return 1 ;;
	esac
}

sanitize_name() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | sed 's/[^a-z0-9_.-]//g' | cut -c1-24
}

find_sqlite_bin() {
	if command -v sqlite3 >/dev/null 2>&1; then
		SQLITE_BIN="$(command -v sqlite3)"
		return 0
	fi
	if command -v sqlite3-cli >/dev/null 2>&1; then
		SQLITE_BIN="$(command -v sqlite3-cli)"
		return 0
	fi
	return 1
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

sql_exec() {
	local query output
	query="$1"
	if ! output="$("$SQLITE_BIN" "$DB_PATH" "PRAGMA busy_timeout=3000; $query" 2>&1)"; then
		log "sqlite error: $output"
		return 1
	fi
	[ -n "$output" ] && log "sqlite: $output"
	return 0
}

is_ipv4() {
	printf '%s\n' "$1" | awk -F. '
		NF != 4 { exit 1 }
		{
			for (i = 1; i <= 4; i++) {
				if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
			}
		}
	'
}

is_hidden_mac() {
	local mac esc_mac hidden
	mac="$1"
	esc_mac="$(sql_escape "$mac")"
	hidden="$("$SQLITE_BIN" "$DB_PATH" "SELECT hidden FROM devices WHERE lower(mac)='$esc_mac' LIMIT 1;" 2>/dev/null || true)"
	[ "$hidden" = "1" ]
}

collect_router_macs() {
	local address_file mac
	for address_file in /sys/class/net/*/address; do
		[ -r "$address_file" ] || continue
		mac="$(tr '[:upper:]' '[:lower:]' <"$address_file" 2>/dev/null || true)"
		case "$mac" in
		[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f])
			[ "$mac" = "00:00:00:00:00:00" ] || echo "$mac"
			;;
		esac
	done | sort -u
}

is_router_mac() {
	local candidate own_mac
	candidate="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
	while IFS= read -r own_mac; do
		[ "$candidate" = "$own_mac" ] && return 0
	done <<EOF
$(collect_router_macs)
EOF
	return 1
}

load_config() {
	local value

	value="$(uci_get openwalla.devices.db_path)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && DB_PATH="$value"

	value="$(uci_get openwalla.devices.poll_seconds)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && POLL_SECONDS="$value"

	value="$(uci_get openwalla.devices.offline_after_seconds)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && OFFLINE_AFTER_SECONDS="$value"

	value="$(uci_get openwalla.quarantine.rule_prefix)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && RULE_PREFIX="$value"

	value="$(uci_get openwalla.quarantine.enabled)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && QUARANTINE_ENABLED="$value"

	value="$(uci_get openwalla.quarantine.state_file)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && STATE_FILE="$value"

	value="$(uci_get openwalla.notifications.db_path)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && NOTIFICATIONS_DB="$value"

	value="$(uci_get openwalla.quarantine.lan_network)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && LAN_NETWORK="$value"

	value="$(uci_get openwalla.quarantine.lan_device)"
	value="$(sanitize_text "$value")"
	[ -n "$value" ] && LAN_DEVICE="$value"

	value="$(uci_get network.lan.device)"
	value="$(sanitize_text "$value")"
	[ "$LAN_DEVICE" = "$DEFAULT_LAN_DEVICE" ] && [ -n "$value" ] && LAN_DEVICE="$value"

	value="$(uci_get network.lan.ifname)"
	value="$(sanitize_text "$value")"
	[ "$LAN_DEVICE" = "$DEFAULT_LAN_DEVICE" ] && [ -n "$value" ] && LAN_DEVICE="$value"

	POLL_SECONDS="$(sanitize_int "$POLL_SECONDS" "$DEFAULT_POLL_SECONDS")"
	OFFLINE_AFTER_SECONDS="$(sanitize_int "$OFFLINE_AFTER_SECONDS" "$DEFAULT_OFFLINE_AFTER_SECONDS")"
	[ "$POLL_SECONDS" -lt 10 ] && POLL_SECONDS="$DEFAULT_POLL_SECONDS"
	[ "$OFFLINE_AFTER_SECONDS" -lt "$POLL_SECONDS" ] && OFFLINE_AFTER_SECONDS=$((POLL_SECONDS * 5))
}

ensure_db_file() {
	local dir
	dir="$(dirname "$DB_PATH")"
	mkdir -p "$dir"
	[ -f "$DB_PATH" ] || : >"$DB_PATH"
	init_db
}

init_db() {
	sql_exec "PRAGMA journal_mode=WAL;" || return 1
	sql_exec "CREATE TABLE IF NOT EXISTS devices (mac TEXT PRIMARY KEY, ip TEXT NOT NULL DEFAULT '', hostname TEXT NOT NULL DEFAULT '', vendor TEXT NOT NULL DEFAULT '', quarantined INTEGER NOT NULL DEFAULT 0, last_seen INTEGER NOT NULL DEFAULT 0, total_up INTEGER NOT NULL DEFAULT 0, total_down INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'offline', static_ip TEXT NOT NULL DEFAULT '', icon TEXT NOT NULL DEFAULT '', scheduled_block INTEGER NOT NULL DEFAULT 0, schedule_until TEXT NOT NULL DEFAULT '', hidden INTEGER NOT NULL DEFAULT 0);" || return 1
	sql_exec "ALTER TABLE devices ADD COLUMN static_ip TEXT NOT NULL DEFAULT '';" 2>/dev/null || true
	sql_exec "ALTER TABLE devices ADD COLUMN icon TEXT NOT NULL DEFAULT '';" 2>/dev/null || true
	sql_exec "ALTER TABLE devices ADD COLUMN scheduled_block INTEGER NOT NULL DEFAULT 0;" 2>/dev/null || true
	sql_exec "ALTER TABLE devices ADD COLUMN schedule_until TEXT NOT NULL DEFAULT '';" 2>/dev/null || true
	sql_exec "ALTER TABLE devices ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;" 2>/dev/null || true
	dedupe_devices
	sql_exec "CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);" || return 1
	sql_exec "CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen);" || return 1
	sql_exec "CREATE INDEX IF NOT EXISTS idx_devices_quarantined ON devices(quarantined);" || return 1
}

dedupe_devices() {
	sql_exec "CREATE TEMP TABLE IF NOT EXISTS openwalla_devices_dedupe AS SELECT lower(d.mac) AS mac, COALESCE((SELECT ip FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.ip!='' ORDER BY (x.status!='offline') DESC, x.last_seen DESC LIMIT 1), '') AS ip, COALESCE((SELECT hostname FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.hostname!='' ORDER BY (x.icon!='') DESC, (x.static_ip!='') DESC, x.last_seen DESC LIMIT 1), '') AS hostname, COALESCE((SELECT vendor FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.vendor!='' ORDER BY x.last_seen DESC LIMIT 1), '') AS vendor, COALESCE((SELECT quarantined FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY x.quarantined DESC, x.last_seen DESC LIMIT 1), 0) AS quarantined, COALESCE((SELECT last_seen FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY (x.status!='offline') DESC, x.last_seen DESC LIMIT 1), 0) AS last_seen, COALESCE((SELECT total_up FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY (x.status!='offline') DESC, x.last_seen DESC LIMIT 1), 0) AS total_up, COALESCE((SELECT total_down FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY (x.status!='offline') DESC, x.last_seen DESC LIMIT 1), 0) AS total_down, COALESCE((SELECT status FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY (x.status='blocked') DESC, (x.status='block-scheduled') DESC, (x.status!='offline') DESC, x.last_seen DESC LIMIT 1), 'offline') AS status, COALESCE((SELECT static_ip FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.static_ip!='' ORDER BY x.last_seen DESC LIMIT 1), '') AS static_ip, COALESCE((SELECT icon FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.icon!='' ORDER BY x.last_seen DESC LIMIT 1), '') AS icon, COALESCE((SELECT scheduled_block FROM devices x WHERE lower(x.mac)=lower(d.mac) ORDER BY x.scheduled_block DESC, x.last_seen DESC LIMIT 1), 0) AS scheduled_block, COALESCE((SELECT schedule_until FROM devices x WHERE lower(x.mac)=lower(d.mac) AND x.schedule_until!='' ORDER BY x.last_seen DESC LIMIT 1), '') AS schedule_until, COALESCE(MAX(d.hidden), 0) AS hidden FROM devices d GROUP BY lower(d.mac); DELETE FROM devices; INSERT INTO devices (mac, ip, hostname, vendor, quarantined, last_seen, total_up, total_down, status, static_ip, icon, scheduled_block, schedule_until, hidden) SELECT mac, ip, hostname, vendor, quarantined, last_seen, total_up, total_down, status, static_ip, icon, scheduled_block, schedule_until, hidden FROM openwalla_devices_dedupe; DROP TABLE openwalla_devices_dedupe;" || true
}

collect_dhcp() {
	[ -f /tmp/dhcp.leases ] || return 0
	awk '{
		if ($2 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) {
			mac=tolower($2)
			ip=$3
			host=$4
			if (host == "*") host=""
			print mac "|" ip "|" host "|0"
		}
	}' /tmp/dhcp.leases
}

collect_arp() {
	if [ -r /proc/net/arp ]; then
		awk -v dev="$LAN_DEVICE" 'NR>1 {
			ip=$1
			mac=tolower($4)
			ifname=$6
			if (ifname == dev && mac ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/ && mac != "00:00:00:00:00:00")
				print mac "|" ip "||" ($3 == "0x2" ? 1 : 0)
		}' /proc/net/arp
	fi
}

collect_ip_neigh() {
	ip -4 neigh show dev "$LAN_DEVICE" 2>/dev/null | awk '{
		ip=$1
		mac=""
		active=0
		for (i=1; i<=NF; i++) {
			if ($i == "lladdr" && (i+1) <= NF) { mac=$(i+1); break }
		}
		for (i=1; i<=NF; i++) {
			if ($i == "REACHABLE" || $i == "DELAY" || $i == "PROBE" || $i == "PERMANENT") active=1
		}
		if (mac ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)
			print tolower(mac) "|" ip "||" active
	}'
}

collect_bridge_fdb() {
	command -v bridge >/dev/null 2>&1 || return 0
	bridge fdb show br "$LAN_DEVICE" 2>/dev/null | awk '
		$1 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/ && $0 !~ / self/ && $0 !~ / permanent/ {
			print tolower($1) "|||1"
		}'
}

collect_wireless() {
	command -v jsonfilter >/dev/null 2>&1 || return 0
	command -v ubus >/dev/null 2>&1 || return 0

	local json
	json="$(ubus call network.wireless status 2>/dev/null || true)"
	[ -n "$json" ] || return 0
	{
		jsonfilter -s "$json" -e "@.*.interfaces[@.config.network='$LAN_NETWORK'].stations[*].mac" 2>/dev/null || true
		jsonfilter -s "$json" -e "@.*.interfaces[@.config.network[0]='$LAN_NETWORK'].stations[*].mac" 2>/dev/null || true
	} | tr ' ' '\n' | sed '/^$/d' | tr '[:upper:]' '[:lower:]' | sort -u | awk '{ print $1 "|||1" }'
}

collect_candidates() {
	{
		collect_dhcp
		collect_arp
		collect_ip_neigh
		collect_bridge_fdb
		collect_wireless
	} | awk -F'|' '
		{
			mac=tolower($1)
			ip=$2
			host=$3
			active_now=$4 + 0
			if (mac ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/) {
				seen[mac]=1
				if (ip != "" && ip_by_mac[mac] == "") ip_by_mac[mac]=ip
				if (host != "" && host_by_mac[mac] == "") host_by_mac[mac]=host
				if (active_now == 1) active[mac]=1
			}
		}
		END {
			for (mac in seen)
				print mac "|" ip_by_mac[mac] "|" host_by_mac[mac] "|" (active[mac] ? 1 : 0)
		}
	'
}

collect_totals() {
	command -v nlbw >/dev/null 2>&1 || return 0
	nlbw -c csv -g mac -o mac -q 2>/dev/null | awk '
		NR == 1 {
			for (i = 1; i <= NF; i++) idx[$i] = i
			next
		}
		NF > 0 {
			mac = tolower($idx["mac"])
			rx = $idx["rx_bytes"] + 0
			tx = $idx["tx_bytes"] + 0
			if (mac ~ /^([0-9a-f][0-9a-f]:){5}[0-9a-f][0-9a-f]$/ && mac != "00:00:00:00:00:00")
				print mac "|" rx "|" tx
		}
	'
}

collect_quarantined() {
	uci -q show firewall 2>/dev/null | awk -F'[.=]' -v prefix="$RULE_PREFIX" '
		$1 == "firewall" && $3 == "name" && index($0, prefix) > 0 {
			section=$2
			quarantine[section]=1
		}
		$1 == "firewall" && $3 == "src_mac" {
			section=$2
			value=$0
			sub(/^[^=]*=/, "", value)
			gsub(/\047/, "", value)
			gsub(/"/, "", value)
			if (quarantine[section] && value ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)
				print tolower(value)
		}
	' | sort -u
}

ensure_state_file() {
	local dir
	dir="$(dirname "$STATE_FILE")"
	mkdir -p "$dir" 2>/dev/null || true
	[ -f "$STATE_FILE" ] || : >"$STATE_FILE"
}

is_known_mac() {
	grep -qx "$1" "$STATE_FILE" 2>/dev/null
}

remember_mac() {
	ensure_state_file
	is_known_mac "$1" || printf '%s\n' "$1" >>"$STATE_FILE"
}

rule_name_for() {
	local mac safe
	mac="$1"
	safe="$(sanitize_name "${2:-}")"
	[ -n "$safe" ] && [ "$safe" != "*" ] || safe="$(printf '%s' "$mac" | tr -d ':')"
	printf '%s%s' "$RULE_PREFIX" "$safe"
}

rule_exists_by_name() {
	uci -q show firewall 2>/dev/null | grep -Fq "name='$1'"
}

add_quarantine_rule() {
	local name="$1" mac="$2" destination="$3" sid
	sid="$(uci add firewall rule 2>/dev/null || true)"
	[ -n "$sid" ] || return 1
	uci set firewall."$sid".name="$name"
	uci set firewall."$sid".src="lan"
	uci set firewall."$sid".dest="$destination"
	uci set firewall."$sid".src_mac="$mac"
	uci set firewall."$sid".proto="all"
	uci set firewall."$sid".target="REJECT"
	uci set firewall."$sid".family="ipv4"
	uci set firewall."$sid".enabled="1"
}

remove_quarantine_rules_for_mac() {
	local mac="$1" section name source changed pass
	changed=0
	for pass in 1 2 3 4; do
		for section in $(uci -q show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=rule$/\1/p'); do
			name="$(uci_get firewall."$section".name)"
			source="$(uci_get firewall."$section".src_mac | tr '[:upper:]' '[:lower:]')"
			case "$name" in
			"${RULE_PREFIX}"*)
				if [ "$source" = "$mac" ]; then
					uci -q delete firewall."$section" >/dev/null 2>&1 || true
					changed=1
				fi
				;;
			esac
		done
	done
	[ "$changed" = "1" ]
}

write_quarantine_notification() {
	local message esc_message
	message="$1"
	esc_message="$(sql_escape "$message")"
	mkdir -p "$(dirname "$NOTIFICATIONS_DB")" 2>/dev/null || true
	"$SQLITE_BIN" "$NOTIFICATIONS_DB" "CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)), app TEXT NOT NULL DEFAULT '', msg TEXT NOT NULL DEFAULT '', archived INTEGER NOT NULL DEFAULT 0, \"delete\" INTEGER NOT NULL DEFAULT 0); INSERT INTO notifications (app, msg, archived, \"delete\") VALUES ('device-quarantine', '$esc_message', 0, 0);" >/dev/null 2>&1 || true
}

quarantine_new_device() {
	local mac="$1" ip="$2" host="$3" base lan wan esc_mac esc_ip esc_host
	base="$(rule_name_for "$mac" "$host")"
	lan="${base}_lan"
	wan="${base}_wan"
	rule_exists_by_name "$lan" || add_quarantine_rule "$lan" "$mac" "lan" || true
	rule_exists_by_name "$wan" || add_quarantine_rule "$wan" "$mac" "wan" || true
	esc_mac="$(sql_escape "$mac")"
	esc_ip="$(sql_escape "$ip")"
	esc_host="$(sql_escape "$host")"
	sql_exec "INSERT INTO devices (mac, ip, hostname, quarantined, last_seen, status) VALUES ('$esc_mac', '$esc_ip', '$esc_host', 1, CAST(strftime('%s','now') AS INTEGER), 'blocked') ON CONFLICT(mac) DO UPDATE SET ip=excluded.ip, hostname=CASE WHEN devices.hostname='' AND excluded.hostname!='' THEN excluded.hostname ELSE devices.hostname END, quarantined=1, last_seen=excluded.last_seen, status='blocked';" || true
	write_quarantine_notification "New device quarantined mac=$mac ip=$ip host=${host:-unknown}"
	log "quarantined new IPv4 device mac=$mac ip=$ip host=${host:-unknown}"
}

process_new_device() {
	local mac="$1" ip="$2" host="$3"
	is_known_mac "$mac" && return 1
	remember_mac "$mac"
	if is_enabled_flag "$QUARANTINE_ENABLED" && [ -n "$ip" ] && is_ipv4 "$ip"; then
		quarantine_new_device "$mac" "$ip" "$host"
		return 0
	fi
	return 1
}

cleanup_excluded_devices() {
	local mac esc_mac changed
	changed=0
	while IFS= read -r mac; do
		[ -n "$mac" ] || continue
		if remove_quarantine_rules_for_mac "$mac"; then changed=1; fi
		esc_mac="$(sql_escape "$mac")"
		sql_exec "DELETE FROM devices WHERE lower(mac)='$esc_mac';" || true
	done <<EOF
$(collect_router_macs)
$($SQLITE_BIN "$DB_PATH" "SELECT lower(mac) FROM devices WHERE instr(ip, ':') > 0;" 2>/dev/null || true)
EOF
	if [ "$changed" = "1" ]; then
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
	fi
}

collect_once() {
	local now cutoff candidates totals quarantined sql mac ip host active_now rx tx is_quarantined esc_mac esc_ip esc_host changed fresh_state
	now="$(date +%s)"
	cutoff=$((now - OFFLINE_AFTER_SECONDS))
	candidates="/tmp/.openwalla-devices-candidates.$$"
	totals="/tmp/.openwalla-devices-totals.$$"
	quarantined="/tmp/.openwalla-devices-quarantined.$$"

	collect_candidates >"$candidates"
	collect_totals >"$totals"
	cleanup_excluded_devices

	fresh_state=0
	[ -f "$STATE_FILE" ] || fresh_state=1
	ensure_state_file
	changed=0
	while IFS='|' read -r mac ip host active_now; do
		[ -n "$mac" ] && [ -n "$ip" ] && is_ipv4 "$ip" || continue
		if [ "$fresh_state" = "1" ]; then
			remember_mac "$mac"
		elif process_new_device "$mac" "$ip" "$host"; then
			changed=1
		fi
	done <"$candidates"
	if [ "$changed" = "1" ]; then
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
	fi
	collect_quarantined >"$quarantined"

	while IFS='|' read -r mac ip host active_now; do
		[ -n "$mac" ] || continue
		is_router_mac "$mac" && continue
		is_hidden_mac "$mac" && continue
		if [ -n "$ip" ] && ! is_ipv4 "$ip"; then
			continue
		fi
		rx="$(awk -F'|' -v m="$mac" '$1 == m { print $2; found=1; exit } END { if (!found) print 0 }' "$totals")"
		tx="$(awk -F'|' -v m="$mac" '$1 == m { print $3; found=1; exit } END { if (!found) print 0 }' "$totals")"
		case "$rx" in '' | *[!0-9]*) rx=0 ;; esac
		case "$tx" in '' | *[!0-9]*) tx=0 ;; esac
		if grep -qx "$mac" "$quarantined" 2>/dev/null; then
			is_quarantined=1
		else
			is_quarantined=0
		fi

		esc_mac="$(sql_escape "$mac")"
		esc_ip="$(sql_escape "$ip")"
		esc_host="$(sql_escape "$host")"
		if [ "$active_now" = "1" ]; then
			sql="INSERT INTO devices (mac, ip, hostname, vendor, quarantined, last_seen, total_up, total_down, status) VALUES ('$esc_mac', '$esc_ip', '$esc_host', '', $is_quarantined, $now, $tx, $rx, 'online') ON CONFLICT(mac) DO UPDATE SET ip=CASE WHEN excluded.ip != '' THEN excluded.ip ELSE devices.ip END, hostname=CASE WHEN devices.hostname = '' AND excluded.hostname != '' THEN excluded.hostname ELSE devices.hostname END, quarantined=excluded.quarantined, last_seen=excluded.last_seen, total_up=excluded.total_up, total_down=excluded.total_down, status=CASE WHEN devices.scheduled_block=1 THEN 'block-scheduled' ELSE excluded.status END;"
		else
			sql="INSERT INTO devices (mac, ip, hostname, vendor, quarantined, last_seen, total_up, total_down, status) VALUES ('$esc_mac', '$esc_ip', '$esc_host', '', $is_quarantined, 0, $tx, $rx, 'offline') ON CONFLICT(mac) DO UPDATE SET ip=CASE WHEN excluded.ip != '' THEN excluded.ip ELSE devices.ip END, hostname=CASE WHEN devices.hostname = '' AND excluded.hostname != '' THEN excluded.hostname ELSE devices.hostname END, quarantined=excluded.quarantined, total_up=excluded.total_up, total_down=excluded.total_down;"
		fi
		sql_exec "$sql" || true
	done <"$candidates"

	while IFS= read -r mac; do
		[ -n "$mac" ] || continue
		esc_mac="$(sql_escape "$mac")"
		sql_exec "UPDATE devices SET quarantined=1 WHERE mac='$esc_mac';" || true
	done <"$quarantined"

	sql_exec "UPDATE devices SET status='offline' WHERE last_seen < $cutoff AND quarantined = 0 AND scheduled_block = 0;"
	sql_exec "UPDATE devices SET status='blocked' WHERE quarantined = 1;"

	rm -f "$candidates" "$totals" "$quarantined"
}

handle_event() {
	local mac ip host changed fresh_state
	mac="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
	ip="${2:-}"
	host="${3:-}"
	case "$mac" in
	[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) ;;
	*) return 0 ;;
	esac
	[ -n "$ip" ] && is_ipv4 "$ip" || return 0
	is_router_mac "$mac" && return 0
	is_hidden_mac "$mac" && return 0

	fresh_state=0
	[ -f "$STATE_FILE" ] || fresh_state=1
	if [ "$fresh_state" = "1" ]; then
		collect_candidates | while IFS='|' read -r candidate candidate_ip candidate_host candidate_active; do
			[ -n "$candidate_ip" ] && is_ipv4 "$candidate_ip" && remember_mac "$candidate"
		done
		remember_mac "$mac"
		return 0
	fi
	if process_new_device "$mac" "$ip" "$host"; then
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
	fi
}

hide_device() {
	local mac esc_mac changed
	mac="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
	case "$mac" in
	[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) ;;
	*) return 1 ;;
	esac
	changed=0
	if remove_quarantine_rules_for_mac "$mac"; then changed=1; fi
	esc_mac="$(sql_escape "$mac")"
	sql_exec "INSERT INTO devices (mac, hidden, quarantined, status) VALUES ('$esc_mac', 1, 0, 'offline') ON CONFLICT(mac) DO UPDATE SET hidden=1, quarantined=0, scheduled_block=0, schedule_until='', status='offline';" || return 1
	remember_mac "$mac"
	if [ "$changed" = "1" ]; then
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
	fi
}

run_locked() {
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		log "collector already running; event deferred"
		return 0
	fi
	"$@"
	local result=$?
	rmdir "$LOCK_DIR" 2>/dev/null || true
	return "$result"
}

run_daemon() {
	log "starting devices collector db=$DB_PATH poll=${POLL_SECONDS}s offline_after=${OFFLINE_AFTER_SECONDS}s"
	while true; do
		load_config
		run_locked collect_once || log "collector iteration failed"
		sleep "$POLL_SECONDS"
	done
}

load_config
init_logging
log "collector boot mode=${1:---daemon}"
if ! find_sqlite_bin; then
	log "sqlite3 not found; install sqlite3-cli"
	exit 1
fi

case "${1:---daemon}" in
--init-db)
	ensure_db_file
	;;
--once)
	ensure_db_file
	run_locked collect_once
	;;
--event)
	ensure_db_file
	run_locked handle_event "${2:-}" "${3:-}" "${4:-}"
	;;
--hide)
	ensure_db_file
	run_locked hide_device "${2:-}"
	;;
--daemon)
	ensure_db_file
	run_daemon
	;;
*)
	echo "Usage: $0 [--init-db|--once|--daemon|--event MAC IPv4 [HOSTNAME]|--hide MAC]"
	exit 2
	;;
esac
