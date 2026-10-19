#!/bin/sh

# Shared by the app and collector. This file only defines a function when sourced.
openwalla_device_access() (
	action="${1:-}" reason="${2:-}" mac="$(printf '%s' "${3:-}" | tr '[:upper:]' '[:lower:]')"
	requested_reason="$reason"
	operation="${4:-}"
	case "$operation" in *[!a-zA-Z0-9_-]*) exit 2 ;; esac
	case "$action:$reason" in block:manual|block:quarantine|release:manual|release:quarantine|release:current|clear:all) ;; *) echo 'Invalid device access action' >&2; exit 2 ;; esac
	case "$mac" in
	[0-9a-f][02468ace]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) ;;
	*) echo 'Invalid unicast device MAC' >&2; exit 2 ;;
	esac
	[ "$mac" != 00:00:00:00:00:00 ] || exit 2
	if [ "$action" = block ]; then
		for address in /sys/class/net/*/address; do
			[ -r "$address" ] || continue
			[ "$(tr '[:upper:]' '[:lower:]' <"$address")" != "$mac" ] || {
				echo 'Cannot block a router interface' >&2; exit 2;
			}
		done
	fi
	runtime="${OPENWALLA_ACCESS_RUNTIME_DIR:-/tmp/openwalla}"
	config_dir="${OPENWALLA_ACCESS_CONFIG_DIR:-/etc/config}"
	mkdir -p "$runtime" || exit 1
	lock="$runtime/device-access.lock"
	attempt=0
	until mkdir "$lock" 2>/dev/null; do
		owner="$(cat "$lock/pid" 2>/dev/null)"
		case "$owner" in ''|*[!0-9]*) ;; *)
			if ! kill -0 "$owner" 2>/dev/null; then
				rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true
				continue
			fi ;;
		esac
		attempt=$((attempt + 1))
		[ "$attempt" -lt 30 ] || { echo 'Device access is busy; retry' >&2; exit 1; }
		sleep 1
	done
	echo "$$" >"$lock/pid"
	work="$(mktemp -d "$runtime/device-access.XXXXXX")" || { rm -f "$lock/pid"; rmdir "$lock"; exit 1; }
	trap 'rm -rf "$work"; rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true' EXIT
	trap 'exit 1' HUP INT TERM
	result_dir="$runtime/device-access-results"
	mkdir -p "$result_dir" || exit 1
	expected="OPENWALLA_DEVICE_ACCESS_OK|$action|$requested_reason|$mac"
	if [ -n "$operation" ] && [ -f "$result_dir/$operation" ]; then
		grep -Fx "$expected" "$result_dir/$operation" || exit 1
		exit 0
	fi
	find "$result_dir" -type f -mtime +1 -exec rm -f {} \; 2>/dev/null || true
	mkdir -p "$work/config" "$work/delta" || exit 1
	cp -p "$config_dir/firewall" "$work/original" || exit 1
	cp -p "$work/original" "$work/config/firewall" || exit 1
	# Never incorporate another CLI writer's uncommitted firewall changes.
	[ ! -s /tmp/.uci/firewall ] || { echo 'Save or revert pending firewall changes first' >&2; exit 1; }
	oa_uci() { uci -c "$work/config" -t "$work/delta" "$@"; }
	oa_get() { oa_uci -q get "firewall.$1"; }
	oa_sections() { oa_uci -q show firewall | sed -n 's/^firewall\.\([^.=]*\)=rule$/\1/p'; }
	oa_has_mac() {
		{ oa_get "$1.src_mac"; oa_get "$1.src_mac_address"; } 2>/dev/null |
			tr '[:upper:]' '[:lower:]' | tr ' ' '\n' | grep -qx "$mac"
	}
	legacy_manual=0
	for section in $(oa_sections); do
		oa_has_mac "$section" || continue
		[ "$(oa_get "$section.enabled" 2>/dev/null)" != 0 ] || continue
		case "$(oa_get "$section.name")" in openwalla_quarantine_*_router) legacy_manual=1 ;; esac
	done
	oa_reason() {
		case "$1" in
		owrt_device_block_*) echo manual ;;
		openwalla_quarantine_*) [ "$legacy_manual" = 1 ] && echo manual || echo quarantine ;;
		esac
	}
	if [ "$reason" = current ]; then
		reason=manual
		for section in $(oa_sections); do
			oa_has_mac "$section" || continue
			if [ "$(oa_reason "$(oa_get "$section.name")")" = quarantine ]; then
				reason=quarantine; break
			fi
		done
	fi
	# Remove only this reason's MAC membership. Other devices and policies survive.
	: >"$work/removed-names"
	for section in $(oa_sections); do
		oa_has_mac "$section" || continue
		owned="$(oa_reason "$(oa_get "$section.name")")"
		[ -n "$owned" ] || continue
		[ "$reason" = all ] || [ "$owned" = "$reason" ] || continue
		oa_get "$section.name" >>"$work/removed-names"
		for option in src_mac src_mac_address; do
			values="$(oa_get "$section.$option" 2>/dev/null)"
			[ -n "$values" ] || continue
			oa_uci -q delete "firewall.$section.$option" || exit 1
			for value in $values; do
				[ "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" = "$mac" ] && continue
				oa_uci add_list "firewall.$section.$option=$value" || exit 1
			done
		done
		remaining="$(oa_get "$section.src_mac" 2>/dev/null)$(oa_get "$section.src_mac_address" 2>/dev/null)"
		[ -n "$remaining" ] || oa_uci delete "firewall.$section" || exit 1
	done
	base="$(printf '%s' "$mac" | tr -d ':')"
	case "$reason" in manual) base="owrt_device_block_$base" ;; *) base="openwalla_quarantine_$base" ;; esac
	if [ "$action" = block ]; then
		scopes=forward
		[ "$reason" != manual ] || scopes='forward router'
		for scope in $scopes; do
			section="$(oa_uci add firewall rule)" || exit 1
			[ -n "$section" ] || exit 1
			oa_uci set "firewall.$section.name=${base}_$scope" || exit 1
			oa_uci set "firewall.$section.src=*" || exit 1
			[ "$scope" != forward ] || oa_uci set "firewall.$section.dest=*" || exit 1
			oa_uci set "firewall.$section.src_mac=$mac" || exit 1
			oa_uci set "firewall.$section.proto=all" || exit 1
			oa_uci set "firewall.$section.family=any" || exit 1
			oa_uci set "firewall.$section.target=DROP" || exit 1
			oa_uci set "firewall.$section.enabled=1" || exit 1
		done
	fi
	oa_uci commit firewall || exit 1
	# Refuse to overwrite a configuration another writer changed during planning.
	cmp -s "$config_dir/firewall" "$work/original" || { echo 'Firewall changed; retry' >&2; exit 1; }
	[ ! -s /tmp/.uci/firewall ] || { echo 'Firewall has pending changes; retry' >&2; exit 1; }
	# Publish on the same filesystem so readers never see a partially written file.
	staged="$config_dir/.openwalla-firewall.$$"
	cp -p "$work/config/firewall" "$staged" && mv "$staged" "$config_dir/firewall" || exit 1
	oa_reload() { "${OPENWALLA_ACCESS_FIREWALL_INIT:-/etc/init.d/firewall}" reload; }
	oa_runtime() {
		if command -v nft >/dev/null 2>&1; then
			nft list table inet fw4 && return 0
		fi
		if command -v iptables-save >/dev/null 2>&1; then
			iptables-save || return 1
			if command -v ip6tables-save >/dev/null 2>&1; then ip6tables-save || return 1; fi
		else
			return 1
		fi
	}
	verified=0
	if oa_reload >"$runtime/device-access-apply.log" 2>&1 && oa_runtime >"$work/runtime" 2>/dev/null; then
		verified=1
		if [ "$action" = block ]; then
			for scope in $scopes; do
				grep -F "${base}_$scope" "$work/runtime" | grep -qi "$mac" || verified=0
			done
		else
			# Reload also removes untracked runtime rules from older app versions.
			for section in $(oa_sections); do
				oa_has_mac "$section" || continue
				owned="$(oa_reason "$(oa_get "$section.name")")"
				if [ -n "$owned" ] && { [ "$reason" = all ] || [ "$owned" = "$reason" ]; }; then verified=0; fi
			done
			while IFS= read -r name; do
				grep -F "$name" "$work/runtime" | grep -qi "$mac" && verified=0
			done <"$work/removed-names"
		fi
	fi
	if [ "$verified" != 1 ]; then
		if cmp -s "$config_dir/firewall" "$work/config/firewall"; then
			cp -p "$work/original" "$staged" && mv "$staged" "$config_dir/firewall"
			oa_reload >>"$runtime/device-access-apply.log" 2>&1 || true
		fi
		echo 'Firewall apply could not be verified; device access change failed' >&2
		exit 1
	fi
	# Established flows can otherwise bypass a new rule's connection-state check.
	if [ "$action" = block ] && command -v conntrack >/dev/null 2>&1; then
		{
			ip neigh show 2>/dev/null | awk -v mac="$mac" '{for(i=1;i<=NF;i++) if($i=="lladdr" && tolower($(i+1))==mac) print $1}'
			[ ! -r /tmp/dhcp.leases ] || awk -v mac="$mac" 'tolower($2)==mac {print $3}' /tmp/dhcp.leases
		} | sort -u | while IFS= read -r address; do
			case "$address" in ''|*[!0-9a-fA-F:.]*) continue ;; esac
			family=ipv4; case "$address" in *:*) family=ipv6 ;; esac
			conntrack -D -f "$family" -s "$address" >/dev/null 2>&1 || true
			conntrack -D -f "$family" -d "$address" >/dev/null 2>&1 || true
		done
	fi
	if [ -n "$operation" ]; then
		printf '%s\n' "$expected" >"$result_dir/.$operation" &&
			mv "$result_dir/.$operation" "$result_dir/$operation" || exit 1
	fi
	printf '%s\n' "$expected"
)
