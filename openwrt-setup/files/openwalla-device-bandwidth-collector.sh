#!/bin/sh

# Openwalla device bandwidth collector for OpenWrt.
# Uses nlbwmon's cumulative per-MAC counters and stores rolling 15-minute buckets.

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DEFAULT_DB="/tmp/openwalla-device-bandwidth.sqlite"
DEFAULT_POLL_SECONDS="60"
DEFAULT_BUCKET_SECONDS="900"
DEFAULT_RETENTION_SECONDS="86400"
LOG_FILE="/tmp/openwalla-device-bandwidth-collector.log"

DB_PATH="$DEFAULT_DB"
POLL_SECONDS="$DEFAULT_POLL_SECONDS"
BUCKET_SECONDS="$DEFAULT_BUCKET_SECONDS"
RETENTION_SECONDS="$DEFAULT_RETENTION_SECONDS"
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
		'' | *[!0-9]*)
			echo "$2"
			;;
		*)
			echo "$1"
			;;
	esac
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

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

load_config() {
	if command -v uci >/dev/null 2>&1; then
		local value
		value="$(uci -q get openwalla.device_bandwidth.db_path 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && DB_PATH="$value"

		value="$(uci -q get openwalla.device_bandwidth.poll_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && POLL_SECONDS="$value"

		value="$(uci -q get openwalla.device_bandwidth.bucket_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && BUCKET_SECONDS="$value"

		value="$(uci -q get openwalla.device_bandwidth.retention_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && RETENTION_SECONDS="$value"
	fi

	POLL_SECONDS="$(sanitize_int "$POLL_SECONDS" "$DEFAULT_POLL_SECONDS")"
	BUCKET_SECONDS="$(sanitize_int "$BUCKET_SECONDS" "$DEFAULT_BUCKET_SECONDS")"
	RETENTION_SECONDS="$(sanitize_int "$RETENTION_SECONDS" "$DEFAULT_RETENTION_SECONDS")"
	[ "$POLL_SECONDS" -lt 10 ] && POLL_SECONDS=60
	[ "$BUCKET_SECONDS" -lt 60 ] && BUCKET_SECONDS=900
	[ "$RETENTION_SECONDS" -lt "$BUCKET_SECONDS" ] && RETENTION_SECONDS=86400
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
	sql_exec "CREATE TABLE IF NOT EXISTS device_bandwidth_snapshots (mac TEXT PRIMARY KEY, rx_bytes INTEGER NOT NULL DEFAULT 0, tx_bytes INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL);" || return 1
	sql_exec "CREATE TABLE IF NOT EXISTS device_bandwidth_15m (bucket_start INTEGER NOT NULL, mac TEXT NOT NULL, rx_bytes INTEGER NOT NULL DEFAULT 0, tx_bytes INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, PRIMARY KEY (bucket_start, mac));" || return 1
	sql_exec "CREATE INDEX IF NOT EXISTS idx_device_bandwidth_15m_mac_bucket ON device_bandwidth_15m(mac, bucket_start DESC);" || return 1
	return 0
}

prune_db() {
	local now cutoff
	now="$(date +%s)"
	cutoff=$((now - RETENTION_SECONDS))
	sql_exec "DELETE FROM device_bandwidth_15m WHERE bucket_start < $cutoff;"
}

parse_nlbw_csv() {
	nlbw -c csv -g mac -o mac -s "|" -q 2>/dev/null | awk -F'|' '
		BEGIN { OFS="\t" }
		NR == 1 {
			for (i = 1; i <= NF; i++) {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
				idx[$i] = i
			}
			next
		}
		NF > 0 {
			mac = tolower($idx["mac"])
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", mac)
			if (mac ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ && mac != "00:00:00:00:00:00") {
				rx[mac] += $idx["rx_bytes"] + 0
				tx[mac] += $idx["tx_bytes"] + 0
			}
		}
		END {
			for (mac in rx)
				printf "%s\t%.0f\t%.0f\n", mac, rx[mac], tx[mac]
		}
	'
}

