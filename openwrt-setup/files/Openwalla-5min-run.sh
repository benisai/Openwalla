#!/bin/sh

# Five-minute Netify/collector health and resident-memory watchdog.
set -u

RUNTIME_DIR="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
CRON_PATH="${OPENWALLA_CRON_PATH:-/etc/crontabs/root}"
INIT_DIR="${OPENWALLA_INIT_DIR:-/etc/init.d}"
PROC_DIR="${OPENWALLA_PROC_DIR:-/proc}"
LOCK_DIR="$RUNTIME_DIR/openwalla-5min-run.lock"

service_pids() {
	local data
	command -v jsonfilter >/dev/null 2>&1 || return 1
	data="$(ubus call service list "{\"name\":\"$1\"}" 2>/dev/null)" || return 1
	printf '%s' "$data" | jsonfilter -e '@.*.instances.*.pid' 2>/dev/null || true
}

service_memory() {
	# Include children (stream readers, shell workers), not only the procd parent.
	awk -v roots="$1" '
		FNR == 1 { n=split(FILENAME, parts, "/"); pid=parts[n-1] }
		/^PPid:/ { parent[pid]=$2 }
		/^VmRSS:/ { rss[pid]=$2 }
		END {
			n=split(roots, ids, /[[:space:]]+/)
			for (i=1; i<=n; i++) if (ids[i] ~ /^[0-9]+$/) owned[ids[i]]=1
			do {
				changed=0
				for (p in parent) if (!owned[p] && owned[parent[p]]) { owned[p]=1; changed=1 }
			} while (changed)
			for (p in rss) if (owned[p]) total+=rss[p]
			printf "%.0f\n", total
		}' "$PROC_DIR"/[0-9]*/status 2>/dev/null
}

check_netify() {
	local enabled mode limit total netify_pids collector_pids netify_kb collector_kb local_collector
	[ -x "$INIT_DIR/netifyd" ] || return 0
	"$INIT_DIR/netifyd" enabled >/dev/null 2>&1 || return 0
	enabled="$(uci -q get openwalla.collector.enabled 2>/dev/null || echo 0)"
	mode="$(uci -q get openwalla.collector.mode 2>/dev/null || echo local)"
	limit="$(uci -q get openwalla.collector.memory_limit_percent 2>/dev/null || echo 25)"
	case "$limit" in ''|*[!0-9]*) limit=25 ;; esac
	[ "$limit" -ge 1 ] && [ "$limit" -le 100 ] || limit=25
	local_collector=0
	if [ "$enabled" = 1 ] && [ "$mode" != external ] && [ -x "$INIT_DIR/openwalla-netify-collector" ]; then
		local_collector=1
	fi
	netify_pids="$(service_pids netifyd)" || { echo '[openwalla-5min] Cannot query Netify service; skipping.'; return 1; }
	collector_pids=''
	if [ "$local_collector" = 1 ]; then
		collector_pids="$(service_pids openwalla-netify-collector)" || return 1
	fi
	total="$(awk '/^MemTotal:/ {print $2; exit}' "$PROC_DIR/meminfo")" || return 1
	case "$total" in ''|*[!0-9]*|0) echo '[openwalla-5min] Cannot read total memory; skipping.'; return 1 ;; esac
	netify_kb="$(service_memory "$netify_pids")" || return 1
	collector_kb="$(service_memory "$collector_pids")" || return 1
	echo "[openwalla-5min] Netify RSS=${netify_kb}kB collector RSS=${collector_kb}kB RAM=${total}kB limit=${limit}% per service."
	if [ -z "$netify_pids" ] || awk -v n="$netify_kb" -v c="$collector_kb" -v t="$total" -v l="$limit" 'BEGIN {exit !(n*100>t*l || c*100>t*l)}'; then
		echo '[openwalla-5min] Recovering Netify and collector: missing Netify or high memory.'
		if [ "$local_collector" = 1 ]; then
			"$INIT_DIR/openwalla-netify-collector" stop || return 1
		fi
		# Stop the consumer before its stream source. Reconnect only after restart succeeds.
		"$INIT_DIR/netifyd" restart || return 1
		if [ "$local_collector" = 1 ]; then
			"$INIT_DIR/openwalla-netify-collector" start || return 1
		fi
	elif [ "$local_collector" = 1 ] && [ -z "$collector_pids" ]; then
		echo '[openwalla-5min] Starting missing collector; Netify is healthy.'
		"$INIT_DIR/openwalla-netify-collector" start || return 1
	fi
}

install_cron() {
	local tmp
	mkdir -p "$RUNTIME_DIR" "$(dirname "$CRON_PATH")" || return 1
	touch "$CRON_PATH" || return 1
	tmp="$(mktemp "$RUNTIME_DIR/.openwalla-5min-cron.XXXXXX")" || return 1
	grep -v 'OPENWALLA_5MIN_RUN' "$CRON_PATH" >"$tmp" || true
	echo '*/5 * * * * mkdir -p /tmp/openwalla; /usr/bin/Openwalla-5min-run.sh run >/tmp/openwalla/openwalla-5min-run.last.log 2>&1 # OPENWALLA_5MIN_RUN' >>"$tmp"
	cp "$tmp" "$CRON_PATH" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"
	"$INIT_DIR/cron" reload >/dev/null 2>&1 || \
		"$INIT_DIR/crond" reload >/dev/null 2>&1 || \
		killall -HUP crond >/dev/null 2>&1 || true
}

run_all() {
	local result
	mkdir -p "$RUNTIME_DIR" || return 1
	mkdir "$LOCK_DIR" 2>/dev/null || return 0
	trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
	trap 'exit 1' INT TERM
	check_netify
	result=$?
	rmdir "$LOCK_DIR" 2>/dev/null || true
	trap - EXIT INT TERM
	return "$result"
}

case "${1:-run}" in
run) run_all ;;
install-cron) install_cron ;;
*) echo "Usage: $0 [run|install-cron]" >&2; exit 2 ;;
esac
