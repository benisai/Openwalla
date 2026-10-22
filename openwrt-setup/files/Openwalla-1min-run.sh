#!/bin/sh

# Shared one-minute maintenance entry point for Openwalla router tasks.
set -u

RUNTIME_DIR="${OPENWALLA_RUNTIME_DIR:-/tmp/openwalla}"
CRON_PATH="${OPENWALLA_CRON_PATH:-/etc/crontabs/root}"
PING_SCRIPT="${OPENWALLA_DEVICES_PING:-/usr/bin/openwalla-devices-ping}"

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
	[ ! -x "$PING_SCRIPT" ] || "$PING_SCRIPT"
	;;
install-cron) install_cron ;;
*) echo "Usage: $0 [run|install-cron]" >&2; exit 2 ;;
esac
