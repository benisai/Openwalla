#!/bin/sh

# Openwalla OpenWrt bootstrap script.
# Downloads and runs feature-focused installers from this repo.

set -u

log() {
	echo "[openwalla-setup] $*"
}

have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

OPENWALLA_GITHUB_REPO="${OPENWALLA_GITHUB_REPO:-benisai/openwalla-apk}"
OPENWALLA_GITHUB_REF="${OPENWALLA_GITHUB_REF:-main}"
OPENWALLA_RAW_BASE="${OPENWALLA_RAW_BASE:-https://raw.githubusercontent.com/$OPENWALLA_GITHUB_REPO/$OPENWALLA_GITHUB_REF/openwrt-setup}"
OPENWALLA_VERSION_URL="${OPENWALLA_VERSION_URL:-${OPENWALLA_RAW_BASE%/openwrt-setup}/pub_script_version.yaml}"
OPENWALLA_ROOT="${OPENWALLA_ROOT:-/root/openwalla}"
OPENWALLA_COMPONENT_VERSION="unknown"
STANDALONE_DIR="$OPENWALLA_ROOT/standalone"
STANDALONE_LIB_DIR="$STANDALONE_DIR/lib"

FEATURES=""
INSTALLERS=""
INSTALL_PROFILE=""
DRY_RUN=0
USED_FEATURE_ARGS=0
WITH_ADBLOCK=""
WITH_PBR=""
WITH_NETIFY=""
ACTION="install"

usage() {
	cat <<'EOF'
Usage:
  sh setup-openwrt-router.sh [feature ...] [options]
  sh setup-openwrt-router.sh uninstall [feature ...]

Examples:
  sh setup-openwrt-router.sh netify
  sh setup-openwrt-router.sh conntrack
  sh setup-openwrt-router.sh network-monitor dns speedtest
  sh setup-openwrt-router.sh monitoring
  sh setup-openwrt-router.sh stack --with-netify
  sh setup-openwrt-router.sh --profile=3
  sh setup-openwrt-router.sh uninstall network-monitor dns speedtest
  sh setup-openwrt-router.sh uninstall usage adblock netify

Feature groups:
  stack        Standard Openwrt apps plus Openwalla monitoring, usage,
               notifications, devices, blocking, state sync, and quarantine.
  monitoring   Standard apps plus usage, network, DNS, speedtest, notifications,
               devices, device bandwidth, and state sync.
  flows        Simple Conntrack flows plus detailed Netify flows.
  all          Everything in stack plus AdBlock, PBR, Netify, banIP, and SQM.

Individual features:
  standard          uhttpd-mod-ubus, nlbwmon, vnstat2/vnstat, sqlite, conntrack, qrencode
  usage            vnstat/nlbwmon usage support
  network-monitor  latency, outage, and Ethernet link monitor
  dns              DNS monitor script and init service
  speedtest        speedtest monitor script and cron
  notifications    notifications sqlite helper
  devices          devices sqlite collector
  device-speed     live per-device speed helper
  bandwidth        per-device bandwidth collector
  blocking         internet/parental blocking helper
  scheduler        device group block scheduler
  conntrack        simple flow collector
  netify           detailed Netify flow collector
  quarantine       device quarantine helper service
  state-sync       Openwalla state backup/sync helper
  wireguard        WireGuard packages and LuCI protocol support
  adblock          OpenWrt adblock packages and config
  ddns             OpenWrt dynamic DNS packages and service
  banip            OpenWrt banIP packages and config
  pbr              OpenWrt PBR packages and config
  qos              Smart Queue/SQM packages
  tor              Tor transparent proxy support
  tailscale        Tailscale mesh VPN and subnet routing support
  mwan3            Multi-WAN failover and load balancing support
  geoip             Country blocking with geoip-shell

Compatibility options:
  --profile=1         Same as stack
  --profile=2         Stack + AdBlock + PBR
  --profile=3         Stack + AdBlock + PBR + Netify
  --with-netify       Add Netify to the selected profile/group
  --without-netify    Remove Netify from the selected profile/group
  --with-adblock      Add AdBlock to the selected profile/group
  --without-adblock   Remove AdBlock from the selected profile/group
  --with-pbr          Add PBR to the selected profile/group
  --without-pbr       Remove PBR from the selected profile/group
  --dry-run           Show what would run without installing
  --help              Show this help

Environment:
  OPENWALLA_RAW_BASE   Override raw GitHub setup URL
  OPENWALLA_ROOT       Override install download dir (default: /root/openwalla)
EOF
}

