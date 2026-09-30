#!/bin/sh

# Openwalla Netify collector for OpenWrt.
# Captures Netify flow JSON events and stores them in a local SQLite database.

set -e

DEFAULT_HOST="127.0.0.1"
DEFAULT_PORT="7150"
DEFAULT_DB="/tmp/openwalla-netify.sqlite"
DEFAULT_FLOW_STATS_DB="/tmp/openwalla-netify-flow-stats.sqlite"
DEFAULT_RETENTION_ROWS="500000"
DEFAULT_STREAM_TIMEOUT="45"
DEFAULT_EXCLUDE_PROTOCOLS="MDNS,DNS,QUIC,DHCPv6,ICMP"
RECONNECT_DELAY="3"
LOG_FILE="/tmp/openwalla-netify-collector.log"
FLOW_STATS_WORK_DIR="/tmp/openwalla-netify-stats-work"

NETIFY_HOST="$DEFAULT_HOST"
NETIFY_PORT="$DEFAULT_PORT"
NETIFY_DB="$DEFAULT_DB"
FLOW_STATS_DB="$DEFAULT_FLOW_STATS_DB"
RETENTION_ROWS="$DEFAULT_RETENTION_ROWS"
STREAM_TIMEOUT="$DEFAULT_STREAM_TIMEOUT"
EXCLUDE_PROTOCOLS="$DEFAULT_EXCLUDE_PROTOCOLS"
FLOW_STATS_ENABLED="0"
FLOW_STATS_POLL_SECONDS="5"
FLOW_STATS_BUCKET_SECONDS="300"
FLOW_STATS_RETENTION_SECONDS="2592000"
SQLITE_BIN=""
JSHN_AVAILABLE="0"

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
	local query output rc
	query="$1"
	output="$("$SQLITE_BIN" "$NETIFY_DB" "PRAGMA busy_timeout=3000; $query" 2>&1)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "sqlite error: $output"
		return "$rc"
	fi
	return 0
}

stats_sql_exec() {
	local query output rc
	query="$1"
	output="$("$SQLITE_BIN" "$FLOW_STATS_DB" "PRAGMA busy_timeout=3000; $query" 2>&1)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "flow stats sqlite error: $output"
		return "$rc"
	fi
	return 0
}

load_config() {
	if command -v uci >/dev/null 2>&1; then
		local value

		value="$(uci -q get openwalla.collector.host 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && NETIFY_HOST="$value"

		value="$(uci -q get openwalla.collector.port 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && NETIFY_PORT="$value"

		value="$(uci -q get openwalla.collector.db_path 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && NETIFY_DB="$value"

		# Backward compatibility with older key.
		value="$(uci -q get openwalla.collector.output_file 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		if [ -n "$value" ] && [ "$NETIFY_DB" = "$DEFAULT_DB" ]; then
			case "$value" in
				*.sqlite | *.sqlite3)
					NETIFY_DB="$value"
					;;
			esac
		fi

		value="$(uci -q get openwalla.collector.retention_rows 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && RETENTION_ROWS="$value"

		# Backward compatibility with older key.
		value="$(uci -q get openwalla.collector.max_lines 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		if [ -n "$value" ] && [ "$RETENTION_ROWS" = "$DEFAULT_RETENTION_ROWS" ]; then
			RETENTION_ROWS="$value"
		fi

		value="$(uci -q get openwalla.collector.stream_timeout 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && STREAM_TIMEOUT="$value"

		value="$(uci -q get openwalla.collector.exclude_protocols 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && EXCLUDE_PROTOCOLS="$value"

		value="$(uci -q get openwalla.flow_stats.enabled 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ "$value" = "1" ] && FLOW_STATS_ENABLED="1" || FLOW_STATS_ENABLED="0"

		value="$(uci -q get openwalla.flow_stats.db_path 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && FLOW_STATS_DB="$value"

		value="$(uci -q get openwalla.flow_stats.poll 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && FLOW_STATS_POLL_SECONDS="$value"

		value="$(uci -q get openwalla.flow_stats.bucket_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && FLOW_STATS_BUCKET_SECONDS="$value"

		value="$(uci -q get openwalla.flow_stats.retention_seconds 2>/dev/null || true)"
		value="$(sanitize_text "$value")"
		[ -n "$value" ] && FLOW_STATS_RETENTION_SECONDS="$value"

	fi
}

