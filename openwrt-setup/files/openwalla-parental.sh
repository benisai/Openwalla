#!/bin/sh

# Router-side Openwalla parental controls database and enforcement helper.

mkdir -p /tmp/openwalla

DEFAULT_DB="/tmp/openwalla/openwalla-parental.sqlite"
RULE_PREFIX="openwalla_parental_profile_"

uci_get() { uci -q get "$1" 2>/dev/null || true; }
sql_escape() { printf "%s" "$1" | sed "s/'/''/g"; }
normalize_mac() { printf "%s" "$1" | tr '[:lower:]-' '[:upper:]:'; }
is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
sqlite_bin() {
	command -v sqlite3 >/dev/null 2>&1 && { echo sqlite3; return; }
	command -v sqlite3-cli >/dev/null 2>&1 && { echo sqlite3-cli; return; }
	return 1
}
db_path() {
	path="${OPENWALLA_PARENTAL_DB:-}"
	[ -n "$path" ] || path="$(uci_get openwalla.parental.db_path)"
	[ -n "$path" ] || path="$DEFAULT_DB"
	echo "$path"
}
sql_exec() {
	bin="$(sqlite_bin)" || { echo "sqlite3/sqlite3-cli not installed" >&2; return 127; }
	"$bin" -batch -noheader -separator '|' "$(db_path)" "$1"
}

backup_path() {
	if [ -n "${OPENWALLA_PARENTAL_BACKUP:-}" ]; then echo "$OPENWALLA_PARENTAL_BACKUP"; return; fi
	state_dir="$(uci_get openwalla.state_backup.state_dir)"
	[ -n "$state_dir" ] || state_dir="/overlay/openwalla-state"
	echo "$state_dir/openwalla-parental.sqlite"
}

persist_db() {
	bin="$(sqlite_bin)" || return 1
	dst="$(backup_path)"; mkdir -p "$(dirname "$dst")"
	"$bin" "$(db_path)" ".timeout 5000" ".backup '$dst'" >/dev/null 2>&1 || cp -f "$(db_path)" "$dst"
}