append_feature() {
	feature="$1"
	case " $FEATURES " in
	*" $feature "*) ;;
	*) FEATURES="$FEATURES $feature" ;;
	esac
}

remove_feature() {
	target="$1"
	next_features=""
	for feature in $FEATURES; do
		if [ "$feature" != "$target" ]; then
			next_features="$next_features $feature"
		fi
	done
	FEATURES="$next_features"
}

append_installer() {
	installer="$1"
	case " $INSTALLERS " in
	*" $installer "*) ;;
	*) INSTALLERS="$INSTALLERS $installer" ;;
	esac
}

feature_to_installer() {
	case "$1" in
	standard) echo "install-standard-apps.sh" ;;
	usage) echo "install-usage-monitoring.sh" ;;
	network-monitor) echo "install-network-monitor.sh" ;;
	dns) echo "install-dns-monitor.sh" ;;
	speedtest) echo "install-speedtest-monitor.sh" ;;
	notifications) echo "install-notifications-db.sh" ;;
	devices) echo "install-devices-collector.sh" ;;
	device-speed) echo "install-device-speed.sh" ;;
	bandwidth) echo "install-device-bandwidth.sh" ;;
	blocking) echo "install-internet-blocking.sh" ;;
	scheduler) echo "install-scheduler.sh" ;;
	conntrack) echo "install-conntrack.sh" ;;
	netify) echo "install-netify.sh" ;;
	quarantine) echo "install-quarantine.sh" ;;
	state-sync) echo "install-state-sync.sh" ;;
	wireguard) echo "install-wireguard.sh" ;;
	adblock) echo "install-adblock.sh" ;;
	ddns) echo "install-ddns.sh" ;;
	banip) echo "install-banip.sh" ;;
	pbr) echo "install-pbr.sh" ;;
	qos) echo "install-qos-scripts.sh" ;;
	tor) echo "install-tor.sh" ;;
	tailscale) echo "install-tailscale.sh" ;;
	mwan3) echo "install-mwan3.sh" ;;
	geoip) echo "install-geoip-shell.sh" ;;
	*) return 1 ;;
	esac
}

canonical_feature() {
	case "$1" in
	apps|packages|standard-apps) echo "standard" ;;
	usage|statistics|stats|vnstat|nlbwmon) echo "usage" ;;
	network|network-monitor) echo "network-monitor" ;;
	dns|dns-test|dns-monitor) echo "dns" ;;
	speedtest|speed-test|speedtest-monitor) echo "speedtest" ;;
	notifications|notification|notifications-db) echo "notifications" ;;
	devices|device-db|devices-collector) echo "devices" ;;
	device-speed|live-speed|speed-helper|traffic-summary|device-traffic-summary) echo "device-speed" ;;
	bandwidth|device-bandwidth|device-bandwidth-collector) echo "bandwidth" ;;
	blocking|internet-blocking|parental-blocking|paternal-pause) echo "blocking" ;;
	scheduler|schedules|device-scheduler|block-scheduler) echo "scheduler" ;;
	conntrack|simple-flow|simple-flows|connection-flows) echo "conntrack" ;;
	netify|detailed-flow|detailed-flows) echo "netify" ;;
	quarantine|device-quarantine) echo "quarantine" ;;
	state-sync|state|backup|sync) echo "state-sync" ;;
	wireguard|wg|vpn) echo "wireguard" ;;
	adblock|ad-block) echo "adblock" ;;
	ddns|dynamic-dns) echo "ddns" ;;
	banip|ban-ip) echo "banip" ;;
	pbr) echo "pbr" ;;
	qos|sqm|smart-queue|smartqueue) echo "qos" ;;
	tor|onion) echo "tor" ;;
	tailscale|tailnet|mesh-vpn) echo "tailscale" ;;
	mwan3|multi-wan|multiwan) echo "mwan3" ;;
	geoip|geo-blocking|geoblocking|country-blocking) echo "geoip" ;;
	*) return 1 ;;
	esac
}

