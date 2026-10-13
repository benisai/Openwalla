#!/bin/sh

# Openwalla lightweight connection flow collector for OpenWrt.
# Streams conntrack events with `conntrack -E` and stores unique flow rows in SQLite.
# Falls back to periodic snapshots when event streaming is not available.

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
mkdir -p /tmp/openwalla

DEFAULT_DB="/tmp/openwalla/openwalla-connection-flows.sqlite"
DEFAULT_POLL_SECONDS="15"
DEFAULT_RETENTION_ROWS="50000"
DEFAULT_EXCLUDE_ENDPOINTS="127.0.0.1"
DEFAULT_IGNORE_IPV6="1"
DEFAULT_LAN_TO_WAN_ONLY="0"
LOG_FILE="/tmp/openwalla/openwalla-connection-flows-collector.log"

FLOW_DB="${OPENWALLA_CONNECTION_FLOWS_DB:-$DEFAULT_DB}"
POLL_SECONDS="$DEFAULT_POLL_SECONDS"
RETENTION_ROWS="$DEFAULT_RETENTION_ROWS"
EXCLUDE_ENDPOINTS="$DEFAULT_EXCLUDE_ENDPOINTS"
IGNORE_IPV6="$DEFAULT_IGNORE_IPV6"
LAN_TO_WAN_ONLY="$DEFAULT_LAN_TO_WAN_ONLY"
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
	if ! output="$("$SQLITE_BIN" "$FLOW_DB" "PRAGMA busy_timeout=3000; $query" 2>&1)"; then
		log "sqlite error: $output"
		return 1
	fi
	[ -n "$output" ] && log "sqlite: $output"
	return 0
}

load_config() {
	if command -v uci >/dev/null 2>&1; then
		local value
		value="$(uci -q get openwalla.connection_flows.db_path 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && FLOW_DB="$value"

		value="$(uci -q get openwalla.connection_flows.poll_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && POLL_SECONDS="$value"

		value="$(uci -q get openwalla.connection_flows.retention_rows 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && RETENTION_ROWS="$value"

		value="$(uci -q get openwalla.connection_flows.exclude_endpoints 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && EXCLUDE_ENDPOINTS="$value"

		value="$(uci -q get openwalla.connection_flows.ignore_ipv6 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && IGNORE_IPV6="$value"

		value="$(uci -q get openwalla.connection_flows.lan_to_wan_only 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && LAN_TO_WAN_ONLY="$value"
	fi

	POLL_SECONDS="$(sanitize_int "$POLL_SECONDS" "$DEFAULT_POLL_SECONDS")"
	RETENTION_ROWS="$(sanitize_int "$RETENTION_ROWS" "$DEFAULT_RETENTION_ROWS")"
	IGNORE_IPV6="$(sanitize_int "$IGNORE_IPV6" "$DEFAULT_IGNORE_IPV6")"
	LAN_TO_WAN_ONLY="$(sanitize_int "$LAN_TO_WAN_ONLY" "$DEFAULT_LAN_TO_WAN_ONLY")"
	[ "$POLL_SECONDS" -lt 1 ] && POLL_SECONDS=5
	[ "$RETENTION_ROWS" -lt 100 ] && RETENTION_ROWS=100
	[ "$IGNORE_IPV6" -ne 1 ] && IGNORE_IPV6=0
	[ "$LAN_TO_WAN_ONLY" -ne 1 ] && LAN_TO_WAN_ONLY=0
}

ensure_db_file() {
	local dir
	dir="$(dirname "$FLOW_DB")"
	mkdir -p "$dir"
	[ -f "$FLOW_DB" ] || : >"$FLOW_DB"
	init_db
}

init_db() {
	sql_exec "PRAGMA journal_mode=WAL;" || return 1
	sql_exec "CREATE TABLE IF NOT EXISTS connection_flows (id INTEGER PRIMARY KEY AUTOINCREMENT,timeinsert INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),protocol TEXT,source TEXT,destination TEXT,transfer TEXT,status TEXT,sig TEXT UNIQUE);" || return 1
	sql_exec "CREATE INDEX IF NOT EXISTS idx_connection_flows_time ON connection_flows(timeinsert);" || return 1
	return 0
}

