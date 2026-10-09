#!/bin/sh

# Verifies and updates Openwalla-managed router helper files without changing
# packages, UCI feature settings, databases, or monitoring history.

set -u

RAW_BASE="${OPENWALLA_RAW_BASE:-https://raw.githubusercontent.com/benisai/openwalla-apk/main/openwrt-setup}"
VERSION_URL="${OPENWALLA_VERSION_URL:-${RAW_BASE%/openwrt-setup}/pub_script_version.yaml}"
ACTION="${1:-status}"
TMP_DIR="/tmp/openwalla-component-update.$$"
UPDATED=0
CURRENT=0
MANAGED=0
FAILED=0
TOUCHED_SERVICES=""

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

migrate_speedtest_schedule() {
	local marker cron_path tmp_cron hour minute enabled
	uci -q get openwalla.speedtest_monitor >/dev/null 2>&1 || return 0
	[ -x /usr/bin/openwalla-speedtest-monitor ] || return 0

	marker="# OPENWALLA_SPEEDTEST_MONITOR"
	cron_path="/etc/crontabs/root"
	tmp_cron="/tmp/.openwalla_speedtest_migrate.$$"
	hour="$(uci -q get openwalla.speedtest_monitor.run_hour 2>/dev/null || echo 3)"
	minute="$(uci -q get openwalla.speedtest_monitor.run_minute 2>/dev/null || echo 15)"
	enabled="$(uci -q get openwalla.speedtest_monitor.enabled 2>/dev/null || echo 1)"
	case "$hour" in ''|*[!0-9]*) hour=3 ;; esac
	case "$minute" in ''|*[!0-9]*) minute=15 ;; esac
	[ "$hour" -le 23 ] || hour=3
	[ "$minute" -le 59 ] || minute=15

	mkdir -p "$(dirname "$cron_path")"
	if [ -f "$cron_path" ]; then
		grep -v "$marker" "$cron_path" >"$tmp_cron" 2>/dev/null || : >"$tmp_cron"
	else
		: >"$tmp_cron"
	fi
	if [ "$enabled" = "1" ]; then
		echo "$minute $hour * * * /usr/bin/openwalla-speedtest-monitor --scheduled >/tmp/openwalla-speedtest-monitor.last.log 2>&1 $marker" >>"$tmp_cron"
	fi
	mv "$tmp_cron" "$cron_path"
	uci -q delete openwalla.speedtest_monitor.run_date >/dev/null 2>&1 || true

	if [ -x /etc/init.d/cron ]; then
		/etc/init.d/cron enable >/dev/null 2>&1 || true
		/etc/init.d/cron restart >/dev/null 2>&1 || /etc/init.d/cron start >/dev/null 2>&1 || true
	elif [ -x /etc/init.d/crond ]; then
		/etc/init.d/crond enable >/dev/null 2>&1 || true
		/etc/init.d/crond restart >/dev/null 2>&1 || /etc/init.d/crond start >/dev/null 2>&1 || true
	fi
}

download() {
	url="$1"
	dst="$2"
	if command -v wget >/dev/null 2>&1; then
		wget -qO "$dst" "$url"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$dst"
	else
		echo "ERROR|Neither wget nor curl is available"
		return 1
	fi
}

checksum() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$1" | awk '{print $NF}'
	else
		cksum "$1" | awk '{print $1 ":" $2}'
	fi
}

touch_service() {
	service="$1"
	[ -n "$service" ] || return 0
	case " $TOUCHED_SERVICES " in
	*" $service "*) ;;
	*) TOUCHED_SERVICES="$TOUCHED_SERVICES $service" ;;
	esac
}

check_file() {
	source_path="$1"
	destination="$2"
	mode="$3"
	service="$4"

	# Components that were never selected in Router Setup remain untouched.
	[ -e "$destination" ] || return 0
	MANAGED=$((MANAGED + 1))
	temporary="$TMP_DIR/$(basename "$destination").$MANAGED"
	if ! download "$RAW_BASE/$source_path" "$temporary"; then
		echo "FAILED|$destination|download failed"
		FAILED=$((FAILED + 1))
		return 0
	fi

	if [ "$(checksum "$temporary")" = "$(checksum "$destination")" ]; then
		CURRENT=$((CURRENT + 1))
		return 0
	fi

	echo "OUTDATED|$destination"
	[ "$ACTION" = "update" ] || return 0
	if cp "$temporary" "$destination" && chmod "$mode" "$destination"; then
		echo "UPDATED|$destination"
		UPDATED=$((UPDATED + 1))
		touch_service "$service"
	else
		echo "FAILED|$destination|install failed"
		FAILED=$((FAILED + 1))
	fi
}

mkdir -p "$TMP_DIR"
VERSION_FILE="$TMP_DIR/pub_script_version.yaml"
COMPONENT_VERSION="unknown"
if download "$VERSION_URL" "$VERSION_FILE"; then
	COMPONENT_VERSION="$(awk -F ': *' '$1 == "version" { print $2; exit }' "$VERSION_FILE")"
	[ -n "$COMPONENT_VERSION" ] || COMPONENT_VERSION="unknown"