append_monitoring_features() {
	append_feature standard
	append_feature usage
	append_feature network-monitor
	append_feature dns
	append_feature speedtest
	append_feature notifications
	append_feature devices
	append_feature bandwidth
	append_feature state-sync
}

append_stack_features() {
	append_monitoring_features
	append_feature blocking
	append_feature scheduler
	append_feature quarantine
}

append_all_features() {
	append_stack_features
	append_feature adblock
	append_feature pbr
	append_feature banip
	append_feature qos
	append_feature tor
}

append_feature_arg() {
	arg="$1"
	case "$arg" in
	stack|profile1|default)
		append_stack_features
		;;
	monitoring|monitors)
		append_monitoring_features
		;;
	all|everything|profile3)
		append_all_features
		;;
	profile2)
		append_stack_features
		append_feature adblock
		append_feature pbr
		;;
	*)
		if canonical="$(canonical_feature "$arg")"; then
			append_feature "$canonical"
		else
			echo "Unknown feature: $arg"
			usage
			exit 1
		fi
		;;
	esac
}

prompt_install_profile() {
	while true; do
		cat <<'EOF'

Select installation profile:
  1) Install Openwalla Stack
  2) Install Openwalla Stack + AdBlock + PBR
  3) Install Openwalla Stack + AdBlock + PBR + Netify
EOF
		printf "Enter option [1-3] (default: 1): "
		read -r choice
		choice="${choice:-1}"
		case "$choice" in
		1|2|3)
			INSTALL_PROFILE="$choice"
			return 0
			;;
		*)
			echo "Invalid selection: $choice"
			;;
		esac
	done
}

append_profile_features() {
	case "$1" in
	1)
		append_stack_features
		;;
	2)
		append_stack_features
		append_feature adblock
		append_feature pbr
		;;
	3)
		append_stack_features
		append_feature adblock
		append_feature pbr
		;;
	*)
		echo "Invalid profile: $1"
		exit 1
		;;
	esac
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
	echo "Neither wget nor curl is available; cannot download $url"
	return 1
}

load_component_version() {
	version_file="/tmp/openwalla-pub-script-version.$$"
	if download_file "$OPENWALLA_VERSION_URL" "$version_file"; then
		OPENWALLA_COMPONENT_VERSION="$(awk -F ': *' '$1 == "version" { print $2; exit }' "$version_file")"
	fi
	rm -f "$version_file"
	[ -n "$OPENWALLA_COMPONENT_VERSION" ] || OPENWALLA_COMPONENT_VERSION="unknown"
}

download_standalone_runtime() {
	log "Preparing installer runtime in $OPENWALLA_ROOT"
	mkdir -p "$STANDALONE_LIB_DIR"

	download_file "$OPENWALLA_RAW_BASE/standalone/lib/openwalla-standalone-common.sh" \
		"$STANDALONE_LIB_DIR/openwalla-standalone-common.sh" || exit 1
	chmod 0755 "$STANDALONE_LIB_DIR/openwalla-standalone-common.sh"

	for installer in $INSTALLERS; do
		download_file "$OPENWALLA_RAW_BASE/standalone/$installer" "$STANDALONE_DIR/$installer" || exit 1
		chmod 0755 "$STANDALONE_DIR/$installer"
	done
}

detect_package_manager() {
	if have_cmd opkg; then
		echo "opkg"
	elif have_cmd apk; then
		echo "apk"
	else
		echo ""
	fi
}

update_package_feeds_once() {
	pkg_mgr="$(detect_package_manager)"
	case "$pkg_mgr" in
	opkg)
		log "Updating opkg package feeds"
		opkg update
		;;
	apk)
		log "Updating apk package indexes"
		apk update
		;;
	*)
		log "No supported package manager found (opkg/apk). Package install steps may be skipped."
		;;
	esac
	export OPENWALLA_PACKAGE_FEEDS_UPDATED=1
}

