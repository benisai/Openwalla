#!/bin/sh

# Openwalla state sync:
# - keeps live writes in /tmp
# - checkpoints selected runtime data to persistent storage on interval
# - restores checkpoint back into /tmp on boot

set -u

MARKER="# OPENWALLA_STATE_SYNC"
CRON_PATH="/etc/crontabs/root"
STATE_TS_FILE="/tmp/openwalla-state-sync.last"

uci_get() {
	uci -q get "$1" 2>/dev/null || true
}

read_backup_time_min() {
	local raw
	raw="$(uci_get openwalla.state_backup.backup_time)"
	case "$raw" in
	''|*[!0-9]*)
		echo "720"
		return
		;;
	esac
	if [ "$raw" -lt 60 ]; then
		echo "60"
		return
	fi
	if [ "$raw" -gt 10080 ]; then
		echo "10080"
		return
	fi
	echo "$raw"
}

read_state_dir() {
	local dir
	dir="$(uci_get openwalla.state_backup.state_dir)"
	if [ -z "$dir" ]; then
		dir="/overlay/openwalla-state"
	fi
	echo "$dir"
}

read_netify_db() {
	local path
	path="$(uci_get openwalla.collector.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-netify.sqlite"
	fi
	echo "$path"
}

read_netify_flow_stats_db() {
	local path
	path="$(uci_get openwalla.flow_stats.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-netify-flow-stats.sqlite"
	fi
	echo "$path"
}

read_connection_flows_db() {
	local path
	path="$(uci_get openwalla.connection_flows.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-connection-flows.sqlite"
	fi
	echo "$path"
}

read_device_bandwidth_db() {
	local path
	path="$(uci_get openwalla.device_bandwidth.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-device-bandwidth.sqlite"
	fi
	echo "$path"
}

read_devices_db() {
	local path
	path="$(uci_get openwalla.devices.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-devices.sqlite"
	fi
	echo "$path"
}

read_notifications_db() {
	local path
	path="$(uci_get openwalla.notifications.db_path)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-notifications.sqlite"
	fi
	echo "$path"
}

read_parental_db() {
	local path
	path="$(uci_get openwalla.parental.db_path)"
	[ -n "$path" ] || path="/tmp/openwalla-parental.sqlite"
	echo "$path"
}

read_ping_file() {
	local path
	path="$(uci_get openwalla.ping_monitor.output_file)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-ping-monitor.txt"
	fi
	echo "$path"
}

read_dns_file() {
	local path
	path="$(uci_get openwalla.dns_monitor.output_file)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-dns-monitor.txt"
	fi
	echo "$path"
}

read_speedtest_file() {
	local path
	path="$(uci_get openwalla.speedtest_monitor.output_file)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-speedtest-monitor.txt"
	fi
	echo "$path"
}

read_quarantine_state_file() {
	local path
	path="$(uci_get openwalla.quarantine.state_file)"
	if [ -z "$path" ]; then
		path="/tmp/openwalla-quarantine-known.txt"
	fi
	echo "$path"
}

save_sqlite() {
	local src="$1"
	local dst="$2"
	if [ ! -f "$src" ]; then
		return 0
	fi
	if command -v sqlite3 >/dev/null 2>&1; then
		sqlite3 "$src" ".timeout 5000" ".backup '$dst'" >/dev/null 2>&1 && return 0
	fi
	cp -f "$src" "$dst" 2>/dev/null || true
}

save_copy() {
	local src="$1"
	local dst="$2"
	[ -f "$src" ] || return 0
	mkdir -p "$(dirname "$dst")" 2>/dev/null || true
	cp -f "$src" "$dst" 2>/dev/null || true
}

save_netify_archives() {
	local netify_db="$1"
	local state_dir="$2"
	local src_dir dst_dir
	src_dir="$(dirname "$netify_db")"
	dst_dir="$state_dir/netify-archives"
	mkdir -p "$dst_dir"
	rm -f "$dst_dir"/netify.* 2>/dev/null || true
	for f in "$src_dir"/netify.*; do
		[ -f "$f" ] || continue
		cp -f "$f" "$dst_dir/" 2>/dev/null || true
	done
}

save_vnstat_dir() {
	local src="/var/lib/vnstat"
	local dst="$1/vnstat"
	[ -d "$src" ] || return 0
	mkdir -p "$dst"
	( cd "$src" && tar -cf - . ) | ( cd "$dst" && tar -xf - ) 2>/dev/null || true
}

