#!/bin/sh

# Openwalla scheduler helper for OpenWrt.
# Stores device groups and daily internet block schedules in the devices DB,
# applies active schedules as firewall reject rules, and marks matching devices
# with status='block-scheduled' while the schedule is active.

mkdir -p /tmp/openwalla

DEFAULT_DB="/tmp/openwalla/openwalla-devices.sqlite"
DEFAULT_RULE_PREFIX="openwalla_schedule_"

uci_get() {
	uci -q get "$1" 2>/dev/null || true
}

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

sqlite_bin() {
	if command -v sqlite3 >/dev/null 2>&1; then
		echo sqlite3
		return 0
	fi
	if command -v sqlite3-cli >/dev/null 2>&1; then
		echo sqlite3-cli
		return 0
	fi
	return 1
}

db_path() {
	path="$(uci_get openwalla.devices.db_path)"
	[ -n "$path" ] || path="$DEFAULT_DB"
	echo "$path"
}

rule_prefix() {
	prefix="$(uci_get openwalla.scheduler.rule_prefix)"
	[ -n "$prefix" ] || prefix="$DEFAULT_RULE_PREFIX"
	echo "$prefix"
}

normalize_mac() {
	printf "%s" "$1" | tr '[:lower:]' '[:upper:]' | tr '-' ':'
}

mac_rule_suffix() {
	printf "%s" "$1" | tr '[:upper:]:' '[:lower:]_'
}

is_valid_mac() {
	printf "%s" "$1" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
}

is_number() {
	case "$1" in
	""|*[!0-9]*) return 1 ;;
	*) return 0 ;;
	esac
}

to_minutes() {
	value="$1"
	hour="${value%%:*}"
	minute="${value#*:}"
	case "$hour:$minute" in
	[0-2][0-9]:[0-5][0-9]) ;;
	*) echo -1; return ;;
	esac
	hour="$(printf "%s" "$hour" | sed 's/^0*//')"
	minute="$(printf "%s" "$minute" | sed 's/^0*//')"
	[ -n "$hour" ] || hour=0
	[ -n "$minute" ] || minute=0
	if [ "$hour" -gt 23 ]; then
		echo -1
		return
	fi
	echo $((hour * 60 + minute))
}

time_is_active() {
	start="$(to_minutes "$1")"
	end="$(to_minutes "$2")"
	now_min="$(date +%H:%M)"
	now_min="$(to_minutes "$now_min")"
	[ "$start" -ge 0 ] && [ "$end" -ge 0 ] || return 1
	if [ "$start" -eq "$end" ]; then
		return 0
	fi
	if [ "$start" -lt "$end" ]; then
		[ "$now_min" -ge "$start" ] && [ "$now_min" -lt "$end" ]
	else
		[ "$now_min" -ge "$start" ] || [ "$now_min" -lt "$end" ]
	fi
}

sql_exec() {
	SQLITE="$(sqlite_bin)" || {
		echo "sqlite3/sqlite3-cli not installed" >&2
		return 127
	}
	"$SQLITE" "$(db_path)" "$1"
}