collect_once() {
	if ! command -v nlbw >/dev/null 2>&1; then
		log "nlbw command not found"
		return 1
	fi

	local now bucket tmp rows values snapshots mac rx tx old_rx old_tx rx_delta tx_delta esc_mac
	now="$(date +%s)"
	bucket=$((now - (now % BUCKET_SECONDS)))
	tmp="/tmp/.openwalla-device-bandwidth.$$"
	: >"$tmp"

	parse_nlbw_csv >"$tmp"
	if [ ! -s "$tmp" ]; then
		rm -f "$tmp"
		log "nlbw returned no per-MAC rows"
		return 0
	fi

	rows=""
	snapshots=""
	while IFS="$(printf '\t')" read -r mac rx tx; do
		[ -n "$mac" ] || continue
		case "$rx" in '' | *[!0-9]*) rx=0 ;; esac
		case "$tx" in '' | *[!0-9]*) tx=0 ;; esac

		old_rx="$("$SQLITE_BIN" "$DB_PATH" "SELECT rx_bytes FROM device_bandwidth_snapshots WHERE mac='$(sql_escape "$mac")';" 2>/dev/null | head -n 1)"
		old_tx="$("$SQLITE_BIN" "$DB_PATH" "SELECT tx_bytes FROM device_bandwidth_snapshots WHERE mac='$(sql_escape "$mac")';" 2>/dev/null | head -n 1)"
		case "$old_rx" in '' | *[!0-9]*) old_rx="" ;; esac
		case "$old_tx" in '' | *[!0-9]*) old_tx="" ;; esac

		rx_delta=0
		tx_delta=0
		if [ -n "$old_rx" ] && [ -n "$old_tx" ]; then
			rx_delta=$((rx - old_rx))
			tx_delta=$((tx - old_tx))
			[ "$rx_delta" -lt 0 ] && rx_delta=0
			[ "$tx_delta" -lt 0 ] && tx_delta=0
		fi

		esc_mac="$(sql_escape "$mac")"
		if [ "$rx_delta" -gt 0 ] || [ "$tx_delta" -gt 0 ]; then
			values="($bucket,'$esc_mac',$rx_delta,$tx_delta,$now)"
			if [ -n "$rows" ]; then rows="$rows,$values"; else rows="$values"; fi
		fi
		values="('$esc_mac',$rx,$tx,$now)"
		if [ -n "$snapshots" ]; then snapshots="$snapshots,$values"; else snapshots="$values"; fi
	done <"$tmp"
	rm -f "$tmp"

	if [ -n "$rows" ]; then
		sql_exec "INSERT INTO device_bandwidth_15m (bucket_start, mac, rx_bytes, tx_bytes, updated_at) VALUES $rows ON CONFLICT(bucket_start, mac) DO UPDATE SET rx_bytes=rx_bytes+excluded.rx_bytes, tx_bytes=tx_bytes+excluded.tx_bytes, updated_at=excluded.updated_at;" || return 1
	fi
	if [ -n "$snapshots" ]; then
		sql_exec "INSERT INTO device_bandwidth_snapshots (mac, rx_bytes, tx_bytes, updated_at) VALUES $snapshots ON CONFLICT(mac) DO UPDATE SET rx_bytes=excluded.rx_bytes, tx_bytes=excluded.tx_bytes, updated_at=excluded.updated_at;" || return 1
	fi
	prune_db
	return 0
}

run_daemon() {
	log "starting device bandwidth collector db=$DB_PATH poll=${POLL_SECONDS}s bucket=${BUCKET_SECONDS}s retention=${RETENTION_SECONDS}s"
	while true; do
		collect_once || log "collector iteration failed"
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
		collect_once
		;;
	--daemon)
		ensure_db_file
		run_daemon
		;;
	*)
		echo "Usage: $0 [--init-db|--once|--daemon]"
		exit 2
		;;
esac