resolve_installers() {
	INSTALLERS=""
	for feature in $FEATURES; do
		if installer="$(feature_to_installer "$feature")"; then
			append_installer "$installer"
		else
			echo "No installer mapped for feature: $feature"
			exit 1
		fi
	done
}

run_installers() {
	for installer in $INSTALLERS; do
		log "Running $installer"
		if ! OPENWALLA_PACKAGE_FEEDS_UPDATED=1 sh "$STANDALONE_DIR/$installer"; then
			echo "[openwalla-setup] Installer failed: $installer" >&2
			exit 1
		fi
	done
}

pkg_installed() {
	pkg="$1"
	pkg_mgr="$(detect_package_manager)"
	case "$pkg_mgr" in
	opkg) opkg list-installed | grep -q "^$pkg -" ;;
	apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

remove_pkg_if_installed() {
	pkg="$1"
	pkg_mgr="$(detect_package_manager)"
	if ! pkg_installed "$pkg"; then
		log "Package not installed, skipping remove: $pkg"
		return 0
	fi
	case "$pkg_mgr" in
	opkg) opkg remove "$pkg" || true ;;
	apk) apk del "$pkg" || true ;;
	esac
	log "Removed package if unused: $pkg"
}

stop_disable_service() {
	svc="$1"
	if [ -x "/etc/init.d/$svc" ]; then
		/etc/init.d/"$svc" stop >/dev/null 2>&1 || true
		/etc/init.d/"$svc" disable >/dev/null 2>&1 || true
		log "Stopped service: $svc"
	fi
}

remove_cron_marker() {
	marker="$1"
	cron_path="/etc/crontabs/root"
	tmp_cron="/tmp/.openwalla_uninstall_cron.$$"
	[ -f "$cron_path" ] || return 0
	grep -v "$marker" "$cron_path" >"$tmp_cron" 2>/dev/null || : >"$tmp_cron"
	cp "$tmp_cron" "$cron_path"
	rm -f "$tmp_cron"
	/bin/sh -c '/etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || /etc/init.d/crond reload 2>/dev/null || /etc/init.d/crond restart 2>/dev/null || killall -HUP crond 2>/dev/null || true'
}

clear_openwalla_section() {
	section="$1"
	uci -q delete "openwalla.$section" >/dev/null 2>&1 || true
}