init_db() {
	db="$(db_path)"; saved="$(backup_path)"
	if [ ! -f "$db" ] && [ -f "$saved" ]; then mkdir -p "$(dirname "$db")"; cp -f "$saved" "$db"; fi
	sql_exec "PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS profiles (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '', color TEXT NOT NULL DEFAULT '',
 enabled INTEGER NOT NULL DEFAULT 1, paused INTEGER NOT NULL DEFAULT 0, pause_until INTEGER NOT NULL DEFAULT 0,
 content_filter TEXT NOT NULL DEFAULT 'none', custom_dns TEXT NOT NULL DEFAULT '', daily_limit INTEGER NOT NULL DEFAULT 0,
 active_days TEXT NOT NULL DEFAULT '', block_time TEXT NOT NULL DEFAULT '', resume_time TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS profile_members (profile_id TEXT NOT NULL, mac TEXT NOT NULL, PRIMARY KEY(profile_id, mac));
CREATE TABLE IF NOT EXISTS daily_usage (profile_id TEXT NOT NULL, usage_date TEXT NOT NULL, minutes INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(profile_id, usage_date));
CREATE TABLE IF NOT EXISTS parental_activity (id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id TEXT NOT NULL DEFAULT '', profile_name TEXT NOT NULL DEFAULT '', action TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_parental_members_mac ON profile_members(mac);
CREATE INDEX IF NOT EXISTS idx_parental_activity_created ON parental_activity(created_at DESC);" >/dev/null
}

log_activity() {
	id="$(sql_escape "$1")"; name="$(sql_escape "$2")"; action="$(sql_escape "$3")"; detail="$(sql_escape "$4")"
	sql_exec "INSERT INTO parental_activity(profile_id,profile_name,action,detail,created_at) VALUES('$id','$name','$action','$detail',strftime('%s','now')); DELETE FROM parental_activity WHERE id NOT IN (SELECT id FROM parental_activity ORDER BY created_at DESC,id DESC LIMIT 200);" >/dev/null 2>&1 || true
}

profile_list() {
	init_db || return 1
	sql_exec "SELECT p.id,hex(p.name),hex(p.icon),p.color,p.enabled,p.paused,p.pause_until,p.content_filter,hex(p.custom_dns),p.daily_limit,p.active_days,p.block_time,p.resume_time,COALESCE(group_concat(m.mac,','),'') FROM profiles p LEFT JOIN profile_members m ON m.profile_id=p.id GROUP BY p.id ORDER BY lower(p.name);"
}

profile_save() {
	init_db || return 1
	id="$(sql_escape "$1")"; name="$(sql_escape "$2")"; icon="$(sql_escape "$3")"; color="$(sql_escape "$4")"
	enabled="$5"; paused="$6"; pause_until="$7"; filter="$(sql_escape "$8")"; dns="$(sql_escape "$9")"
	shift 9
	limit="$1"; days="$(sql_escape "$2")"; block="$(sql_escape "$3")"; resume="$(sql_escape "$4")"; shift 4
	is_number "$enabled" || enabled=1; is_number "$paused" || paused=0; is_number "$pause_until" || pause_until=0; is_number "$limit" || limit=0
	sql_exec "INSERT INTO profiles(id,name,icon,color,enabled,paused,pause_until,content_filter,custom_dns,daily_limit,active_days,block_time,resume_time,updated_at) VALUES('$id','$name','$icon','$color',$enabled,$paused,$pause_until,'$filter','$dns',$limit,'$days','$block','$resume',strftime('%s','now')) ON CONFLICT(id) DO UPDATE SET name=excluded.name,icon=excluded.icon,color=excluded.color,enabled=excluded.enabled,paused=excluded.paused,pause_until=excluded.pause_until,content_filter=excluded.content_filter,custom_dns=excluded.custom_dns,daily_limit=excluded.daily_limit,active_days=excluded.active_days,block_time=excluded.block_time,resume_time=excluded.resume_time,updated_at=excluded.updated_at; DELETE FROM profile_members WHERE profile_id='$id';"
	for raw in "$@"; do
		mac="$(normalize_mac "$raw")"
		printf "%s" "$mac" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' || continue
		sql_exec "INSERT OR IGNORE INTO profile_members(profile_id,mac) VALUES('$id','$(sql_escape "$mac")');" >/dev/null
	done
	log_activity "$id" "$name" "Profile Updated" "Router profile saved"
	apply_profiles >/dev/null 2>&1 || true
	persist_db
}

profile_delete() {
	init_db || return 1
	id="$(sql_escape "$1")"; name="$(sql_exec "SELECT name FROM profiles WHERE id='$id' LIMIT 1;")"
	sql_exec "DELETE FROM profile_members WHERE profile_id='$id'; DELETE FROM daily_usage WHERE profile_id='$id'; DELETE FROM profiles WHERE id='$id';"
	log_activity "$id" "$name" "Profile Deleted" ""
	apply_profiles >/dev/null 2>&1 || true
	persist_db
}

profile_pause() {
	init_db || return 1
	id="$(sql_escape "$1")"; until="$2"; is_number "$until" || until=0
	sql_exec "UPDATE profiles SET paused=1,pause_until=$until,updated_at=strftime('%s','now') WHERE id='$id';"
	name="$(sql_exec "SELECT name FROM profiles WHERE id='$id' LIMIT 1;")"; log_activity "$id" "$name" "Paused" ""
	apply_profiles >/dev/null 2>&1 || true
	persist_db
}

profile_resume() {
	init_db || return 1
	id="$(sql_escape "$1")"
	sql_exec "UPDATE profiles SET paused=0,pause_until=0,updated_at=strftime('%s','now') WHERE id='$id';"
	name="$(sql_exec "SELECT name FROM profiles WHERE id='$id' LIMIT 1;")"; log_activity "$id" "$name" "Resumed" ""
	apply_profiles >/dev/null 2>&1 || true
	persist_db
}

to_minutes() {
	value="$1"; hour="${value%%:*}"; minute="${value#*:}"
	case "$hour:$minute" in [0-2][0-9]:[0-5][0-9]) ;; *) echo -1; return ;; esac
	hour="$(echo "$hour" | sed 's/^0*//')"; minute="$(echo "$minute" | sed 's/^0*//')"
	[ -n "$hour" ] || hour=0; [ -n "$minute" ] || minute=0
	[ "$hour" -le 23 ] || { echo -1; return; }; echo $((hour * 60 + minute))
}

schedule_active() {
	days="$1"; start="$(to_minutes "$2")"; end="$(to_minutes "$3")"; now="$(to_minutes "$(date +%H:%M)")"
	[ "$start" -ge 0 ] && [ "$end" -ge 0 ] || return 1
	# Dart indexes days Monday=0 through Sunday=6. POSIX date uses Sunday=0.
	dow="$(date +%u)"; dow=$((dow - 1))
	case ",$days," in *",$dow,"*) ;; *) return 1 ;; esac
	[ "$start" -eq "$end" ] && return 0
	[ "$start" -lt "$end" ] && { [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]; return; }
	[ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
}