refresh_runtime_config() {
	load_config
	RETENTION_ROWS="$(sanitize_int "$RETENTION_ROWS" "$DEFAULT_RETENTION_ROWS")"
	STREAM_TIMEOUT="$(sanitize_int "$STREAM_TIMEOUT" "$DEFAULT_STREAM_TIMEOUT")"
	FLOW_STATS_POLL_SECONDS="$(sanitize_int "$FLOW_STATS_POLL_SECONDS" "5")"
	[ "$FLOW_STATS_POLL_SECONDS" -lt 2 ] && FLOW_STATS_POLL_SECONDS=2
	[ "$FLOW_STATS_POLL_SECONDS" -gt 10 ] && FLOW_STATS_POLL_SECONDS=10
	ensure_db_file
}

require_dependencies() {
	command -v nc >/dev/null 2>&1 || {
		log "nc not found; install netcat"
		exit 1
	}
	find_sqlite_bin || {
		log "sqlite3 not found; install sqlite3-cli"
		exit 1
	}
	if [ -r /usr/share/libubox/jshn.sh ]; then
		. /usr/share/libubox/jshn.sh
		JSHN_AVAILABLE="1"
	fi
}

ensure_db_file() {
	local dir
	dir="$(dirname "$NETIFY_DB")"
	mkdir -p "$dir"
	[ -f "$NETIFY_DB" ] || : >"$NETIFY_DB"
	init_db
}

init_db() {
	sql_exec "PRAGMA journal_mode=WAL;"
	sql_exec "CREATE TABLE IF NOT EXISTS flow_raw (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timeinsert INTEGER NOT NULL DEFAULT (strftime('%s','now')),
		local_ip TEXT NOT NULL DEFAULT '',
		local_mac TEXT NOT NULL DEFAULT '',
		fqdn TEXT NOT NULL DEFAULT '',
		dest_ip TEXT NOT NULL DEFAULT '',
		dest_port INTEGER NOT NULL DEFAULT 0,
		dest_type TEXT NOT NULL DEFAULT 'remote',
		detected_protocol_name TEXT NOT NULL DEFAULT '',
		detected_app_name TEXT NOT NULL DEFAULT '',
		interface TEXT NOT NULL DEFAULT '',
		internal INTEGER NOT NULL DEFAULT 0,
		ndpi_risk_score INTEGER NOT NULL DEFAULT 0,
		ndpi_risk_score_client INTEGER NOT NULL DEFAULT 0,
		ndpi_risk_score_server INTEGER NOT NULL DEFAULT 0,
		client_sni TEXT NOT NULL DEFAULT '',
		category_application INTEGER NOT NULL DEFAULT 0,
		category_domain INTEGER NOT NULL DEFAULT 0,
		category_protocol INTEGER NOT NULL DEFAULT 0,
		detected_application INTEGER NOT NULL DEFAULT 0,
		detected_protocol INTEGER NOT NULL DEFAULT 0,
		detection_guessed INTEGER NOT NULL DEFAULT 0,
		dns_host_name TEXT NOT NULL DEFAULT '',
		host_server_name TEXT NOT NULL DEFAULT '',
		digest TEXT NOT NULL DEFAULT '',
		json TEXT NOT NULL
	);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_raw_time ON flow_raw(timeinsert);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_raw_mac_time ON flow_raw(local_mac, timeinsert DESC);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_raw_ip_time ON flow_raw(local_ip, timeinsert DESC);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_raw_app_time ON flow_raw(detected_app_name, timeinsert DESC);"
	if [ "$FLOW_STATS_ENABLED" = "1" ]; then
		flow_stats_init_db
	fi
}

prune_db() {
	local keep
	keep="$(sanitize_int "$RETENTION_ROWS" "$DEFAULT_RETENTION_ROWS")"
	sql_exec "DELETE FROM flow_raw
		WHERE id <= (
			SELECT CASE
				WHEN MAX(id) > $keep THEN MAX(id) - $keep
				ELSE 0
			END
			FROM flow_raw
		);"
}