save_runtime_logs() {
	local state_dir="$1"
	local dst="$state_dir/tmp"
	mkdir -p "$dst"
	for f in \
		/tmp/openwalla-netify-collector.log \
		/tmp/openwalla-connection-flows-collector.log \
		/tmp/openwalla-devices-collector.log \
		/tmp/openwalla-device-bandwidth-collector.log \
		/tmp/openwalla-dns-monitor.last.log \
		/tmp/openwalla-paternal-pause.last.log \
		/tmp/openwalla-network-monitor.last.log \
		/tmp/openwalla-speedtest-monitor.last.log
	do
		[ -f "$f" ] || continue
		cp -f "$f" "$dst/" 2>/dev/null || true
	done
}

file_mtime_epoch() {
	local file="$1"
	[ -f "$file" ] || return 1
	stat -c %Y "$file" 2>/dev/null && return 0
	stat -f %m "$file" 2>/dev/null && return 0
	return 1
}

read_last_backup_epoch() {
	local state_dir="$1"
	local last newest file mtime
	last="$(cat "$STATE_TS_FILE" 2>/dev/null || cat "$state_dir/openwalla-state-sync.last" 2>/dev/null || echo 0)"
	case "$last" in
	''|*[!0-9]*) last=0 ;;
	esac
	if [ "$last" -gt 0 ]; then
		echo "$last"
		return
	fi

	newest=0
	for file in \
		"$state_dir/openwalla-netify.sqlite" \
		"$state_dir/openwalla-netify-flow-stats.sqlite" \
		"$state_dir/openwalla-connection-flows.sqlite" \
		"$state_dir/openwalla-devices.sqlite" \
		"$state_dir/openwalla-device-bandwidth.sqlite" \
			"$state_dir/openwalla-notifications.sqlite" \
			"$state_dir/openwalla-parental.sqlite" \
		"$state_dir/openwalla-ping-monitor.txt" \
		"$state_dir/openwalla-dns-monitor.txt" \
		"$state_dir/openwalla-speedtest-monitor.txt" \
		"$state_dir/openwalla-quarantine-known.txt" \
		"$state_dir/openwalla.config"
	do
		mtime="$(file_mtime_epoch "$file" 2>/dev/null || echo 0)"
		case "$mtime" in
		''|*[!0-9]*) mtime=0 ;;
		esac
		[ "$mtime" -gt "$newest" ] && newest="$mtime"
	done
	echo "$newest"
}

restore_copy() {
	local src="$1"
	local dst="$2"
	[ -f "$src" ] || return 0
	mkdir -p "$(dirname "$dst")" 2>/dev/null || true
	cp -f "$src" "$dst" 2>/dev/null || true
}

restore_runtime_logs() {
	local state_dir="$1"
	local src="$state_dir/tmp"
	[ -d "$src" ] || return 0
	for f in "$src"/openwalla-*.log "$src"/openwalla-speedtest-monitor.last.log; do
		[ -f "$f" ] || continue
		cp -f "$f" "/tmp/$(basename "$f")" 2>/dev/null || true
	done
}

restore_netify_archives() {
	local netify_db="$1"
	local state_dir="$2"
	local src_dir dst_dir
	dst_dir="$(dirname "$netify_db")"
	src_dir="$state_dir/netify-archives"
	[ -d "$src_dir" ] || return 0
	mkdir -p "$dst_dir"
	for f in "$src_dir"/netify.*; do
		[ -f "$f" ] || continue
		cp -f "$f" "$dst_dir/" 2>/dev/null || true
	done
}

restore_vnstat_dir() {
	local src="$1/vnstat"
	local dst="/var/lib/vnstat"
	[ -d "$src" ] || return 0
	mkdir -p "$dst"
	( cd "$src" && tar -cf - . ) | ( cd "$dst" && tar -xf - ) 2>/dev/null || true
}