init_db() {
	sql_exec "PRAGMA journal_mode=WAL;" >/dev/null 2>&1 || true
	sql_exec "CREATE TABLE IF NOT EXISTS devices (mac TEXT PRIMARY KEY, ip TEXT NOT NULL DEFAULT '', hostname TEXT NOT NULL DEFAULT '', vendor TEXT NOT NULL DEFAULT '', quarantined INTEGER NOT NULL DEFAULT 0, last_seen INTEGER NOT NULL DEFAULT 0, total_up INTEGER NOT NULL DEFAULT 0, total_down INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'offline', static_ip TEXT NOT NULL DEFAULT '', icon TEXT NOT NULL DEFAULT '', scheduled_block INTEGER NOT NULL DEFAULT 0, schedule_until TEXT NOT NULL DEFAULT '');"
	sql_exec "ALTER TABLE devices ADD COLUMN scheduled_block INTEGER NOT NULL DEFAULT 0;" 2>/dev/null || true
	sql_exec "ALTER TABLE devices ADD COLUMN schedule_until TEXT NOT NULL DEFAULT '';" 2>/dev/null || true
	sql_exec "CREATE TABLE IF NOT EXISTS schedule_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL DEFAULT 'Kids');"
	sql_exec "CREATE TABLE IF NOT EXISTS schedule_members (group_id INTEGER NOT NULL, mac TEXT NOT NULL, PRIMARY KEY(group_id, mac));"
	sql_exec "CREATE TABLE IF NOT EXISTS schedules (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL, start_time TEXT NOT NULL DEFAULT '21:00', end_time TEXT NOT NULL DEFAULT '07:00', enabled INTEGER NOT NULL DEFAULT 1);"
	sql_exec "CREATE TABLE IF NOT EXISTS schedule_pauses (group_id INTEGER PRIMARY KEY, pause_until INTEGER NOT NULL DEFAULT 0);"
	sql_exec "CREATE TABLE IF NOT EXISTS schedule_activity (id INTEGER PRIMARY KEY AUTOINCREMENT, group_name TEXT NOT NULL DEFAULT '', action TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_schedule_members_mac ON schedule_members(mac);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_schedules_group ON schedules(group_id);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_schedule_pauses_until ON schedule_pauses(pause_until);"
	sql_exec "CREATE INDEX IF NOT EXISTS idx_schedule_activity_created ON schedule_activity(created_at DESC);"
}

log_activity() {
	name="$(sql_escape "$1")"
	action="$(sql_escape "$2")"
	detail="$(sql_escape "$3")"
	sql_exec "INSERT INTO schedule_activity (group_name, action, detail, created_at) VALUES ('$name', '$action', '$detail', $(date +%s)); DELETE FROM schedule_activity WHERE id NOT IN (SELECT id FROM schedule_activity ORDER BY created_at DESC, id DESC LIMIT 100);" >/dev/null 2>&1 || true
}

list_activity() {
	init_db || return 1
	sql_exec "SELECT group_name, action, detail, created_at FROM schedule_activity ORDER BY created_at DESC, id DESC LIMIT 100;"
}

clear_activity() {
	init_db || return 1
	sql_exec "DELETE FROM schedule_activity;"
}

list_schedules() {
	init_db || return 1
	current="$(date +%s)"
	sql_exec "DELETE FROM schedule_pauses WHERE pause_until <= $current;" >/dev/null 2>&1 || true
	sql_exec "SELECT g.id, g.name, COALESCE(s.start_time,''), COALESCE(s.end_time,''), COALESCE(s.enabled,0), COALESCE(group_concat(m.mac, ','), ''), COALESCE(p.pause_until,0) FROM schedule_groups g LEFT JOIN schedules s ON s.group_id = g.id LEFT JOIN schedule_members m ON m.group_id = g.id LEFT JOIN schedule_pauses p ON p.group_id = g.id GROUP BY g.id ORDER BY lower(g.name);"
}

active_for_mac() {
	init_db || return 1
	current="$(date +%s)"
	sql_exec "DELETE FROM schedule_pauses WHERE pause_until <= $current;" >/dev/null 2>&1 || true
	mac="$(normalize_mac "$1")"
	esc_mac="$(sql_escape "$mac")"
	sql_exec "SELECT g.name, s.start_time, s.end_time, COALESCE(p.pause_until,0) FROM schedules s JOIN schedule_groups g ON g.id = s.group_id JOIN schedule_members m ON m.group_id = g.id LEFT JOIN schedule_pauses p ON p.group_id = g.id WHERE s.enabled = 1 AND upper(m.mac) = '$esc_mac';" |
	while IFS='|' read -r name start_time end_time pause_until; do
		[ -n "$name" ] || continue
		is_number "$pause_until" || pause_until=0
		[ "$pause_until" -gt "$current" ] && continue
		if time_is_active "$start_time" "$end_time"; then
			printf "%s|%s\n" "$name" "$end_time"
			break
		fi
	done
}