is_flow_event() {
	echo "$1" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"flow"'
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

normalize_protocol() {
	printf "%s" "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9'
}

extract_protocol_name() {
	printf "%s\n" "$1" | sed -n 's/.*"detected_protocol_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

extract_client_sni() {
	printf "%s\n" "$1" | sed -n 's/.*"client_sni"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

extract_json_string() {
	printf "%s\n" "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

extract_json_number() {
	printf "%s\n" "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1
}

extract_json_bool() {
	local value
	value="$(printf "%s\n" "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p" | head -n 1)"
	case "$value" in true | false | 1 | 0) printf "%s" "$value" ;; esac
}

upsert_flow_label() {
	[ "$FLOW_STATS_ENABLED" = "1" ] || return 0
	local line ip_protocol protocol local_ip other_ip local_port other_port application destination key
	line="$1"
	ip_protocol="$(extract_json_number "$line" ip_protocol)"
	case "$ip_protocol" in 6) protocol="tcp" ;; 17) protocol="udp" ;; *) return 0 ;; esac
	local_ip="$(extract_json_string "$line" local_ip)"
	other_ip="$(extract_json_string "$line" other_ip)"
	local_port="$(extract_json_number "$line" local_port)"
	other_port="$(extract_json_number "$line" other_port)"
	case "$local_ip" in *:*) return 0 ;; esac
	case "$other_ip" in *:*) return 0 ;; esac
	[ -n "$local_ip" ] && [ -n "$other_ip" ] && [ -n "$local_port" ] && [ -n "$other_port" ] || return 0
	application="$(extract_json_string "$line" detected_application_name)"
	[ -n "$application" ] || application="$(extract_json_string "$line" detected_protocol_name)"
	[ -n "$application" ] || application="Unknown"
	destination="$(extract_json_string "$line" client_sni)"
	[ -n "$destination" ] || destination="$(extract_json_string "$line" host_server_name)"
	[ -n "$destination" ] || destination="$(extract_json_string "$line" dns_host_name)"
	[ -n "$destination" ] || destination="$other_ip"
	key="$protocol|$local_ip|$other_ip|$local_port|$other_port"
	stats_sql_exec "INSERT INTO flow_stats_labels(flow_key,application,destination,updated_at) VALUES ('$(sql_escape "$key")','$(sql_escape "$application")','$(sql_escape "$destination")',strftime('%s','now')) ON CONFLICT(flow_key) DO UPDATE SET application=excluded.application,destination=excluded.destination,updated_at=excluded.updated_at;"
}

flow_stats_init_db() {
	mkdir -p "$(dirname "$FLOW_STATS_DB")"
	[ -f "$FLOW_STATS_DB" ] || : >"$FLOW_STATS_DB"
	stats_sql_exec "CREATE TABLE IF NOT EXISTS flow_stats_labels (
		flow_key TEXT PRIMARY KEY,
		application TEXT NOT NULL DEFAULT 'Unknown',
		destination TEXT NOT NULL DEFAULT '',
		updated_at INTEGER NOT NULL
	);"
	stats_sql_exec "CREATE TABLE IF NOT EXISTS flow_stats_state (
		flow_key TEXT PRIMARY KEY,
		rx_bytes INTEGER NOT NULL,
		tx_bytes INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	);"
	stats_sql_exec "CREATE TABLE IF NOT EXISTS flow_stats_5m (
		bucket_start INTEGER NOT NULL,
		mac TEXT NOT NULL,
		application TEXT NOT NULL,
		destination TEXT NOT NULL,
		rx_bytes INTEGER NOT NULL DEFAULT 0,
		tx_bytes INTEGER NOT NULL DEFAULT 0,
		updated_at INTEGER NOT NULL,
		PRIMARY KEY (bucket_start, mac, application, destination)
	);"
	stats_sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_stats_5m_mac_bucket ON flow_stats_5m(mac, bucket_start DESC);"
	stats_sql_exec "CREATE TABLE IF NOT EXISTS flow_stats_totals (
		mac TEXT NOT NULL,
		application TEXT NOT NULL,
		destination TEXT NOT NULL,
		rx_bytes INTEGER NOT NULL DEFAULT 0,
		tx_bytes INTEGER NOT NULL DEFAULT 0,
		updated_at INTEGER NOT NULL,
		PRIMARY KEY (mac, application, destination)
	);"
	stats_sql_exec "CREATE INDEX IF NOT EXISTS idx_flow_stats_totals_mac ON flow_stats_totals(mac);"
}