save_state() {
	local state_dir netify_db netify_flow_stats_db flows_db devices_db device_bandwidth_db notifications_db parental_db ping_file dns_file speedtest_file quarantine_state_file
	state_dir="$(read_state_dir)"
	netify_db="$(read_netify_db)"
	netify_flow_stats_db="$(read_netify_flow_stats_db)"
	flows_db="$(read_connection_flows_db)"
	devices_db="$(read_devices_db)"
	device_bandwidth_db="$(read_device_bandwidth_db)"
	notifications_db="$(read_notifications_db)"
	parental_db="$(read_parental_db)"
	ping_file="$(read_ping_file)"
	dns_file="$(read_dns_file)"
	speedtest_file="$(read_speedtest_file)"
	quarantine_state_file="$(read_quarantine_state_file)"

	mkdir -p "$state_dir"
	save_sqlite "$netify_db" "$state_dir/openwalla-netify.sqlite"
	save_sqlite "$netify_flow_stats_db" "$state_dir/openwalla-netify-flow-stats.sqlite"
	save_sqlite "$flows_db" "$state_dir/openwalla-connection-flows.sqlite"
	save_sqlite "$devices_db" "$state_dir/openwalla-devices.sqlite"
	save_sqlite "$device_bandwidth_db" "$state_dir/openwalla-device-bandwidth.sqlite"
	save_sqlite "$notifications_db" "$state_dir/openwalla-notifications.sqlite"
	save_sqlite "$parental_db" "$state_dir/openwalla-parental.sqlite"
	save_netify_archives "$netify_db" "$state_dir"
	save_copy "$ping_file" "$state_dir/openwalla-ping-monitor.txt"
	save_copy "$dns_file" "$state_dir/openwalla-dns-monitor.txt"
	save_copy "$speedtest_file" "$state_dir/openwalla-speedtest-monitor.txt"
	save_copy "$quarantine_state_file" "$state_dir/openwalla-quarantine-known.txt"
	save_copy "/etc/config/openwalla" "$state_dir/openwalla.config"
	save_vnstat_dir "$state_dir"
	save_runtime_logs "$state_dir"
	date +%s >"$STATE_TS_FILE" 2>/dev/null || true
	save_copy "$STATE_TS_FILE" "$state_dir/openwalla-state-sync.last"
}

restore_state() {
	local state_dir netify_db netify_flow_stats_db flows_db devices_db device_bandwidth_db notifications_db parental_db ping_file dns_file speedtest_file quarantine_state_file
	state_dir="$(read_state_dir)"
	netify_db="$(read_netify_db)"
	netify_flow_stats_db="$(read_netify_flow_stats_db)"
	flows_db="$(read_connection_flows_db)"
	devices_db="$(read_devices_db)"
	device_bandwidth_db="$(read_device_bandwidth_db)"
	notifications_db="$(read_notifications_db)"
	parental_db="$(read_parental_db)"
	ping_file="$(read_ping_file)"
	dns_file="$(read_dns_file)"
	speedtest_file="$(read_speedtest_file)"
	quarantine_state_file="$(read_quarantine_state_file)"

	[ -d "$state_dir" ] || return 0
	restore_copy "$state_dir/openwalla-netify.sqlite" "$netify_db"
	restore_copy "$state_dir/openwalla-netify-flow-stats.sqlite" "$netify_flow_stats_db"
	restore_copy "$state_dir/openwalla-connection-flows.sqlite" "$flows_db"
	restore_copy "$state_dir/openwalla-devices.sqlite" "$devices_db"
	restore_copy "$state_dir/openwalla-device-bandwidth.sqlite" "$device_bandwidth_db"
	restore_copy "$state_dir/openwalla-notifications.sqlite" "$notifications_db"
	restore_copy "$state_dir/openwalla-parental.sqlite" "$parental_db"
	restore_netify_archives "$netify_db" "$state_dir"
	restore_copy "$state_dir/openwalla-ping-monitor.txt" "$ping_file"
	restore_copy "$state_dir/openwalla-dns-monitor.txt" "$dns_file"
	restore_copy "$state_dir/openwalla-speedtest-monitor.txt" "$speedtest_file"
	restore_copy "$state_dir/openwalla-quarantine-known.txt" "$quarantine_state_file"
	restore_copy "$state_dir/openwalla.config" "/etc/config/openwalla"
	restore_copy "$state_dir/openwalla-state-sync.last" "$STATE_TS_FILE"
	restore_vnstat_dir "$state_dir"
	restore_runtime_logs "$state_dir"
}