save_schedule() {
	init_db || return 1
	id="$1"
	is_new=0
	name="$2"
	start_time="$3"
	end_time="$4"
	enabled="$5"
	shift 5

	start_minutes="$(to_minutes "$start_time")"
	end_minutes="$(to_minutes "$end_time")"
	[ "$start_minutes" -ge 0 ] && [ "$end_minutes" -ge 0 ] || {
		echo "invalid schedule time" >&2
		return 1
	}
	case "$enabled" in 1|true|yes|on) enabled=1 ;; *) enabled=0 ;; esac
	esc_name="$(sql_escape "$name")"

	if [ "$id" = "new" ] || [ -z "$id" ] || [ "$id" = "0" ]; then
		is_new=1
		id="$(sql_exec "INSERT INTO schedule_groups (name) VALUES ('$esc_name'); SELECT last_insert_rowid();")"
	else
		sql_exec "UPDATE schedule_groups SET name='$esc_name' WHERE id=$id;"
	fi

	sql_exec "DELETE FROM schedule_members WHERE group_id=$id;"
	sql_exec "DELETE FROM schedules WHERE group_id=$id;"
	sql_exec "INSERT INTO schedules (group_id, start_time, end_time, enabled) VALUES ($id, '$start_time', '$end_time', $enabled);"

	for raw_mac in "$@"; do
		mac="$(normalize_mac "$raw_mac")"
		is_valid_mac "$mac" || continue
		esc_mac="$(sql_escape "$mac")"
		sql_exec "INSERT OR IGNORE INTO schedule_members (group_id, mac) VALUES ($id, '$esc_mac');"
	done

	if [ "$is_new" -eq 1 ]; then
		log_activity "$name" "Profile Created" "Block schedule $start_time-$end_time"
	else
		log_activity "$name" "Profile Updated" "Block schedule $start_time-$end_time"
	fi
	apply_schedules >/dev/null 2>&1 || true
	echo "$id"
}

delete_schedule() {
	init_db || return 1
	id="$1"
	name="$(sql_exec "SELECT name FROM schedule_groups WHERE id=$id LIMIT 1;")"
	sql_exec "DELETE FROM schedule_members WHERE group_id=$id;"
	sql_exec "DELETE FROM schedules WHERE group_id=$id;"
	sql_exec "DELETE FROM schedule_pauses WHERE group_id=$id;"
	sql_exec "DELETE FROM schedule_groups WHERE id=$id;"
	log_activity "$name" "Profile Deleted" ""
	apply_schedules >/dev/null 2>&1 || true
}

pause_schedule() {
	init_db || return 1
	id="$1"
	minutes="$2"
	is_number "$id" || {
		echo "invalid schedule id" >&2
		return 1
	}
	is_number "$minutes" || {
		echo "invalid pause minutes" >&2
		return 1
	}
	[ "$minutes" -gt 0 ] || {
		echo "pause minutes must be greater than 0" >&2
		return 1
	}
	pause_until=$(($(date +%s) + minutes * 60))
	name="$(sql_exec "SELECT name FROM schedule_groups WHERE id=$id LIMIT 1;")"
	sql_exec "INSERT INTO schedule_pauses (group_id, pause_until) VALUES ($id, $pause_until) ON CONFLICT(group_id) DO UPDATE SET pause_until=excluded.pause_until;"
	apply_schedules >/dev/null 2>&1 || true
	log_activity "$name" "Schedule Paused" "$minutes minutes"
	echo "$pause_until"
}

resume_schedule() {
	init_db || return 1
	id="$1"
	is_number "$id" || {
		echo "invalid schedule id" >&2
		return 1
	}
	name="$(sql_exec "SELECT name FROM schedule_groups WHERE id=$id LIMIT 1;")"
	sql_exec "DELETE FROM schedule_pauses WHERE group_id=$id;"
	apply_schedules >/dev/null 2>&1 || true
	log_activity "$name" "Schedule Resumed" ""
}

