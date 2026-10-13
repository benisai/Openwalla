#!/bin/sh

# Shared helpers for Openwalla standalone OpenWrt installers.
# Provides repo/file path resolution, package install helpers, UCI setup,
# file installation, service enable/start helpers, and rpcd ACL installation.

set -u

if [ "$(id -u)" != "0" ]; then
	echo "Run as root."
	exit 1
fi

SCRIPT_PATH="$0"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"
OPENWALLA_SETUP_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
case "$(basename "$SCRIPT_DIR")" in
lib)
	OPENWALLA_SETUP_DIR="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
	;;
esac
FILES_DIR="$OPENWALLA_SETUP_DIR/files"
RPCD_ACL="$OPENWALLA_SETUP_DIR/rpcd-acl.json"
OPENWALLA_RAW_BASE="${OPENWALLA_RAW_BASE:-https://raw.githubusercontent.com/benisai/Openwalla/main/openwrt-setup}"
OPENWALLA_RUNTIME_DIR="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
PKG_MGR=""

mkdir -p "$OPENWALLA_RUNTIME_DIR"

log() {
	echo "[openwalla-standalone] $*"
}

have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

download_file() {
	url="$1"
	dst="$2"
	mkdir -p "$(dirname "$dst")"
	if have_cmd wget; then
		wget -qO "$dst" "$url" && return 0
	fi
	if have_cmd curl; then
		curl -fsSL "$url" -o "$dst" && return 0
	fi
	return 1
}