flow_stats_conntrack_snapshot() {
	if [ -r /proc/net/nf_conntrack ]; then
		cat /proc/net/nf_conntrack
	elif command -v conntrack >/dev/null 2>&1; then
		conntrack -L -o extended 2>/dev/null
	fi | awk '
	function private4(ip, a) {
		split(ip, a, ".")
		return a[1] == 10 || (a[1] == 172 && a[2] >= 16 && a[2] <= 31) || (a[1] == 192 && a[2] == 168)
	}
	function ipv4(ip) { return ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ }
	{
		proto=""; src1=""; dst1=""; sp1=""; dp1=""; b1=""; src2=""; dst2=""; b2=""
		for (i=1; i<=NF; i++) {
			if (proto == "" && ($i == "tcp" || $i == "udp")) proto=$i
			if ($i ~ /^src=/) { if (src1 == "") src1=substr($i,5); else if (src2 == "") src2=substr($i,5) }
			else if ($i ~ /^dst=/) { if (dst1 == "") dst1=substr($i,5); else if (dst2 == "") dst2=substr($i,5) }
			else if ($i ~ /^sport=/) { if (sp1 == "") sp1=substr($i,7) }
			else if ($i ~ /^dport=/) { if (dp1 == "") dp1=substr($i,7) }
			else if ($i ~ /^bytes=/) { if (b1 == "") b1=substr($i,7)+0; else if (b2 == "") b2=substr($i,7)+0 }
		}
		if (proto == "" || !ipv4(src1) || !ipv4(dst1) || !private4(src1) || private4(dst1)) next
		if (sp1 == "" || dp1 == "" || b1 == "" || b2 == "") next
		print proto "|" src1 "|" dst1 "|" sp1 "|" dp1 "\t" src1 "\t" dst1 "\t" b2 "\t" b1
	}'
}

flow_stats_write_neighbors() {
	ip neigh show 2>/dev/null | awk '
	$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
		for (i=2; i<NF; i++) if ($i == "lladdr") print $1 "\t" tolower($(i+1))
	}' | sort -u
}