remove_schedule_firewall_rules() {
	prefix="$(rule_prefix)"
	for section in $(uci -q show firewall 2>/dev/null | sed -n "s/^firewall\.\([^.=]*\)\.name=['\"]\{0,1\}${prefix}.*/\1/p"); do
		uci -q delete "firewall.$section" 2>/dev/null || true
	done
}

add_schedule_rule() {
	mac="$1"
	name="$2"
	prefix="$(rule_prefix)"
	suffix="$(mac_rule_suffix "$mac")"
	section="$(uci add firewall rule 2>/dev/null || true)"
	[ -n "$section" ] || return 1
	uci set "firewall.$section.name=${prefix}${suffix}"
	uci set "firewall.$section.src=lan"
	uci set "firewall.$section.dest=wan"
	uci set "firewall.$section.src_mac=$mac"
	uci set "firewall.$section.proto=all"
	uci set "firewall.$section.target=REJECT"
	uci set "firewall.$section.family=any"
	uci set "firewall.$section.enabled=1"
}

apply_schedules() {
	init_db || return 1
	current="$(date +%s)"
	sql_exec "DELETE FROM schedule_pauses WHERE pause_until <= $current;" >/dev/null 2>&1 || true
	active="/tmp/openwalla/.openwalla-schedule-active.$$"
	: >"$active"
	sql_exec "SELECT g.name, s.start_time, s.end_time, m.mac, COALESCE(p.pause_until,0) FROM schedules s JOIN schedule_groups g ON g.id = s.group_id JOIN schedule_members m ON m.group_id = g.id LEFT JOIN schedule_pauses p ON p.group_id = g.id WHERE s.enabled = 1;" |
	while IFS='|' read -r name start_time end_time mac pause_until; do
		[ -n "$mac" ] || continue
		is_number "$pause_until" || pause_until=0
		[ "$pause_until" -gt "$current" ] && continue
		if time_is_active "$start_time" "$end_time"; then
			printf "%s|%s|%s\n" "$(normalize_mac "$mac")" "$name" "$end_time" >>"$active"
		fi
	done

	remove_schedule_firewall_rules
	sql_exec "UPDATE devices SET scheduled_block=0, schedule_until='', status=CASE WHEN status='block-scheduled' AND quarantined=0 THEN 'online' ELSE status END;"

	while IFS='|' read -r mac name end_time; do
		[ -n "$mac" ] || continue
		add_schedule_rule "$mac" "$name" || true
		esc_mac="$(sql_escape "$mac")"
		esc_end="$(sql_escape "$end_time")"
		sql_exec "INSERT INTO devices (mac, status, scheduled_block, schedule_until, last_seen) VALUES ('$esc_mac', 'block-scheduled', 1, '$esc_end', strftime('%s','now')) ON CONFLICT(mac) DO UPDATE SET scheduled_block=1, schedule_until='$esc_end', status='block-scheduled';" || true
	done <"$active"

	rm -f "$active"
	uci commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
}

case "$1" in
--init-db|init-db)
	init_db
	;;
list)
	list_schedules
	;;
active-for-mac)
	shift
	active_for_mac "$@"
	;;
save)
	shift
	save_schedule "$@"
	;;
delete)
	shift
	delete_schedule "$@"
	;;
pause)
	shift
	pause_schedule "$@"
	;;
resume)
	shift
	resume_schedule "$@"
	;;
activity-list)
	list_activity
	;;
activity-clear)
	clear_activity
	;;
apply|--apply)
	apply_schedules
	;;
*)
	echo "usage: $0 {init-db|list|active-for-mac MAC|save ID NAME START END ENABLED MAC...|delete ID|pause ID MINUTES|resume ID|activity-list|activity-clear|apply}" >&2
	exit 1
	;;
esac