uninstall_feature() {
	feature="$1"
	log "Uninstalling feature: $feature"
	case "$feature" in
	standard)
		remove_pkg_if_installed uhttpd-mod-ubus
		remove_pkg_if_installed qrencode
		;;
	usage)
		stop_disable_service vnstat
		stop_disable_service nlbwmon
		remove_pkg_if_installed luci-app-nlbwmon
		remove_pkg_if_installed nlbwmon
		remove_pkg_if_installed luci-app-vnstat2
		remove_pkg_if_installed luci-app-vnstat
		remove_pkg_if_installed vnstati2
		remove_pkg_if_installed vnstati
		remove_pkg_if_installed vnstat2
		remove_pkg_if_installed vnstat
		clear_openwalla_section dashboard
		;;
	network-monitor)
		stop_disable_service openwalla-network-monitor
		rm -f /usr/bin/openwalla-network-monitor /etc/init.d/openwalla-network-monitor
		clear_openwalla_section ping_monitor
		;;
	dns)
		stop_disable_service openwalla-dns-monitor
		rm -f /usr/bin/openwalla-dns-monitor /etc/init.d/openwalla-dns-monitor
		clear_openwalla_section dns_monitor
		;;
	speedtest)
		remove_cron_marker "OPENWALLA_SPEEDTEST_MONITOR"
		rm -f /usr/bin/openwalla-speedtest-monitor
		clear_openwalla_section speedtest_monitor
		;;
	notifications)
		rm -f /usr/bin/openwalla-notifications-db
		clear_openwalla_section notifications
		;;
	devices)
		stop_disable_service openwalla-devices-collector
		rm -f /usr/bin/openwalla-devices-collector /etc/init.d/openwalla-devices-collector
		clear_openwalla_section devices
		;;
	bandwidth)
		stop_disable_service openwalla-device-bandwidth-collector
		rm -f /usr/bin/openwalla-device-bandwidth-collector /usr/bin/openwalla-device-traffic-summary /etc/init.d/openwalla-device-bandwidth-collector
		clear_openwalla_section device_bandwidth
		;;
	device-speed)
		rm -f /usr/bin/openwalla-device-traffic-summary
		;;
	blocking)
		remove_cron_marker "OPENWALLA_PATERNAL_PAUSE"
		rm -f /usr/bin/openwalla-paternal-pause
		uci -q delete openwalla.features.quarantine >/dev/null 2>&1 || true
		;;
	scheduler)
		remove_cron_marker "OPENWALLA_SCHEDULER"
		rm -f /usr/bin/openwalla-scheduler /usr/bin/openwalla-parental
		clear_openwalla_section scheduler
		clear_openwalla_section parental
		uci -q delete openwalla.features.scheduler >/dev/null 2>&1 || true
		;;
	conntrack)
		stop_disable_service openwalla-connection-flows-collector
		rm -f /usr/bin/openwalla-connection-flow-collector /etc/init.d/openwalla-connection-flows-collector
		clear_openwalla_section connection_flows
		;;
	netify)
		stop_disable_service openwalla-netify-collector
		rm -f /usr/bin/openwalla-netify-collector /etc/init.d/openwalla-netify-collector
		clear_openwalla_section collector
		clear_openwalla_section flow_stats
		uci -q delete openwalla.features.netify >/dev/null 2>&1 || true
		remove_pkg_if_installed netifyd
		;;
	quarantine)
		rm -f /etc/hotplug.d/dhcp/95-openwalla-quarantine /etc/hotplug.d/neigh/95-openwalla-quarantine
		uci -q set openwalla.quarantine.enabled='0' >/dev/null 2>&1 || true
		uci -q delete openwalla.features.quarantine >/dev/null 2>&1 || true
		;;
	state-sync)
		stop_disable_service openwalla-state-sync
		rm -f /usr/bin/openwalla-state-sync /etc/init.d/openwalla-state-sync
		clear_openwalla_section state_backup
		;;
	wireguard)
		uci -q delete openwalla.features.wireguard >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-wireguard
		remove_pkg_if_installed luci-proto-wireguard
		remove_pkg_if_installed wireguard-tools
		;;
	adblock)
		stop_disable_service adblock
		uci -q delete openwalla.features.adblock >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-adblock
		remove_pkg_if_installed adblock
		;;
	ddns)
		stop_disable_service ddns
		uci -q delete openwalla.features.ddns >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-ddns
		remove_pkg_if_installed ddns-scripts-services
		remove_pkg_if_installed ddns-scripts
		;;
	banip)
		stop_disable_service banip
		uci -q delete openwalla.features.banip >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-banip
		remove_pkg_if_installed banip
		;;
	pbr)
		stop_disable_service pbr
		uci -q delete openwalla.features.pbr >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-pbr
		remove_pkg_if_installed pbr
		;;
	qos)
		stop_disable_service sqm
		uci -q delete openwalla.features.qosify >/dev/null 2>&1 || true
		uci -q delete openwalla.features.sqm >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-sqm
		remove_pkg_if_installed sqm-scripts
		;;
	tailscale)
		stop_disable_service tailscale
		rm -f /usr/bin/openwalla-tailscale
		clear_openwalla_section tailscale
		uci -q delete network.tailscale >/dev/null 2>&1 || true
		uci -q delete firewall.tailscale >/dev/null 2>&1 || true
		uci -q delete firewall.openwalla_tailscale_lan >/dev/null 2>&1 || true
		uci -q delete firewall.openwalla_tailscale_wan >/dev/null 2>&1 || true
		uci commit network
		uci commit firewall
		remove_pkg_if_installed tailscale
		;;
	mwan3)
		stop_disable_service mwan3
		uci -q delete openwalla.features.mwan3 >/dev/null 2>&1 || true
		remove_pkg_if_installed luci-app-mwan3
		remove_pkg_if_installed mwan3
		;;
	geoip)
		if command -v geoip-shell-uninstall.sh >/dev/null 2>&1; then
			geoip-shell-uninstall.sh || true
		fi
		;;
	tor)
		[ -x /usr/bin/openwalla-tor ] && /usr/bin/openwalla-tor disable >/dev/null 2>&1 || true
		[ -x /usr/bin/openwalla-tor ] && /usr/bin/openwalla-tor unconfigure >/dev/null 2>&1 || true
		stop_disable_service tor
		rm -f /usr/bin/openwalla-tor
		clear_openwalla_section tor
		uci -q delete openwalla.features.tor >/dev/null 2>&1 || true
		remove_pkg_if_installed tor-geoip
		remove_pkg_if_installed tor
		;;
	*)
		echo "Unknown uninstall feature: $feature" >&2
		return 1
		;;
	esac
	uci commit openwalla >/dev/null 2>&1 || true
}

