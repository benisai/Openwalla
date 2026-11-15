#!/bin/sh
# Optional dnsmasq reporting; SQLite is the only persisted report format.
set -u
umask 077

get() { uci -q get "$1" 2>/dev/null || true; }
fail() { echo "$*" >&2; exit 1; }
SQLITE="$(command -v sqlite3 || command -v sqlite3-cli || true)"
DB="$(get openwalla.adblock_reports.db_path)"
DB="${DB:-/tmp/openwalla/openwalla-adblock.sqlite}"
PARSER="${OPENWALLA_ADBLOCK_PARSER:-/usr/libexec/openwalla-adblock-reports.awk}"
INIT="${OPENWALLA_ADBLOCK_INIT:-/etc/init.d/openwalla-adblock-reports}"
DNSMASQ_INIT="${OPENWALLA_DNSMASQ_INIT:-/etc/init.d/dnsmasq}"
RUNTIME="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
PID_DIR="${OPENWALLA_DNSMASQ_PID_DIR:-/var/run/dnsmasq}"
LEASES="${OPENWALLA_DHCP_LEASES:-/tmp/dhcp.leases}"

number() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -gt 0 ] 2>/dev/null; }
sql() { [ -n "$SQLITE" ] || fail 'Install SQLite using the AdBlock installer.'; "$SQLITE" -batch -bail -noheader -list -separator '|' "$DB" '.timeout 5000' "$@"; }
init_db() {
	mkdir -p "$(dirname "$DB")" || return 1
	sql "PRAGMA journal_mode=WAL; PRAGMA journal_size_limit=1048576;
	CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT,timestamp INTEGER NOT NULL,client_ip TEXT NOT NULL,client_mac TEXT NOT NULL DEFAULT '',device_name TEXT NOT NULL DEFAULT '',domain TEXT NOT NULL,qtype TEXT NOT NULL,matched_rule TEXT NOT NULL,event_key TEXT NOT NULL UNIQUE);
	CREATE INDEX IF NOT EXISTS events_time ON events(timestamp);
	CREATE TABLE IF NOT EXISTS rules(domain TEXT NOT NULL,deny INTEGER NOT NULL,PRIMARY KEY(domain,deny)) WITHOUT ROWID;
	CREATE TABLE IF NOT EXISTS identities(ip TEXT PRIMARY KEY,mac TEXT NOT NULL,name TEXT NOT NULL,updated_at INTEGER NOT NULL) WITHOUT ROWID;
	CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT);" >/dev/null || return 1
	chmod 600 "$DB"
}
resolve_dnsmasq() {
	backend="$(get adblock.global.adb_dns)"
	case "$backend" in ''|dnsmasq) ;; *) fail 'Reports currently require the dnsmasq AdBlock backend.';; esac
	index="$(get adblock.global.adb_dnsinstance)"; index="${index:-0}"
	case "$index" in *[!0-9]*) fail 'Invalid dnsmasq instance';; esac
	section="$(uci -q show "dhcp.@dnsmasq[$index]" 2>/dev/null | sed -n '1s/^dhcp\.\([^=]*\)=dnsmasq$/\1/p')"
	case "$section" in ''|*[!a-zA-Z0-9_]*) fail 'Cannot identify the AdBlock dnsmasq instance.';; esac
}
check() {
	resolve_dnsmasq
	case "$(get dhcp.$section.logfacility)" in */*) fail 'Reports require dnsmasq system logging, not a custom log file.';; esac
	[ -n "$SQLITE" ] && [ -r "$PARSER" ] && [ -x "$INIT" ] || fail 'Update AdBlock in Router Setup to install SQLite reporting.'
	command -v logread >/dev/null 2>&1 || fail 'logread is required for DNS reporting.'
}
configure() (
	set -e
	wanted="$1"; case "$wanted" in 0|1) ;; *) fail 'Expected 0 or 1';; esac
	# No helper is required for normal AdBlock operation when reports were never enabled.
	active=0
	[ "$wanted" != 1 ] || [ "$(get adblock.global.adb_enabled)" != 1 ] || active=1
	if [ "$active" = 1 ]; then check; else section=''; fi
	uci -q get openwalla.adblock_reports >/dev/null || uci set openwalla.adblock_reports=adblock_reports
	owner="$(get openwalla.adblock_reports.logging_section)"
	if [ -n "$owner" ] && { [ "$active" = 0 ] || [ "$owner" != "$section" ]; }; then
		case "$owner" in *[!a-zA-Z0-9_]*) fail 'Invalid saved dnsmasq instance';; esac
		old="$(get openwalla.adblock_reports.previous_logqueries)"
		if [ "$(get dhcp.$owner.logqueries)" = 1 ] && [ "$old" != 1 ]; then
			if [ "$old" = __unset__ ]; then uci -q delete "dhcp.$owner.logqueries" || true
			else uci set "dhcp.$owner.logqueries=$old"; fi
			changed=1
		fi
		uci -q delete openwalla.adblock_reports.logging_section || true
		uci -q delete openwalla.adblock_reports.previous_logqueries || true
	fi
	if [ "$active" = 1 ]; then
		if [ "$(get openwalla.adblock_reports.logging_section)" != "$section" ]; then
			old="$(get dhcp.$section.logqueries)"; old="${old:-__unset__}"
			uci set "openwalla.adblock_reports.previous_logqueries=$old"
			uci set "openwalla.adblock_reports.logging_section=$section"
		fi
		if [ "$(get dhcp.$section.logqueries)" != 1 ]; then uci set "dhcp.$section.logqueries=1"; changed=1; fi
		"$INIT" stop
		init_db || fail 'Cannot initialize AdBlock database.'
	fi
	uci set "openwalla.adblock_reports.enabled=$wanted"
	uci commit openwalla || fail 'Cannot save report settings.'
	if [ "${changed:-0}" = 1 ]; then
		uci commit dhcp && "$DNSMASQ_INIT" restart || fail 'Could not apply DNS logging settings.'
	fi
	if [ "$active" = 1 ]; then "$INIT" enable && "$INIT" start
	else "$INIT" stop; "$INIT" disable; fi
)
snapshot_identities() {
	now="$(date +%s)"
	devices="$(get openwalla.devices.db_path)"; devices="${devices:-/tmp/openwalla/openwalla-devices.sqlite}"
	: >"$work/names"
	if [ -f "$devices" ]; then
		"$SQLITE" -batch -noheader -list -separator '|' "$devices" '.timeout 1000' "SELECT lower(mac),replace(replace(replace(hostname,'|',' '),char(10),' '),char(13),' ') FROM devices WHERE hostname<>'';" >"$work/names" 2>/dev/null || true
	fi
	{ ip -4 neigh show; ip -6 neigh show; } >"$work/neighbors" 2>/dev/null
	if [ -f "$LEASES" ]; then cp "$LEASES" "$work/leases"; else : >"$work/leases"; fi
	awk -v now="$now" '
	FILENAME==ARGV[1] {split($0,a,"|"); names[tolower(a[1])]=a[2];next}
	FILENAME==ARGV[2] {if(($1==0 || $1>now) && $2 ~ /:/) {ip=$3;mac=tolower($2);name=$4; if(name=="*")name=""; clients[ip]=mac; labels[ip]=name};next}
	{for(i=1;i<NF;i++) if($i=="lladdr" && $NF!="FAILED" && $NF!="INCOMPLETE") {ip=$1; if(!(ip in clients))clients[ip]=tolower($(i+1))}}
	END {for(ip in clients) {mac=clients[ip]; name=names[mac]; if(name=="")name=labels[ip];gsub(/[|\r\n]/," ",name);print ip "|" mac "|" name}}
	' "$work/names" "$work/leases" "$work/neighbors" >"$work/identities" 2>/dev/null
	printf '__IDENTITIES__ %s\n' "$work/identities" >&3
}
run() {
	check; init_db || exit 1
	hours="$(get openwalla.adblock_reports.retention_hours)"; number "$hours" || hours=24
	rows="$(get openwalla.adblock_reports.retention_rows)"; number "$rows" || rows=10000
	mkdir -p "$RUNTIME"
	work="$(mktemp -d "$RUNTIME/.adblock-reports.XXXXXX")" || exit 1
	cleanup() {
		trap '' TERM INT
		# Closing the log pipe lets awk commit its final batch before SQLite exits.
		[ -z "${logger_pid:-}" ] || kill "$logger_pid" 2>/dev/null || true
		[ -z "${logger_pid:-}" ] || wait "$logger_pid" 2>/dev/null || true
		exec 3>&-
		attempts=0
		while { kill -0 "${parser_pid:-0}" 2>/dev/null || kill -0 "${writer_pid:-0}" 2>/dev/null; } && [ "$attempts" -lt 3 ]; do
			sleep 1; attempts=$((attempts+1))
		done
		for pid in ${logger_pid:-} ${parser_pid:-} ${writer_pid:-}; do kill "$pid" 2>/dev/null || true; done
		for pid in ${logger_pid:-} ${parser_pid:-} ${writer_pid:-}; do wait "$pid" 2>/dev/null || true; done
		rm -rf "$work"
	}
	trap cleanup EXIT
	trap 'exit 0' TERM INT
	mkfifo "$work/log" "$work/sql" || exit 1
	"$SQLITE" -batch -bail "$DB" <"$work/sql" >/dev/null & writer_pid=$!
	awk -v retention_hours="$hours" -v retention_rows="$rows" -f "$PARSER" <"$work/log" >"$work/sql" & parser_pid=$!
	exec 3>"$work/log"
	count=0; previous=''
	while :; do
		printf '__TICK__ %s\n' "$(date +%s)" >&3
		# Track the actual process and compiled policy, including after AdBlock updates.
		resolve_dnsmasq
		# Prefer dnsmasq's own PID over a possible procd jail wrapper PID.
		pid="$(cat "$PID_DIR/dnsmasq.$section.pid" 2>/dev/null || true)"
		number "$pid" || pid="$(ubus call service list '{"name":"dnsmasq"}' 2>/dev/null | jsonfilter -e "@.dnsmasq.instances['$section'].pid" 2>/dev/null || true)"
		number "$pid" || pid=0
		printf '__PID__ %s\n' "$pid" >&3
		dir="$(get adblock.global.adb_dnsdir)"
		[ -n "$dir" ] || dir="$(get dhcp.$section.confdir)"
		dir="${dir:-/tmp/dnsmasq.$section.d}"
		policy="$dir/adb_list.overall"
		signature="$policy:$(stat -L -c '%i:%s:%Y' "$policy" 2>/dev/null || true)"
		if [ "$signature" != "$previous" ]; then printf '__POLICY__ %s\n' "$policy" >&3; previous="$signature"; fi
		if [ "$count" = 0 ]; then snapshot_identities; fi
		if [ -z "${logger_pid:-}" ]; then logread -f -l 0 -t -e dnsmasq >"$work/log" & logger_pid=$!; fi
		sleep 5
		for pid in "$writer_pid" "$parser_pid" "$logger_pid"; do kill -0 "$pid" 2>/dev/null || exit 1; done
		count=$(( (count+1)%6 ))
	done
}
query() {
	search=''; before=9223372036854775807; limit=201
	while [ "$#" -gt 0 ]; do
		[ "$#" -ge 2 ] || fail 'Missing query argument'
		case "$1" in --search) search="$2";; --before) before="$2";; --limit) limit="$2";; *) fail 'Unknown query argument';; esac
		shift 2
	done
	number "$before" && number "$limit" && [ "$limit" -le 501 ] || fail 'Invalid query bounds'
	[ "${#search}" -le 256 ] || fail 'Search is too long'
	[ -f "$DB" ] || fail 'No report database. Enable Reports after updating AdBlock in Router Setup.'
	escaped="$(printf '%s' "$search" | sed "s/'/''/g")"
	filter="instr(lower(domain||' '||client_ip||' '||client_mac||' '||device_name),lower('$escaped'))>0"
	sql "BEGIN;
	SELECT 'S',count(*),(SELECT count(*) FROM events WHERE $filter),COALESCE(min(timestamp),0),COALESCE(max(timestamp),0),COALESCE((SELECT value FROM metadata WHERE key='heartbeat'),0) FROM events;
	SELECT 'R',id,timestamp,client_ip,client_mac,replace(replace(replace(device_name,'|',' '),char(10),' '),char(13),' '),domain,qtype,matched_rule FROM events WHERE id<$before AND $filter ORDER BY id DESC LIMIT $limit;
	COMMIT;"
}
case "${1:-}" in
	init-db) init_db;;
	check) check;;
	configure) configure "${2:-}";;
	run) run;;
	query) shift; query "$@";;
	*) fail 'Usage: openwalla-adblock-reports {check|init-db|configure 0|1|run|query [--search text] [--before id] [--limit count]}';;
esac