flow_stats_collect_once() {
	local dir now bucket cutoff
	dir="$FLOW_STATS_WORK_DIR.$$"
	mkdir -p "$dir"
	now="$(date +%s)"
	bucket=$((now - (now % FLOW_STATS_BUCKET_SECONDS)))
	cutoff=$((now - FLOW_STATS_RETENTION_SECONDS))

	flow_stats_conntrack_snapshot >"$dir/current"
	flow_stats_write_neighbors >"$dir/neighbors"
	"$SQLITE_BIN" -separator "$(printf '\t')" -cmd ".timeout 3000" "$FLOW_STATS_DB" \
		"SELECT flow_key,rx_bytes,tx_bytes FROM flow_stats_state;" >"$dir/state"
	"$SQLITE_BIN" -separator "$(printf '\t')" -cmd ".timeout 3000" "$FLOW_STATS_DB" \
		"SELECT flow_key,application,destination FROM flow_stats_labels WHERE updated_at >= $((now - 600));" >"$dir/labels"

	awk -F '\t' -v now="$now" -v bucket="$bucket" \
		-v state_file="$dir/state" -v labels_file="$dir/labels" -v neighbors_file="$dir/neighbors" '
	function q(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
	BEGIN {
		while ((getline < state_file) > 0) { state_rx[$1]=$2+0; state_tx[$1]=$3+0 }
		close(state_file)
		while ((getline < labels_file) > 0) { label_app[$1]=$2; label_dst[$1]=$3 }
		close(labels_file)
		while ((getline < neighbors_file) > 0) ip_mac[$1]=$2
		close(neighbors_file)
		print "BEGIN IMMEDIATE;"
	}
	{
		key=$1; ip=$2; remote=$3; rx=$4+0; tx=$5+0
		drx=(key in state_rx) ? rx-state_rx[key] : 0
		dtx=(key in state_tx) ? tx-state_tx[key] : 0
		if (drx < 0) drx=0
		if (dtx < 0) dtx=0
		print "INSERT INTO flow_stats_state(flow_key,rx_bytes,tx_bytes,updated_at) VALUES(" q(key) "," rx "," tx "," now ") ON CONFLICT(flow_key) DO UPDATE SET rx_bytes=excluded.rx_bytes,tx_bytes=excluded.tx_bytes,updated_at=excluded.updated_at;"
		if (drx == 0 && dtx == 0) next
		mac=(ip in ip_mac) ? ip_mac[ip] : ip
		app=(key in label_app && label_app[key] != "") ? label_app[key] : "Unknown"
		dst=(key in label_dst && label_dst[key] != "") ? label_dst[key] : remote
		print "INSERT INTO flow_stats_5m(bucket_start,mac,application,destination,rx_bytes,tx_bytes,updated_at) VALUES(" bucket "," q(mac) "," q(app) "," q(dst) "," drx "," dtx "," now ") ON CONFLICT(bucket_start,mac,application,destination) DO UPDATE SET rx_bytes=rx_bytes+excluded.rx_bytes,tx_bytes=tx_bytes+excluded.tx_bytes,updated_at=excluded.updated_at;"
		print "INSERT INTO flow_stats_totals(mac,application,destination,rx_bytes,tx_bytes,updated_at) VALUES(" q(mac) "," q(app) "," q(dst) "," drx "," dtx "," now ") ON CONFLICT(mac,application,destination) DO UPDATE SET rx_bytes=rx_bytes+excluded.rx_bytes,tx_bytes=tx_bytes+excluded.tx_bytes,updated_at=excluded.updated_at;"
	}
	END {
		print "DELETE FROM flow_stats_state WHERE updated_at < " (now-300) ";"
		print "COMMIT;"
	}' "$dir/current" >"$dir/update.sql"

	"$SQLITE_BIN" -cmd ".timeout 3000" "$FLOW_STATS_DB" <"$dir/update.sql"
	stats_sql_exec "DELETE FROM flow_stats_5m WHERE bucket_start < $cutoff; DELETE FROM flow_stats_labels WHERE updated_at < $((now - 3600));"
	rm -rf "$dir"
}

flow_stats_loop() {
	flow_stats_init_db
	while true; do
		flow_stats_collect_once || true
		sleep "$FLOW_STATS_POLL_SECONDS" &
		wait $!
	done
}

escape_sed_replacement() {
	printf "%s" "$1" | sed 's/[\/&]/\\&/g'
}

prefer_client_sni() {
	local line sni replacement
	line="$1"
	sni="$(extract_client_sni "$line")"
	[ -n "$sni" ] || {
		printf "%s" "$line"
		return
	}
	replacement="$(escape_sed_replacement "$sni")"
	if printf "%s\n" "$line" | grep -q '"host_server_name"[[:space:]]*:'; then
		printf "%s" "$line" | sed "s/\"host_server_name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"host_server_name\":\"$replacement\"/"
		return
	fi
	if printf "%s\n" "$line" | grep -q '"fqdn"[[:space:]]*:'; then
		printf "%s" "$line" | sed "s/\"fqdn\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"fqdn\":\"$replacement\"/"
		return
	fi
	printf "%s" "$line"
}

should_skip_protocol() {
	local line proto token normalized_proto normalized_token old_ifs
	line="$1"
	proto="$(extract_protocol_name "$line")"
	[ -n "$proto" ] || return 1

	normalized_proto="$(normalize_protocol "$proto")"
	[ -n "$normalized_proto" ] || return 1

	old_ifs="$IFS"
	IFS=','
	for token in $EXCLUDE_PROTOCOLS; do
		token="$(sanitize_text "$token")"
		token="$(printf "%s" "$token" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
		[ -n "$token" ] || continue
		normalized_token="$(normalize_protocol "$token")"
		[ -n "$normalized_token" ] || continue
		case "$normalized_proto" in
			"$normalized_token"|"$normalized_token"*)
				IFS="$old_ifs"
				return 0
				;;
		esac
	done
	IFS="$old_ifs"
	return 1
}

