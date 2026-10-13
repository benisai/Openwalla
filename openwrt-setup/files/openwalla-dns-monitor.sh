#!/bin/sh

# Openwalla DNS Monitor
# Runs continuously on OpenWrt and writes DNS resolution samples to /tmp/openwalla/openwalla-dns-monitor.txt

set -u

mkdir -p /tmp/openwalla

DEFAULT_TARGET="openwrt.org"
DEFAULT_INTERVAL="60"
DEFAULT_TIMEOUT="3"
DEFAULT_OUTPUT="/tmp/openwalla/openwalla-dns-monitor.txt"
DEFAULT_MAX_LINES="2000"

DNS_TARGET="$DEFAULT_TARGET"
DNS_INTERVAL="$DEFAULT_INTERVAL"
DNS_TIMEOUT="$DEFAULT_TIMEOUT"
DNS_OUTPUT="$DEFAULT_OUTPUT"
DNS_MAX_LINES="$DEFAULT_MAX_LINES"

load_config() {
	if command -v uci >/dev/null 2>&1; then
		local value
		value="$(uci -q get openwalla.dns_monitor.target 2>/dev/null || true)"
		[ -n "$value" ] && DNS_TARGET="$value"

		value="$(uci -q get openwalla.dns_monitor.timeout 2>/dev/null || true)"
		[ -n "$value" ] && DNS_TIMEOUT="$value"

		value="$(uci -q get openwalla.dns_monitor.output_file 2>/dev/null || true)"
		[ -n "$value" ] && DNS_OUTPUT="$value"

		value="$(uci -q get openwalla.dns_monitor.max_lines 2>/dev/null || true)"
		[ -n "$value" ] && DNS_MAX_LINES="$value"

	fi
}

sanitize_int() {
	case "${1:-}" in
		'' | *[!0-9]*)
			echo "$2"
			;;
		*)
			echo "$1"
			;;
	esac
}

refresh_runtime_config() {
	load_config
	DNS_INTERVAL="$(sanitize_int "$DNS_INTERVAL" "$DEFAULT_INTERVAL")"
	DNS_TIMEOUT="$(sanitize_int "$DNS_TIMEOUT" "$DEFAULT_TIMEOUT")"
	DNS_MAX_LINES="$(sanitize_int "$DNS_MAX_LINES" "$DEFAULT_MAX_LINES")"
	ensure_output_file
}

ensure_output_file() {
	local dir
	dir="$(dirname "$DNS_OUTPUT")"
	mkdir -p "$dir"
	[ -f "$DNS_OUTPUT" ] || : >"$DNS_OUTPUT"
}

append_sample() {
	local ts="$1"
	local target="$2"
	local status="$3"
	local result="$4"
	local msg="$5"

	printf "%s|%s|%s|%s|%s\n" "$ts" "$target" "$status" "$result" "$msg" >>"$DNS_OUTPUT"
}

prune_file() {
	local max_lines
	max_lines="$(sanitize_int "$DNS_MAX_LINES" "$DEFAULT_MAX_LINES")"
	local current
	current="$(wc -l <"$DNS_OUTPUT" 2>/dev/null || echo 0)"
	current="$(sanitize_int "$current" "0")"

	if [ "$current" -gt "$max_lines" ]; then
		tail -n "$max_lines" "$DNS_OUTPUT" >"${DNS_OUTPUT}.tmp" && mv "${DNS_OUTPUT}.tmp" "$DNS_OUTPUT"
	fi
}

run_dns_once() {
	local now output status result message
	now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

	if command -v nslookup >/dev/null 2>&1; then
		output="$(nslookup "$DNS_TARGET" 2>&1 || true)"
	else
		output="nslookup not found"
	fi

	if echo "$output" | grep -qE '(Address [0-9]+:|Address: [0-9a-fA-F:.]+)'; then
		status="OK"
		result="SUCCESS"
		message="resolved"
	else
		status="ERROR"
		result="FAIL"
		message="$(echo "$output" | tail -n 1 | tr '|' ' ' | tr -s ' ')"
		[ -z "$message" ] && message="resolve failed"
	fi

	append_sample "$now" "$DNS_TARGET" "$status" "$result" "$message"
	prune_file
}

run_forever() {
	refresh_runtime_config
	while true; do
		refresh_runtime_config
		run_dns_once
		sleep "$DNS_INTERVAL"
	done
}

main() {
	refresh_runtime_config
	case "${1:-}" in
	--once)
		run_dns_once
		;;
	*)
		run_forever
		;;
	esac
}

main "$@"