remove_rules() {
	for section in $(uci -q show firewall | sed -n "s/^firewall\.\([^.=]*\)\.name=['\"]\{0,1\}${RULE_PREFIX}.*/\1/p"); do uci -q delete "firewall.$section"; done
}
add_rule() {
	mac="$1"; id="$2"; section="$(uci add firewall rule)" || return
	uci set "firewall.$section.name=${RULE_PREFIX}${id}_$(echo "$mac" | tr '[:upper:]:' '[:lower:]_')"
	uci set "firewall.$section.src=lan"; uci set "firewall.$section.dest=wan"; uci set "firewall.$section.src_mac=$mac"
	uci set "firewall.$section.proto=all"; uci set "firewall.$section.target=REJECT"; uci set "firewall.$section.family=any"
}

apply_profiles() {
	init_db || return 1
	now="$(date +%s)"; today="$(date +%F)"; devices_db="$(uci_get openwalla.devices.db_path)"; [ -n "$devices_db" ] || devices_db="/tmp/openwalla/openwalla-devices.sqlite"
	sql_exec "UPDATE profiles SET paused=0,pause_until=0 WHERE paused=1 AND pause_until>0 AND pause_until<=$now;" >/dev/null
	# Count one minute when at least one assigned member is currently online.
	bin="$(sqlite_bin)"
	if [ -f "$devices_db" ]; then
		sql_exec "SELECT id,daily_limit FROM profiles WHERE enabled=1 AND daily_limit>0;" | while IFS='|' read -r id limit; do
			members="$(sql_exec "SELECT mac FROM profile_members WHERE profile_id='$(sql_escape "$id")';" | tr '\n' ',' | sed 's/,$//')"
			[ -n "$members" ] || continue
			online="$($bin "$devices_db" "SELECT count(*) FROM devices WHERE status!='offline' AND instr(upper('$members'),upper(mac))>0;" 2>/dev/null || echo 0)"
			[ "$online" -gt 0 ] 2>/dev/null || continue
			sql_exec "INSERT INTO daily_usage(profile_id,usage_date,minutes) VALUES('$(sql_escape "$id")','$today',1) ON CONFLICT(profile_id,usage_date) DO UPDATE SET minutes=minutes+1;" >/dev/null
		done
	fi
	active="/tmp/openwalla/.openwalla-parental-active.$$"; : >"$active"
	sql_exec "SELECT id,paused,pause_until,daily_limit,active_days,block_time,resume_time FROM profiles WHERE enabled=1;" | while IFS='|' read -r id paused until limit days block resume; do
		blocked=0
		[ "$paused" = 1 ] && blocked=1
		usage="$(sql_exec "SELECT COALESCE(minutes,0) FROM daily_usage WHERE profile_id='$(sql_escape "$id")' AND usage_date='$today';")"; [ -n "$usage" ] || usage=0
		[ "$limit" -gt 0 ] 2>/dev/null && [ "$usage" -ge "$limit" ] 2>/dev/null && blocked=1
		[ -n "$days" ] && schedule_active "$days" "$block" "$resume" && blocked=1
		[ "$blocked" -eq 1 ] || continue
		sql_exec "SELECT mac FROM profile_members WHERE profile_id='$(sql_escape "$id")';" | while read -r mac; do [ -n "$mac" ] && echo "$mac|$id" >>"$active"; done
	done
	remove_rules
	while IFS='|' read -r mac id; do [ -n "$mac" ] && add_rule "$mac" "$id"; done <"$active"
	rm -f "$active"; uci commit firewall; /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
}

activity_list() { init_db && sql_exec "SELECT profile_id,hex(profile_name),action,hex(detail),created_at FROM parental_activity ORDER BY created_at DESC,id DESC LIMIT 200;"; }
activity_clear() { init_db && sql_exec "DELETE FROM parental_activity;"; }

case "$1" in
init-db|--init-db) init_db ;;
profile-list) profile_list ;;
profile-save) shift; profile_save "$@" ;;
profile-delete) shift; profile_delete "$@" ;;
profile-pause) shift; profile_pause "$@" ;;
profile-resume) shift; profile_resume "$@" ;;
activity-list) activity_list ;;
activity-clear) activity_clear ;;
apply|--apply) apply_profiles ;;
*) echo "usage: $0 {init-db|profile-list|profile-save ...|profile-delete ID|profile-pause ID EPOCH|profile-resume ID|activity-list|activity-clear|apply}" >&2; exit 1 ;;
esac