bool_to_int() {
	case "${1:-}" in
		1 | true | yes | on) echo 1 ;;
		*) echo 0 ;;
	esac
}

parse_flow_columns() {
	local line
	line="$1"
	local_ip=""
	local_mac=""
	fqdn=""
	dest_ip=""
	dest_port="0"
	detected_protocol_name=""
	detected_app_name=""
	flow_interface=""
	internal="0"
	ndpi_risk_score="0"
	ndpi_risk_score_client="0"
	ndpi_risk_score_server="0"
	client_sni=""
	category_application="0"
	category_domain="0"
	category_protocol="0"
	detected_application="0"
	detected_protocol="0"
	detection_guessed="0"
	dns_host_name=""
	host_server_name=""
	digest=""

	if [ "$JSHN_AVAILABLE" = "1" ]; then
		json_load "$line" || return 1
		json_get_var flow_interface interface
		json_get_var internal internal
		json_select flow || return 1
		json_get_var local_ip local_ip
		json_get_var local_mac local_mac
		json_get_var fqdn fqdn
		json_get_var dest_ip other_ip
		json_get_var dest_port other_port
		json_get_var detected_protocol_name detected_protocol_name
		json_get_var detected_app_name detected_application_name
		[ -n "$detected_app_name" ] || json_get_var detected_app_name detected_app_name
		json_get_var detected_application detected_application
		json_get_var detected_protocol detected_protocol
		json_get_var detection_guessed detection_guessed
		json_get_var dns_host_name dns_host_name
		json_get_var host_server_name host_server_name
		json_get_var digest digest
		if json_select risks 2>/dev/null; then
			json_get_var ndpi_risk_score ndpi_risk_score
			json_get_var ndpi_risk_score_client ndpi_risk_score_client
			json_get_var ndpi_risk_score_server ndpi_risk_score_server
			json_select ..
		fi
		if json_select ssl 2>/dev/null; then
			json_get_var client_sni client_sni
			json_select ..
		fi
		if json_select category 2>/dev/null; then
			json_get_var category_application application
			json_get_var category_domain domain
			json_get_var category_protocol protocol
			json_select ..
		fi
	else
		local_ip="$(extract_json_string "$line" local_ip)"
		local_mac="$(extract_json_string "$line" local_mac)"
		fqdn="$(extract_json_string "$line" fqdn)"
		dest_ip="$(extract_json_string "$line" other_ip)"
		dest_port="$(extract_json_number "$line" other_port)"
		detected_protocol_name="$(extract_json_string "$line" detected_protocol_name)"
		detected_app_name="$(extract_json_string "$line" detected_application_name)"
		flow_interface="$(extract_json_string "$line" interface)"
		internal="$(extract_json_bool "$line" internal)"
		ndpi_risk_score="$(extract_json_number "$line" ndpi_risk_score)"
		ndpi_risk_score_client="$(extract_json_number "$line" ndpi_risk_score_client)"
		ndpi_risk_score_server="$(extract_json_number "$line" ndpi_risk_score_server)"
		client_sni="$(extract_json_string "$line" client_sni)"
		detected_application="$(extract_json_number "$line" detected_application)"
		detected_protocol="$(extract_json_number "$line" detected_protocol)"
		detection_guessed="$(extract_json_bool "$line" detection_guessed)"
		dns_host_name="$(extract_json_string "$line" dns_host_name)"
		host_server_name="$(extract_json_string "$line" host_server_name)"
		digest="$(extract_json_string "$line" digest)"
	fi

	[ -n "$fqdn" ] || fqdn="$client_sni"
	[ -n "$fqdn" ] || fqdn="$host_server_name"
	[ -n "$fqdn" ] || fqdn="$dns_host_name"
	[ -n "$fqdn" ] || fqdn="$dest_ip"
	dest_port="$(sanitize_int "$dest_port" 0)"
	internal="$(bool_to_int "$internal")"
	detection_guessed="$(bool_to_int "$detection_guessed")"
	ndpi_risk_score="$(sanitize_int "$ndpi_risk_score" 0)"
	ndpi_risk_score_client="$(sanitize_int "$ndpi_risk_score_client" 0)"
	ndpi_risk_score_server="$(sanitize_int "$ndpi_risk_score_server" 0)"
	category_application="$(sanitize_int "$category_application" 0)"
	category_domain="$(sanitize_int "$category_domain" 0)"
	category_protocol="$(sanitize_int "$category_protocol" 0)"
	detected_application="$(sanitize_int "$detected_application" 0)"
	detected_protocol="$(sanitize_int "$detected_protocol" 0)"
}

