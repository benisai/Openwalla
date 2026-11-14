#!/bin/sh

# Shared one-minute maintenance entry point for Openwalla router tasks.
set -u

RUNTIME_DIR="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
CRON_PATH="${OPENWALLA_CRON_PATH:-/etc/crontabs/root}"
PING_SCRIPT="${OPENWALLA_DEVICES_PING:-/usr/bin/openwalla-devices-ping}"
INIT_DIR="${OPENWALLA_INIT_DIR:-/etc/init.d}"
PROC_DIR="${OPENWALLA_PROC_DIR:-/proc}"
REPORT_LOCK="$RUNTIME_DIR/adblock-report.lock"

# OPENWALLA_ADBLOCK_REPORT: capability checked by the app before enabling reports.
update_adblock_report() (
	local enabled reporting cores tmp='' json snapshot total report_dir capture file
	mkdir -p "$RUNTIME_DIR" || return 1
	mkdir "$REPORT_LOCK" 2>/dev/null || { echo '[adblock-report] A report is already running.'; return 0; }
	trap '[ -z "$tmp" ] || rm -rf "$tmp"; rmdir "$REPORT_LOCK" 2>/dev/null || true' EXIT
	trap 'exit 1' INT TERM
	date '+[adblock-report] %Y-%m-%d %H:%M:%S %Z'
	[ -x "$INIT_DIR/adblock" ] || { echo '[adblock-report] AdBlock is not installed.'; return 0; }
	enabled="$(uci -q get adblock.global.adb_enabled 2>/dev/null)"
	reporting="$(uci -q get adblock.global.adb_report 2>/dev/null)"
	[ "$enabled" = 1 ] && [ "$reporting" = 1 ] || { echo "[adblock-report] Disabled: adb_enabled=$enabled adb_report=$reporting"; return 0; }
	command -v tcpdump >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1 || { echo '[adblock-report] tcpdump or jsonfilter unavailable.'; return 1; }
	command -v timeout >/dev/null 2>&1 || { echo '[adblock-report] timeout unavailable; skipping.'; return 0; }
	cores="$(awk '/^processor/ {n++} END {print n+0}' "$PROC_DIR/cpuinfo" 2>/dev/null)"
	[ "${cores:-0}" -gt 0 ] || cores=1
	if [ -r "$PROC_DIR/loadavg" ] && awk -v n="$cores" '{exit !($1 > n)}' "$PROC_DIR/loadavg"; then
		echo '[adblock-report] Router busy; keeping last report.'
		return 0
	fi
	if [ -r "$PROC_DIR/meminfo" ] && awk '/^MemAvailable:/ {found=1; available=$2} END {exit !(found && available < 16384)}' "$PROC_DIR/meminfo"; then
		echo '[adblock-report] Low memory; keeping last report.'
		return 0
	fi
	tmp="$(mktemp -d "$RUNTIME_DIR/.adblock-report.XXXXXX")" || return 1
	report_dir="$(uci -q get adblock.global.adb_reportdir 2>/dev/null || echo /tmp/adblock-report)"
	[ -n "$report_dir" ] || report_dir=/tmp/adblock-report
	mkdir -p "$report_dir" || { echo '[adblock-report] Cannot create capture directory.'; return 1; }
	capture=0
	for file in "$report_dir"/adb_report.pcap*; do [ ! -f "$file" ] || capture=1; done
	if [ "$capture" = 0 ]; then
		# /tmp is empty after reboot; AdBlock may have started before its parent directory existed.
		echo '[adblock-report] No capture files; requesting AdBlock capture startup.'
		timeout 10 "$INIT_DIR/adblock" reload >"$tmp/start.log" 2>&1 || { tail -n 20 "$tmp/start.log"; return 1; }
		return 0
	fi
	# A bounded native report reads the rotating DNS-only capture, not live traffic.
	set -- "$INIT_DIR/adblock" report gen 10 1000
	if command -v nice >/dev/null 2>&1; then set -- nice -n 10 "$@"; fi
	timeout 45 "$@" >"$tmp/generate.log" 2>&1 || {
		echo '[adblock-report] Generation failed or timed out; keeping last report.'
		tail -n 20 "$tmp/generate.log"
		return 1
	}
	json="$tmp/report.json"
	timeout 10 "$INIT_DIR/adblock" report json >"$json" 2>"$tmp/read.log" || {
		echo '[adblock-report] Cannot retrieve native report JSON.'
		tail -n 20 "$tmp/read.log"
		return 1
	}
	[ -s "$json" ] || { echo '[adblock-report] No native report yet; check capture and DNS traffic.'; return 0; }
	[ "$(wc -c <"$json")" -le 2097152 ] || { echo '[adblock-report] JSON exceeds 2 MB limit.'; return 1; }
	total="$(jsonfilter -i "$json" -e '@[0].total' 2>/dev/null)" || { echo '[adblock-report] Native JSON is invalid.'; return 1; }
	case "$total" in ''|*[!0-9]*) echo '[adblock-report] No valid report available yet.'; return 0 ;; esac
	snapshot="$tmp/snapshot.json"
	{ printf '{"generated_at":%s,"data":' "$(date +%s)"; cat "$json"; printf '}\n'; } >"$snapshot" || return 1
	mv -f "$snapshot" "$RUNTIME_DIR/adblock-report.json" || return 1
	echo '[adblock-report] Cached report updated.'
)

install_cron() {
	local tmp
	mkdir -p "$RUNTIME_DIR" "$(dirname "$CRON_PATH")" || return 1
	touch "$CRON_PATH" || return 1
	tmp="$(mktemp "$RUNTIME_DIR/.openwalla-1min-cron.XXXXXX")" || return 1
	grep -v 'OPENWALLA_1MIN_RUN' "$CRON_PATH" >"$tmp" || true
	echo '* * * * * mkdir -p /tmp/openwalla; /usr/bin/Openwalla-1min-run.sh run >/tmp/openwalla/openwalla-1min-run.last.log 2>&1 # OPENWALLA_1MIN_RUN' >>"$tmp"
	cp "$tmp" "$CRON_PATH" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"
	/etc/init.d/cron reload >/dev/null 2>&1 || \
		/etc/init.d/crond reload >/dev/null 2>&1 || \
		killall -HUP crond >/dev/null 2>&1 || true
}

case "${1:-run}" in
run)
	mkdir -p "$RUNTIME_DIR" || exit 1
	update_adblock_report >"$RUNTIME_DIR/adblock-report.last.log" 2>&1
	result=$?
	if [ -x "$PING_SCRIPT" ]; then "$PING_SCRIPT" || result=1; fi
	exit "$result"
	;;
report-adblock)
	update_adblock_report
	;;
install-cron) install_cron ;;
*) echo "Usage: $0 [run|report-adblock|install-cron]" >&2; exit 2 ;;
esac
