#!/bin/sh

# Openwalla Tailscale manager for OpenWrt.

set -u

mkdir -p /tmp/openwalla

find_tailscale() {
	command -v tailscale 2>/dev/null || true
}

detect_lan_subnet() {
	ip -o -4 route show dev br-lan 2>/dev/null | awk '$1 ~ /\// { print $1; exit }'
}

ensure_firewall() {
	local advertise_lan advertise_exit
	advertise_lan="$(uci -q get openwalla.tailscale.advertise_lan 2>/dev/null || echo 0)"
	advertise_exit="$(uci -q get openwalla.tailscale.advertise_exit_node 2>/dev/null || echo 0)"
	uci -q get network.tailscale >/dev/null 2>&1 || uci set network.tailscale=interface
	uci set network.tailscale.proto='none'
	uci set network.tailscale.device='tailscale0'

	uci -q get firewall.tailscale >/dev/null 2>&1 || uci set firewall.tailscale=zone
	uci set firewall.tailscale.name='tailscale'
	uci set firewall.tailscale.input='ACCEPT'
	uci set firewall.tailscale.output='ACCEPT'
	uci set firewall.tailscale.forward='ACCEPT'
	uci set firewall.tailscale.masq='1'
	uci set firewall.tailscale.mtu_fix='1'
	uci -q delete firewall.tailscale.network >/dev/null 2>&1 || true
	uci add_list firewall.tailscale.network='tailscale'

	uci -q delete firewall.openwalla_tailscale_lan >/dev/null 2>&1 || true
	if [ "$advertise_lan" = '1' ]; then
		uci set firewall.openwalla_tailscale_lan=forwarding
		uci set firewall.openwalla_tailscale_lan.src='tailscale'
		uci set firewall.openwalla_tailscale_lan.dest='lan'
	fi
	uci -q delete firewall.openwalla_tailscale_wan >/dev/null 2>&1 || true
	if [ "$advertise_exit" = '1' ]; then
		uci set firewall.openwalla_tailscale_wan=forwarding
		uci set firewall.openwalla_tailscale_wan.src='tailscale'
		uci set firewall.openwalla_tailscale_wan.dest='wan'
	fi
	uci commit network
	uci commit firewall
	/etc/init.d/network reload >/dev/null 2>&1 || true
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
}

show_status() {
	local bin backend ip hostname subnet
	bin="$(find_tailscale)"
	[ -n "$bin" ] || { echo 'INSTALLED=0'; return 0; }
	backend="$($bin status --json 2>/dev/null | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	ip="$($bin ip -4 2>/dev/null | head -n1 || true)"
	hostname="$($bin status --json 2>/dev/null | sed -n 's/.*"HostName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	subnet="$(uci -q get openwalla.tailscale.lan_subnet 2>/dev/null || true)"
	[ -n "$subnet" ] || subnet="$(detect_lan_subnet)"
	echo 'INSTALLED=1'
	echo "RUNNING=$([ -x /etc/init.d/tailscale ] && /etc/init.d/tailscale running >/dev/null 2>&1 && echo 1 || echo 0)"
	echo "BACKEND=${backend:-Stopped}"
	echo "IP=$ip"
	echo "HOSTNAME=$hostname"
	echo "ADVERTISE_LAN=$(uci -q get openwalla.tailscale.advertise_lan 2>/dev/null || echo 0)"
	echo "LAN_SUBNET=$subnet"
	echo "ACCEPT_ROUTES=$(uci -q get openwalla.tailscale.accept_routes 2>/dev/null || echo 0)"
	echo "ADVERTISE_EXIT_NODE=$(uci -q get openwalla.tailscale.advertise_exit_node 2>/dev/null || echo 0)"
}

login() {
	local bin log_file pid count url
	bin="$(find_tailscale)"
	[ -n "$bin" ] || { echo 'Tailscale is not installed.' >&2; exit 1; }
	/etc/init.d/tailscale enable >/dev/null 2>&1 || true
	/etc/init.d/tailscale start >/dev/null 2>&1 || true
	log_file='/tmp/openwalla/openwalla-tailscale-login.log'
	: >"$log_file"
	"$bin" up --timeout=5m >"$log_file" 2>&1 &
	pid=$!
	count=0
	while [ "$count" -lt 15 ]; do
		url="$(grep -Eo 'https://[^[:space:]]+' "$log_file" 2>/dev/null | head -n1 || true)"
		if [ -n "$url" ]; then
			echo "AUTH_URL=$url"
			echo "LOGIN_PID=$pid"
			return 0
		fi
		kill -0 "$pid" >/dev/null 2>&1 || break
		sleep 1
		count=$((count + 1))
	done
	cat "$log_file"
	$bin status >/dev/null 2>&1 && return 0
	return 1
}

apply_settings() {
	local bin advertise subnet accept_routes exit_node routes_arg
	bin="$(find_tailscale)"
	[ -n "$bin" ] || { echo 'Tailscale is not installed.' >&2; exit 1; }
	advertise="$(uci -q get openwalla.tailscale.advertise_lan 2>/dev/null || echo 0)"
	subnet="$(uci -q get openwalla.tailscale.lan_subnet 2>/dev/null || true)"
	[ -n "$subnet" ] || subnet="$(detect_lan_subnet)"
	accept_routes="$(uci -q get openwalla.tailscale.accept_routes 2>/dev/null || echo 0)"
	exit_node="$(uci -q get openwalla.tailscale.advertise_exit_node 2>/dev/null || echo 0)"
	routes_arg=''
	[ "$advertise" = '1' ] && routes_arg="$subnet"
	ensure_firewall
	"$bin" set \
		--advertise-routes="$routes_arg" \
		--snat-subnet-routes=false \
		--accept-routes="$([ "$accept_routes" = '1' ] && echo true || echo false)" \
		--advertise-exit-node="$([ "$exit_node" = '1' ] && echo true || echo false)"
}

case "${1:-status}" in
	status) show_status ;;
	configure) ensure_firewall ;;
	login) login ;;
	apply) apply_settings ;;
	down) "$(find_tailscale)" down ;;
	restart) /etc/init.d/tailscale restart ;;
	*) echo "Usage: $0 {status|configure|login|apply|down|restart}" >&2; exit 2 ;;
esac