insert_flow() {
	local line escaped
	line="$1"
	parse_flow_columns "$line" || return 1
	escaped="$(sql_escape "$line")"
	sql_exec "INSERT INTO flow_raw(
		timeinsert,local_ip,local_mac,fqdn,dest_ip,dest_port,dest_type,
		detected_protocol_name,detected_app_name,interface,internal,
		ndpi_risk_score,ndpi_risk_score_client,ndpi_risk_score_server,
		client_sni,category_application,category_domain,category_protocol,
		detected_application,detected_protocol,detection_guessed,dns_host_name,
		host_server_name,digest,json
	) VALUES (
		strftime('%s','now'),'$(sql_escape "$local_ip")','$(sql_escape "$local_mac")',
		'$(sql_escape "$fqdn")','$(sql_escape "$dest_ip")',$dest_port,'remote',
		'$(sql_escape "$detected_protocol_name")','$(sql_escape "$detected_app_name")',
		'$(sql_escape "$flow_interface")',$internal,$ndpi_risk_score,
		$ndpi_risk_score_client,$ndpi_risk_score_server,'$(sql_escape "$client_sni")',
		$category_application,$category_domain,$category_protocol,$detected_application,
		$detected_protocol,$detection_guessed,'$(sql_escape "$dns_host_name")',
		'$(sql_escape "$host_server_name")','$(sql_escape "$digest")','$escaped'
	);"
}

consume_stream() {
	local line counter
	counter=0

	nc -w "$STREAM_TIMEOUT" "$NETIFY_HOST" "$NETIFY_PORT" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		if ! is_flow_event "$line"; then
			continue
		fi
		upsert_flow_label "$line" || true
		if should_skip_protocol "$line"; then
			continue
		fi

		insert_flow "$line" || continue
		counter=$((counter + 1))
		if [ $((counter % 200)) -eq 0 ]; then
			prune_db || true
		fi
	done
}

run_forever() {
	refresh_runtime_config
	local stats_pid
	stats_pid=""
	if [ "$FLOW_STATS_ENABLED" = "1" ]; then
		flow_stats_loop &
		stats_pid=$!
		trap '[ -n "$stats_pid" ] && kill "$stats_pid" 2>/dev/null || true; rm -rf "$FLOW_STATS_WORK_DIR.$$"; exit 0' INT TERM EXIT
	fi
	log "starting netify collector host=$NETIFY_HOST port=$NETIFY_PORT db=$NETIFY_DB timeout=${STREAM_TIMEOUT}s flow_stats=$FLOW_STATS_ENABLED flow_stats_db=$FLOW_STATS_DB"
	while true; do
		refresh_runtime_config
		log "connecting to netify stream at $NETIFY_HOST:$NETIFY_PORT"
		consume_stream || true
		log "stream disconnected; retrying in ${RECONNECT_DELAY}s"
		sleep "$RECONNECT_DELAY"
	done
}

main() {
	init_logging
	require_dependencies
	refresh_runtime_config

	case "${1:-}" in
		--init-db | --init-file)
			log "netify sqlite database initialized at $NETIFY_DB"
			exit 0
			;;
	esac

	run_forever
}

if [ "${OPENWALLA_NETIFY_COLLECTOR_SOURCE_ONLY:-0}" != "1" ]; then
	main "$@"
fi