run_uninstallers() {
	for feature in $FEATURES; do
		uninstall_feature "$feature"
	done
	log "Uninstall complete."
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	uninstall|remove)
		ACTION="uninstall"
		;;
	--profile=*)
		INSTALL_PROFILE="${1#*=}"
		;;
	--with-netify)
		WITH_NETIFY=1
		;;
	--without-netify)
		WITH_NETIFY=0
		;;
	--with-adblock)
		WITH_ADBLOCK=1
		;;
	--without-adblock)
		WITH_ADBLOCK=0
		;;
	--with-pbr)
		WITH_PBR=1
		;;
	--without-pbr)
		WITH_PBR=0
		;;
	--dry-run)
		DRY_RUN=1
		;;
	--help|-h)
		usage
		exit 0
		;;
	--*)
		echo "Unknown option: $1"
		usage
		exit 1
		;;
	*)
		USED_FEATURE_ARGS=1
		append_feature_arg "$1"
		;;
	esac
	shift
done

if [ "$ACTION" = "uninstall" ]; then
	:
elif [ -n "$INSTALL_PROFILE" ]; then
	append_profile_features "$INSTALL_PROFILE"
elif [ "$USED_FEATURE_ARGS" = "0" ]; then
	if [ -t 0 ]; then
		prompt_install_profile
		append_profile_features "$INSTALL_PROFILE"
	else
		append_stack_features
	fi
fi

[ "$WITH_NETIFY" = "1" ] && append_feature netify
[ "$WITH_NETIFY" = "0" ] && remove_feature netify
[ "$WITH_ADBLOCK" = "1" ] && append_feature adblock
[ "$WITH_ADBLOCK" = "0" ] && remove_feature adblock
[ "$WITH_PBR" = "1" ] && append_feature pbr
[ "$WITH_PBR" = "0" ] && remove_feature pbr

if [ -z "$FEATURES" ]; then
	if [ "$ACTION" = "uninstall" ]; then
		echo "Choose at least one feature to uninstall."
	else
		echo "No features selected."
	fi
	usage
	exit 1
fi

if [ "$ACTION" = "install" ]; then
	resolve_installers
fi

log "Selected action: $ACTION"
log "Selected features:$FEATURES"
if [ "$ACTION" = "install" ]; then
	log "Installer order:$INSTALLERS"
	case " $FEATURES " in
	*" netify "*|*" conntrack "*)
		log "WARNING: Flow collectors can be heavy. Routers with less than 512 MB RAM or fewer than 4 CPU cores may slow down or crash."
		;;
	esac
fi

if [ "$DRY_RUN" = "1" ]; then
	exit 0
fi

if [ "$(id -u)" != "0" ]; then
	echo "Run as root."
	exit 1
fi

if [ "$ACTION" = "uninstall" ]; then
	run_uninstallers
	exit 0
fi

update_package_feeds_once
load_component_version
download_standalone_runtime
run_installers

uci -q get openwalla.core >/dev/null 2>&1 || uci set openwalla.core='core'
uci set openwalla.core.component_version="$OPENWALLA_COMPONENT_VERSION"
uci commit openwalla

log "Setup complete."
log "Installed feature bundles:$FEATURES"