prune_db() {
	sql_exec "DELETE FROM connection_flows
		WHERE id <= (
			SELECT CASE
				WHEN MAX(id) > $RETENTION_ROWS THEN MAX(id) - $RETENTION_ROWS
				ELSE 0
			END
			FROM connection_flows
		);"
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

should_skip_endpoint() {
	local source destination source_host destination_host token old_ifs
	source="$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')"
	destination="$(printf "%s" "${2:-}" | tr '[:upper:]' '[:lower:]')"
	[ -n "$source" ] || return 1
	[ -n "$destination" ] || return 1
	source_host="$(printf "%s" "$source" | sed -E 's/^(([0-9]{1,3}\.){3}[0-9]{1,3}):[0-9]+$/\1/')"
	destination_host="$(printf "%s" "$destination" | sed -E 's/^(([0-9]{1,3}\.){3}[0-9]{1,3}):[0-9]+$/\1/')"

	old_ifs="$IFS"
	IFS=','
	for token in $EXCLUDE_ENDPOINTS; do
		token="$(sanitize_text "$token")"
		token="$(printf "%s" "$token" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
		[ -n "$token" ] || continue
		if [ "$source" = "$token" ] || [ "$destination" = "$token" ] || [ "$source_host" = "$token" ] || [ "$destination_host" = "$token" ]; then
			IFS="$old_ifs"
			return 0
		fi
	done
	IFS="$old_ifs"
	return 1
}

is_ipv6_endpoint() {
	local value
	value="$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	[ -n "$value" ] || return 1
	# IPv4 or IPv4:port => not IPv6
	if printf "%s" "$value" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?$'; then
		return 1
	fi
	# Anything else containing ":" is treated as IPv6 endpoint.
	printf "%s" "$value" | grep -q ':'
}

endpoint_host() {
	local value
	value="$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	printf "%s" "$value" | sed -E 's/^(([0-9]{1,3}\.){3}[0-9]{1,3}):[0-9]+$/\1/'
}

is_ipv4_addr() {
	printf "%s" "${1:-}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

is_rfc1918_ipv4() {
	case "${1:-}" in
	10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[0-1].*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

is_private_or_local_ipv4() {
	case "${1:-}" in
	10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[0-1].* | 127.* | 169.254.* | 100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

should_skip_non_lan_wan() {
	local source_host destination_host
	source_host="$(endpoint_host "$1")"
	destination_host="$(endpoint_host "$2")"

	is_ipv4_addr "$source_host" || return 0
	is_ipv4_addr "$destination_host" || return 0
	is_rfc1918_ipv4 "$source_host" || return 0
	is_private_or_local_ipv4 "$destination_host" && return 0
	return 1
}

conntrack_source() {
	if command -v conntrack >/dev/null 2>&1; then
		(conntrack -L -o extended 2>/dev/null || conntrack -L 2>/dev/null) | head -n 600
		return 0
	fi
	if [ -r /proc/net/nf_conntrack ]; then
		head -n 600 /proc/net/nf_conntrack 2>/dev/null
		return 0
	fi
	if [ -r /proc/net/ip_conntrack ]; then
		head -n 600 /proc/net/ip_conntrack 2>/dev/null
		return 0
	fi
	return 1
}

parse_conntrack() {
	awk '
		{
			proto="UNKNOWN"; state="ACTIVE";
			src=""; dst=""; sport=""; dport="";
			bytes=0; packets=0;
			for (i=1; i<=NF; i++) {
				t=$i;
				if (t ~ /^(tcp|udp|icmp|icmpv6|sctp|gre|dccp)$/) proto=toupper(t);
				if (t ~ /^src=/ && src=="") src=substr(t,5);
				if (t ~ /^dst=/ && dst=="") dst=substr(t,5);
				if (t ~ /^sport=/ && sport=="") sport=substr(t,7);
				if (t ~ /^dport=/ && dport=="") dport=substr(t,7);
				if (t ~ /^bytes=/) bytes += substr(t,7)+0;
				if (t ~ /^packets=/) packets += substr(t,9)+0;
				if (t ~ /^\[(NEW|UPDATE|DESTROY)\]$/) continue;
				if (t ~ /^(ESTABLISHED|SYN_SENT|SYN_RECV|FIN_WAIT|TIME_WAIT|CLOSE|CLOSE_WAIT|LAST_ACK|LISTEN|CLOSING|UNREPLIED|ASSURED)$/) state=t;
				if (state=="ACTIVE" && t ~ /^\[[A-Z_]+\]$/) {
					state=substr(t,2,length(t)-2);
				}
			}
			if (src=="" || dst=="") next;
			# Store SOURCE as IP only (no port) so sqlite data stays consistent.
			source=src;
			destination=dst; if (dport!="") destination=destination ":" dport;
			transfer=bytes " B (" packets " Pkts.)";
			printf "%s|%s|%s|%s|%s\n", proto, source, destination, transfer, state;
		}
	'
}

insert_row_fields() {
	local protocol source destination transfer status sig
	protocol="$1"
	source="$2"
	destination="$3"
	transfer="$4"
	status="$5"

	[ -n "$protocol" ] || return 0
	if [ "$IGNORE_IPV6" = "1" ]; then
		if is_ipv6_endpoint "$source" || is_ipv6_endpoint "$destination"; then
			return 0
		fi
	fi
	if [ "$LAN_TO_WAN_ONLY" = "1" ]; then
		if should_skip_non_lan_wan "$source" "$destination"; then
			return 0
		fi
	fi
	if should_skip_endpoint "$source" "$destination"; then
		return 0
	fi

	sig="${protocol}|${source}|${destination}|${transfer}|${status}"
	protocol="$(sql_escape "$protocol")"
	source="$(sql_escape "$source")"
	destination="$(sql_escape "$destination")"
	transfer="$(sql_escape "$transfer")"
	status="$(sql_escape "$status")"
	sig="$(sql_escape "$sig")"
	sql_exec "INSERT OR IGNORE INTO connection_flows(timeinsert, protocol, source, destination, transfer, status, sig) VALUES (CAST(strftime('%s','now') AS INTEGER), '$protocol', '$source', '$destination', '$transfer', '$status', '$sig');"
}

insert_rows() {
	local tmp sql line protocol source destination transfer status sig
	tmp="$(mktemp)"
	cat >"$tmp"
	[ -s "$tmp" ] || {
		rm -f "$tmp"
		return 0
	}

	sql="BEGIN;"
	while IFS='|' read -r protocol source destination transfer status; do
		[ -n "$protocol" ] || continue
		if [ "$IGNORE_IPV6" = "1" ]; then
			if is_ipv6_endpoint "$source" || is_ipv6_endpoint "$destination"; then
				continue
			fi
		fi
		if [ "$LAN_TO_WAN_ONLY" = "1" ]; then
			if should_skip_non_lan_wan "$source" "$destination"; then
				continue
			fi
		fi
		if should_skip_endpoint "$source" "$destination"; then
			continue
		fi
		sig="${protocol}|${source}|${destination}|${transfer}|${status}"
		protocol="$(sql_escape "$protocol")"
		source="$(sql_escape "$source")"
		destination="$(sql_escape "$destination")"
		transfer="$(sql_escape "$transfer")"
		status="$(sql_escape "$status")"
		sig="$(sql_escape "$sig")"
		sql="$sql INSERT OR IGNORE INTO connection_flows(timeinsert, protocol, source, destination, transfer, status, sig) VALUES (CAST(strftime('%s','now') AS INTEGER), '$protocol', '$source', '$destination', '$transfer', '$status', '$sig');"
	done <"$tmp"
	sql="$sql COMMIT;"
	rm -f "$tmp"
	sql_exec "$sql"
}

run_stream_once() {
	local protocol source destination transfer status event_count
	event_count=0
	log "starting conntrack event stream db=$FLOW_DB"

	conntrack -E -o extended 2>>"$LOG_FILE" | parse_conntrack | while IFS='|' read -r protocol source destination transfer status; do
		insert_row_fields "$protocol" "$source" "$destination" "$transfer" "$status" || true
		event_count=$((event_count + 1))
		if [ $((event_count % 200)) -eq 0 ]; then
			prune_db || true
		fi
	done

	log "conntrack event stream ended"
}

run_once() {
	load_config
	ensure_db_file
	conntrack_source | parse_conntrack | insert_rows || true
	prune_db
}

parse_stdin() {
	load_config
	ensure_db_file
	parse_conntrack | insert_rows
	prune_db
}

run_daemon() {
	local started ended elapsed
	log "starting connection flow collector daemon"
	while true; do
		load_config
		ensure_db_file
		if command -v conntrack >/dev/null 2>&1; then
			started="$(date +%s)"
			run_stream_once || true
			ended="$(date +%s)"
			elapsed=$((ended - started))
			if [ "$elapsed" -lt 3 ]; then
				log "conntrack event stream unavailable; using one snapshot and retrying in ${POLL_SECONDS}s"
				run_once || log "collector snapshot fallback failed"
				sleep "$POLL_SECONDS"
			else
				sleep 3
			fi
		else
			log "conntrack command not found; using snapshot fallback"
			run_once || log "collector snapshot fallback failed"
			sleep "$POLL_SECONDS"
		fi
	done
}

main() {
	init_logging
	log "collector boot mode=${1:---daemon}"
	find_sqlite_bin || {
		log "sqlite3 not found; install sqlite3-cli"
		exit 1
	}
	command -v awk >/dev/null 2>&1 || {
		log "awk not found"
		exit 1
	}

	case "${1:-}" in
		--init-db)
			load_config
			log "init-db db=$FLOW_DB poll=${POLL_SECONDS}s retention=$RETENTION_ROWS"
			ensure_db_file || {
				log "init-db failed for db=$FLOW_DB"
				exit 1
			}
			log "initialized sqlite db at $FLOW_DB"
			;;
		--once)
			run_once
			;;
		--parse-stdin)
			parse_stdin
			;;
		--daemon|"")
			run_daemon
			;;
		*)
			echo "Usage: $0 [--init-db|--once|--parse-stdin|--daemon]"
			exit 1
			;;
	esac
}

main "$@"