fetch_missing_file() {
	path="$1"
	case "$path" in
	"$FILES_DIR"/*)
		name="${path#$FILES_DIR/}"
		download_file "$OPENWALLA_RAW_BASE/files/$name" "$path"
		;;
	"$RPCD_ACL")
		download_file "$OPENWALLA_RAW_BASE/rpcd-acl.json" "$path"
		;;
	*)
		return 1
		;;
	esac
}

require_file() {
	if [ ! -f "$1" ]; then
		log "Fetching missing file: $1"
		if ! fetch_missing_file "$1"; then
			echo "Missing required file: $1"
			exit 1
		fi
	fi
}

install_file() {
	src="$1"
	dst="$2"
	mode="$3"
	require_file "$src"
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
	chmod "$mode" "$dst"
	log "Installed $dst"
}

detect_pkg_mgr() {
	if have_cmd opkg; then
		PKG_MGR="opkg"
	elif have_cmd apk; then
		PKG_MGR="apk"
	else
		PKG_MGR=""
	fi
}

update_package_feeds() {
	detect_pkg_mgr
	if [ "${OPENWALLA_PACKAGE_FEEDS_UPDATED:-0}" = "1" ]; then
		log "Package feeds already updated; skipping package feed refresh."
		return 0
	fi
	case "$PKG_MGR" in
	opkg) opkg update ;;
	apk) apk update ;;
	*) log "No supported package manager found (opkg/apk). Package install steps will be skipped." ;;
	esac
	export OPENWALLA_PACKAGE_FEEDS_UPDATED=1
}

install_pkg_if_available() {
	pkg="$1"
	case "$PKG_MGR" in
	opkg)
		if opkg list-installed | grep -q "^$pkg -"; then
			if [ "${OPENWALLA_FORCE_REINSTALL:-0}" = "1" ]; then
				opkg install --force-reinstall "$pkg" && log "Reinstalled package: $pkg" && return 0
				log "Failed to reinstall package: $pkg"
				return 1
			fi
			log "Package already installed: $pkg"
			return 0
		fi
		if ! opkg list | grep -q "^$pkg -"; then
			log "Package unavailable in current feed, skipping: $pkg"
			return 1
		fi
		opkg install "$pkg" && log "Installed package: $pkg" && return 0
		log "Failed to install package: $pkg"
		return 1
		;;
	apk)
		if apk info -e "$pkg" >/dev/null 2>&1; then
			if [ "${OPENWALLA_FORCE_REINSTALL:-0}" = "1" ]; then
				apk fix "$pkg" && log "Reinstalled package: $pkg" && return 0
				log "Failed to reinstall package: $pkg"
				return 1
			fi
			log "Package already installed: $pkg"
			return 0
		fi
		if ! apk search -x "$pkg" >/dev/null 2>&1; then
			log "Package unavailable in current feed, skipping: $pkg"
			return 1
		fi
		apk add "$pkg" && log "Installed package: $pkg" && return 0
		log "Failed to install package: $pkg"
		return 1
		;;
	*)
		log "No supported package manager available; skipping package: $pkg"
		return 1
		;;
	esac
}

install_first_available_pkg() {
	label="$1"
	shift
	for candidate in "$@"; do
		[ -n "$candidate" ] || continue
		if install_pkg_if_available "$candidate"; then
			log "Using package for $label: $candidate"
			return 0
		fi
	done
	log "No installable package found for $label"
	return 1
}

set_uci() {
	key="$1"
	value="$2"
	value="${value#\'}"
	value="${value%\'}"
	value="${value#\"}"
	value="${value%\"}"
	uci set "$key=$value"
}

set_uci_default() {
	key="$1"
	value="$2"
	uci -q get "$key" >/dev/null 2>&1 || set_uci "$key" "$value"
}

migrate_openwalla_runtime_path() {
	local key target service current suffix
	key="$1"
	target="$2"
	service="${3:-}"
	current="$(uci -q get "$key" 2>/dev/null || true)"
	case "$current" in
	/tmp/openwalla-*|/tmp/.openwalla*)
		if [ -n "$service" ] && [ -x "/etc/init.d/$service" ]; then
			case " $OPENWALLA_MIGRATED_SERVICES " in
			*" $service "*) ;;
			*)
				if /etc/init.d/"$service" status >/dev/null 2>&1; then
					/etc/init.d/"$service" stop >/dev/null 2>&1 || true
					OPENWALLA_MIGRATED_SERVICES="$OPENWALLA_MIGRATED_SERVICES $service"
				fi
				;;
			esac
		fi
		mkdir -p "$(dirname "$target")"
		if [ -d "$current" ]; then
			mkdir -p "$target"
			cp -R "$current"/. "$target"/ 2>/dev/null || true
		elif [ -f "$current" ] && [ ! -e "$target" ]; then
			cp -p "$current" "$target" 2>/dev/null || cp "$current" "$target" 2>/dev/null || true
		fi
		for suffix in -wal -shm; do
			if [ -f "$current$suffix" ] && [ ! -e "$target$suffix" ]; then
				cp -p "$current$suffix" "$target$suffix" 2>/dev/null || cp "$current$suffix" "$target$suffix" 2>/dev/null || true
			fi
		done
		set_uci "$key" "$target"
		OPENWALLA_CONFIG_CHANGED=1
		;;
	esac
}

migrate_openwalla_runtime_paths() {
	local service
	OPENWALLA_CONFIG_CHANGED=0
	OPENWALLA_MIGRATED_SERVICES=""
	migrate_openwalla_runtime_path openwalla.collector.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-netify.sqlite" openwalla-netify-collector
	migrate_openwalla_runtime_path openwalla.flow_stats.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-netify-flow-stats.sqlite" openwalla-netify-collector
	migrate_openwalla_runtime_path openwalla.connection_flows.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-connection-flows.sqlite" openwalla-connection-flows-collector
	migrate_openwalla_runtime_path openwalla.device_bandwidth.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-device-bandwidth.sqlite" openwalla-device-bandwidth-collector
	migrate_openwalla_runtime_path openwalla.devices.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-devices.sqlite" openwalla-devices-collector
	migrate_openwalla_runtime_path openwalla.parental.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-parental.sqlite"
	migrate_openwalla_runtime_path openwalla.ping_monitor.output_file "$OPENWALLA_RUNTIME_DIR/openwalla-ping-monitor.txt" openwalla-network-monitor
	migrate_openwalla_runtime_path openwalla.ping_monitor.state_file "$OPENWALLA_RUNTIME_DIR/openwalla-network-monitor.state" openwalla-network-monitor
	migrate_openwalla_runtime_path openwalla.ping_monitor.interface_state_file "$OPENWALLA_RUNTIME_DIR/openwalla-interface-monitor.state" openwalla-network-monitor
	migrate_openwalla_runtime_path openwalla.ping_monitor.wireguard_state_file "$OPENWALLA_RUNTIME_DIR/openwalla-wireguard-monitor.state" openwalla-network-monitor
	migrate_openwalla_runtime_path openwalla.dns_monitor.output_file "$OPENWALLA_RUNTIME_DIR/openwalla-dns-monitor.txt" openwalla-dns-monitor
	migrate_openwalla_runtime_path openwalla.speedtest_monitor.output_file "$OPENWALLA_RUNTIME_DIR/openwalla-speedtest-monitor.txt"
	migrate_openwalla_runtime_path openwalla.quarantine.state_file "$OPENWALLA_RUNTIME_DIR/openwalla-quarantine-known.txt"
	migrate_openwalla_runtime_path openwalla.notifications.db_path "$OPENWALLA_RUNTIME_DIR/openwalla-notifications.sqlite"
	if [ "$OPENWALLA_CONFIG_CHANGED" = "1" ]; then
		uci commit openwalla
		log "Migrated runtime files to $OPENWALLA_RUNTIME_DIR"
	fi
	for service in $OPENWALLA_MIGRATED_SERVICES; do
		/etc/init.d/"$service" start >/dev/null 2>&1 || true
	done
}

ensure_openwalla_config() {
	if [ ! -f /etc/config/openwalla ]; then
		install_file "$FILES_DIR/openwalla.config" /etc/config/openwalla 0644
	fi
	migrate_openwalla_runtime_paths
}

ensure_uci_section() {
	section="$1"
	type="$2"
	uci -q get "openwalla.$section" >/dev/null 2>&1 || uci set "openwalla.$section=$type"
}

install_rpcd_acl() {
	install_file "$RPCD_ACL" /usr/share/rpcd/acl.d/openwalla.json 0644
	/etc/init.d/rpcd restart || true
}

enable_restart_service() {
	svc="$1"
	if [ -x "/etc/init.d/$svc" ]; then
		/etc/init.d/"$svc" enable || true
		/etc/init.d/"$svc" restart || true
		log "Service restarted: $svc"
	else
		log "Service not found, skipping: $svc"
	fi
}

configure_vnstat_interface() {
	interface="${1:-br-lan}"

	if [ -f /etc/config/vnstat ]; then
		section="$(uci -q show vnstat 2>/dev/null | sed -n 's/^vnstat\.\([^.=]*\)=vnstat$/\1/p' | head -n 1)"
		if [ -z "$section" ]; then
			section="$(uci add vnstat vnstat)"
		fi
		if ! uci -q get "vnstat.$section.interface" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$interface"; then
			uci add_list "vnstat.$section.interface=$interface"
			uci commit vnstat
			log "Configured vnStat to monitor $interface"
		else
			log "vnStat already monitors $interface"
		fi
	fi

	if have_cmd vnstat; then
		vnstat --add -i "$interface" >/dev/null 2>&1 || \
			vnstat -u -i "$interface" >/dev/null 2>&1 || true
		log "Initialized the vnStat database for $interface"
	fi
}

reload_cron() {
	if [ -x /etc/init.d/cron ]; then
		/etc/init.d/cron enable >/dev/null 2>&1 || true
		/etc/init.d/cron restart >/dev/null 2>&1 || /etc/init.d/cron start >/dev/null 2>&1 || true
		return 0
	fi
	if [ -x /etc/init.d/crond ]; then
		/etc/init.d/crond enable >/dev/null 2>&1 || true
		/etc/init.d/crond restart >/dev/null 2>&1 || /etc/init.d/crond start >/dev/null 2>&1 || true
		return 0
	fi
	killall -HUP crond 2>/dev/null || true
}