print_status() {
	local state_dir interval last size files last_iso cron_line service_enabled service_running
	state_dir="$(read_state_dir)"
	interval="$(read_backup_time_min)"
	last="$(read_last_backup_epoch "$state_dir")"
	if [ "$last" -gt 0 ]; then
		last_iso="$(date -u -d "@$last" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$last" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"
	else
		last_iso=""
	fi
	if [ -d "$state_dir" ]; then
		size="$(du -sh "$state_dir" 2>/dev/null | awk '{print $1}')"
		files="$(find "$state_dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
	else
		size="0 B"
		files="0"
	fi
	cron_line="$(grep "$MARKER" "$CRON_PATH" 2>/dev/null | tail -n 1 || true)"
	service_enabled="0"
	[ -e /etc/rc.d/S*openwalla-state-sync ] && service_enabled="1"
	service_running="0"
	/etc/init.d/openwalla-state-sync enabled >/dev/null 2>&1 && service_enabled="1"
	/etc/init.d/openwalla-state-sync status >/dev/null 2>&1 && service_running="1"
	printf "installed|1\n"
	printf "state_dir|%s\n" "$state_dir"
	printf "backup_time_min|%s\n" "$interval"
	printf "last_backup_epoch|%s\n" "$last"
	printf "last_backup_iso|%s\n" "$last_iso"
	printf "file_count|%s\n" "$files"
	printf "size|%s\n" "$size"
	printf "cron_line|%s\n" "$cron_line"
	printf "service_enabled|%s\n" "$service_enabled"
	printf "service_running|%s\n" "$service_running"
}

save_if_due() {
	local state_dir interval now last elapsed
	state_dir="$(read_state_dir)"
	interval="$(read_backup_time_min)"
	now="$(date +%s 2>/dev/null || echo 0)"
	last="$(read_last_backup_epoch "$state_dir")"
	elapsed=$((now - last))
	if [ "$elapsed" -ge $((interval * 60)) ]; then
		save_state
	fi
}

print_debug() {
	local state_dir
	state_dir="$(read_state_dir)"
	print_status
	printf "runtime_ping_file|%s|%s\n" "$(read_ping_file)" "$(wc -l "$(read_ping_file)" 2>/dev/null | awk '{print $1}' || echo 0)"
	printf "runtime_dns_file|%s|%s\n" "$(read_dns_file)" "$(wc -l "$(read_dns_file)" 2>/dev/null | awk '{print $1}' || echo 0)"
	printf "runtime_speedtest_file|%s|%s\n" "$(read_speedtest_file)" "$(wc -l "$(read_speedtest_file)" 2>/dev/null | awk '{print $1}' || echo 0)"
	printf "checkpoint_files|\n"
	if [ -d "$state_dir" ]; then
		find "$state_dir" -maxdepth 2 -type f -exec ls -lh {} \; 2>/dev/null | sed 's/^/file|/'
	fi
}

build_cron_line() {
	local interval cmd
	interval="$(read_backup_time_min)"
	cmd="/usr/bin/openwalla-state-sync save"

	if [ "$interval" -lt 60 ]; then
		echo "*/$interval * * * * $cmd $MARKER"
		return
	fi

	if [ "$interval" -eq 60 ]; then
		echo "0 * * * * $cmd $MARKER"
		return
	fi

	if [ "$interval" -eq 1440 ]; then
		echo "0 0 * * * $cmd $MARKER"
		return
	fi

	if [ $((interval % 60)) -eq 0 ] && [ "$interval" -lt 1440 ]; then
		local hours
		hours=$((interval / 60))
		echo "0 */$hours * * * $cmd $MARKER"
		return
	fi

	echo "*/10 * * * * /usr/bin/openwalla-state-sync save-if-due $MARKER"
}

sync_cron() {
	local line tmp
	line="$(build_cron_line)"
	tmp="/tmp/.openwalla_state_cron.$$"

	if [ -f "$CRON_PATH" ]; then
		grep -v "$MARKER" "$CRON_PATH" >"$tmp" 2>/dev/null || : >"$tmp"
	else
		: >"$tmp"
	fi
	echo "$line" >>"$tmp"
	cp "$tmp" "$CRON_PATH"
	rm -f "$tmp"
	/bin/sh -c '/etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || /etc/init.d/crond reload 2>/dev/null || /etc/init.d/crond restart 2>/dev/null || killall -HUP crond 2>/dev/null || true'
}

case "${1:-}" in
save|backup)
	save_state
	;;
restore)
	restore_state
	;;
status)
	print_status
	;;
debug|diagnose)
	print_debug
	;;
save-if-due)
	save_if_due
	;;
sync-cron)
	sync_cron
	;;
*)
	echo "usage: $0 {save|backup|restore|status|debug|save-if-due|sync-cron}"
	exit 1
	;;
esac

exit 0
