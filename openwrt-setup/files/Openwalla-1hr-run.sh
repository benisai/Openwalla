#!/bin/sh

# Shared hourly maintenance runner for Openwalla router tasks.
# Keep periodic work here instead of adding it to frequently polled collectors.

set -u

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DEFAULT_DEVICES_DB="/tmp/openwalla-devices.sqlite"
DEFAULT_VENDOR_DB="/usr/share/openwalla/openwalla-mac-vendors.txt"
VENDOR_DB="${OPENWALLA_VENDOR_DB:-$DEFAULT_VENDOR_DB}"
CRON_PATH="${OPENWALLA_CRON_PATH:-/etc/crontabs/root}"
CRON_MARKER="# OPENWALLA_1HR_RUN"
LOCK_DIR="/tmp/openwalla-1hr-run.lock"

find_sqlite_bin() {
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

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}

run_vendor_enrichment() {
	local sqlite_bin devices_db prefixes matches prefix vendor esc_vendor
	sqlite_bin="$(find_sqlite_bin || true)"
	[ -n "$sqlite_bin" ] || {
		echo "[openwalla-1hr] Skipping vendor lookup: sqlite is unavailable."
		return 0
	}
	devices_db="${OPENWALLA_DEVICES_DB:-$(uci -q get openwalla.devices.db_path 2>/dev/null || echo "$DEFAULT_DEVICES_DB")}"
	[ -f "$devices_db" ] || return 0
	[ -r "$VENDOR_DB" ] || return 0

	prefixes="/tmp/.openwalla-vendor-prefixes.$$"
	matches="/tmp/.openwalla-vendor-matches.$$"
	"$sqlite_bin" -batch -noheader "$devices_db" \
		"SELECT DISTINCT upper(substr(replace(mac, ':', ''), 1, 6)) FROM devices WHERE vendor = '' AND length(replace(mac, ':', '')) >= 6;" \
		>"$prefixes" 2>/dev/null || true

	if [ -s "$prefixes" ]; then
		awk 'NR == FNR { wanted[toupper($1)]=1; next } {
			tab=index($0, "\t")
			if (tab == 0) next
			prefix=toupper(substr($0, 1, tab - 1))
			if (wanted[prefix]) {
				vendor=substr($0, tab + 1)
				sub(/\t.*$/, "", vendor)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", vendor)
				if (vendor != "") print prefix "|" vendor
				delete wanted[prefix]
			}
		}' "$prefixes" "$VENDOR_DB" >"$matches"

		while IFS='|' read -r prefix vendor; do
			[ -n "$prefix" ] && [ -n "$vendor" ] || continue
			esc_vendor="$(sql_escape "$vendor")"
			"$sqlite_bin" "$devices_db" \
				"PRAGMA busy_timeout=3000; UPDATE devices SET vendor='$esc_vendor' WHERE vendor='' AND upper(substr(replace(mac, ':', ''), 1, 6))='$prefix';" \
				>/dev/null 2>&1 || true
		done <"$matches"
	fi

	rm -f "$prefixes" "$matches"
}

reload_cron() {
	/etc/init.d/cron reload >/dev/null 2>&1 || \
		/etc/init.d/cron restart >/dev/null 2>&1 || \
		/etc/init.d/crond reload >/dev/null 2>&1 || \
		/etc/init.d/crond restart >/dev/null 2>&1 || \
		killall -HUP crond >/dev/null 2>&1 || true
}

install_cron() {
	local tmp
	mkdir -p "$(dirname "$CRON_PATH")"
	touch "$CRON_PATH"
	tmp="/tmp/.openwalla-1hr-cron.$$"
	grep -v "OPENWALLA_1HR_RUN" "$CRON_PATH" >"$tmp" 2>/dev/null || : >"$tmp"
	echo "0 * * * * /usr/bin/Openwalla-1hr-run.sh run >/tmp/openwalla-1hr-run.last.log 2>&1 $CRON_MARKER" >>"$tmp"
	cp "$tmp" "$CRON_PATH"
	rm -f "$tmp"
	reload_cron
}

run_all() {
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		echo "[openwalla-1hr] Another hourly run is active; skipping."
		return 0
	fi
	trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
	run_vendor_enrichment
	rmdir "$LOCK_DIR" 2>/dev/null || true
	trap - EXIT INT TERM
}

case "${1:-run}" in
run) run_all ;;
install-cron) install_cron ;;
vendor) run_vendor_enrichment ;;
*)
	echo "Usage: $0 [run|install-cron|vendor]"
	exit 2
	;;
esac