else
	echo "ERROR|Unable to read published script version"
fi
echo "AVAILABLE_VERSION|$COMPONENT_VERSION"
echo "INSTALLED_VERSION|$(uci -q get openwalla.core.component_version 2>/dev/null || echo unknown)"

while IFS='|' read -r source_path destination mode service; do
	[ -n "$source_path" ] || continue
	check_file "$source_path" "$destination" "$mode" "$service"
done <<'EOF'
files/openwalla-network-monitor.sh|/usr/bin/openwalla-network-monitor|0755|openwalla-network-monitor
files/openwalla-network-monitor.init|/etc/init.d/openwalla-network-monitor|0755|openwalla-network-monitor
files/openwalla-dns-monitor.sh|/usr/bin/openwalla-dns-monitor|0755|openwalla-dns-monitor
files/openwalla-dns-monitor.init|/etc/init.d/openwalla-dns-monitor|0755|openwalla-dns-monitor
files/openwalla-speedtest-monitor.sh|/usr/bin/openwalla-speedtest-monitor|0755|
files/openwalla-notifications-db.sh|/usr/bin/openwalla-notifications-db|0755|
files/openwalla-devices-collector.sh|/usr/bin/openwalla-devices-collector|0755|openwalla-devices-collector
files/openwalla-devices-collector.init|/etc/init.d/openwalla-devices-collector|0755|openwalla-devices-collector
files/oui/openwalla-mac-vendors.txt|/usr/share/openwalla/openwalla-mac-vendors.txt|0644|
files/Openwalla-1hr-run.sh|/usr/bin/Openwalla-1hr-run.sh|0755|
files/openwalla-device-bandwidth-collector.sh|/usr/bin/openwalla-device-bandwidth-collector|0755|openwalla-device-bandwidth-collector
files/openwalla-device-bandwidth-collector.init|/etc/init.d/openwalla-device-bandwidth-collector|0755|openwalla-device-bandwidth-collector
files/openwalla-device-traffic-summary.sh|/usr/bin/openwalla-device-traffic-summary|0755|
files/openwalla-paternal-pause.sh|/usr/bin/openwalla-paternal-pause|0755|
files/openwalla-scheduler.sh|/usr/bin/openwalla-scheduler|0755|
files/openwalla-parental.sh|/usr/bin/openwalla-parental|0755|
files/openwalla-device-quarantine.hotplug|/etc/hotplug.d/dhcp/95-openwalla-quarantine|0755|
files/openwalla-device-quarantine.hotplug|/etc/hotplug.d/neigh/95-openwalla-quarantine|0755|
files/openwalla-state-sync.sh|/usr/bin/openwalla-state-sync|0755|openwalla-state-sync
files/openwalla-state-sync.init|/etc/init.d/openwalla-state-sync|0755|openwalla-state-sync
files/openwalla-connection-flow-collector.sh|/usr/bin/openwalla-connection-flow-collector|0755|openwalla-connection-flows-collector
files/openwalla-connection-flows-collector.init|/etc/init.d/openwalla-connection-flows-collector|0755|openwalla-connection-flows-collector
files/openwalla-netify-collector.sh|/usr/bin/openwalla-netify-collector|0755|openwalla-netify-collector
files/openwalla-netify-collector.init|/etc/init.d/openwalla-netify-collector|0755|openwalla-netify-collector
files/openwalla-tailscale.sh|/usr/bin/openwalla-tailscale|0755|
files/openwalla-tor.sh|/usr/bin/openwalla-tor|0755|
rpcd-acl.json|/usr/share/rpcd/acl.d/openwalla.json|0644|rpcd
EOF

if [ "$ACTION" = "update" ] && [ "$FAILED" -eq 0 ]; then
	for service in $TOUCHED_SERVICES; do
		[ -x "/etc/init.d/$service" ] || continue
		/etc/init.d/"$service" restart >/dev/null 2>&1 || true
	done
	if [ -x /usr/bin/openwalla-netify-collector ]; then
		/usr/bin/openwalla-netify-collector --install-prune-cron >/dev/null 2>&1 || true
	fi
	if [ -x /usr/bin/Openwalla-1hr-run.sh ]; then
		/usr/bin/Openwalla-1hr-run.sh install-cron >/dev/null 2>&1 || true
		/usr/bin/Openwalla-1hr-run.sh run >/dev/null 2>&1 || true
	fi
	migrate_speedtest_schedule
	uci -q get openwalla.core >/dev/null 2>&1 || uci set openwalla.core='core'
	uci set openwalla.core.component_version="$COMPONENT_VERSION"
	uci commit openwalla
fi

echo "SUMMARY|managed=$MANAGED|current=$CURRENT|updated=$UPDATED|failed=$FAILED"
[ "$FAILED" -eq 0 ]
