#!/bin/sh

# Shared detached execution for setup, standalone installers and package jobs.
# start reads a shell script from stdin; status returns JSON then complete log lines.
set -u
umask 077

ROOT="${OPENWALLA_INSTALL_JOBS_DIR:-/tmp/openwalla/install}"
LOCK="$ROOT/active.lock"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ACTION="${1:-}"
ID="${2:-}"
case "$ID" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid install job ID' >&2; exit 2 ;; esac
[ "${#ID}" -le 80 ] || exit 2
JOB="$ROOT/$ID"

write_status() {
	printf '{"id":"%s","state":"%s","exit_code":%s,"updated_at":%s}\n' \
		"$ID" "$1" "$2" "$(date +%s)" >"$JOB/status.tmp.$$" &&
		mv "$JOB/status.tmp.$$" "$JOB/status.json"
}

release_lock() {
	# Unique owner files prevent a stale status reader from removing a NEW lock.
	if rm "$LOCK/owner-$ID" 2>/dev/null; then rmdir "$LOCK" 2>/dev/null || true; fi
}

process_token() {
	# Linux process birth time prevents a recycled PID from looking like our worker.
	if [ -r "/proc/$1/stat" ]; then
		sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'
	else
		echo unknown
	fi
}

reconcile() {
	local state pid token started
	[ -f "$JOB/status.json" ] || return 0
	state="$(sed -n 's/.*"state":"\([a-z]*\)".*/\1/p' "$JOB/status.json")"
	case "$state" in starting|running) ;; *) return 0 ;; esac
	pid="$(cat "$JOB/pid" 2>/dev/null || true)"
	case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
	if [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null; then
		token="$(cat "$JOB/token" 2>/dev/null || echo unknown)"
		[ "$token" != unknown ] || return 0
		[ "$(process_token "$pid")" != "$token" ] || return 0
	fi
	# A killed supervisor must not unlock while its installer is still working.
	pid="$(cat "$JOB/child-pid" 2>/dev/null || echo 0)"
	case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
	if [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null; then
		token="$(cat "$JOB/child-token" 2>/dev/null || echo unknown)"
		[ "$token" != unknown ] || return 0
		[ "$(process_token "$pid")" != "$token" ] || return 0
	fi
	started="$(cat "$JOB/started" 2>/dev/null || echo 0)"
	# Allow the detached worker to take ownership after the launch shell exits.
	if [ "$state" = starting ] && [ "$(($(date +%s) - started))" -lt 30 ]; then return 0; fi
	state="$(sed -n 's/.*"state":"\([a-z]*\)".*/\1/p' "$JOB/status.json")"
	case "$state" in starting|running) ;; *) return 0 ;; esac
	write_status interrupted null
	release_lock
}

start_job() {
	local active pid owner
	mkdir -p "$ROOT" || return 1
	if [ -f "$JOB/status.json" ]; then
		reconcile
		printf 'OPENWALLA_JOB|%s\n' "$ID"
		return 0
	fi
	if ! mkdir "$LOCK" 2>/dev/null; then
		active=""
		for owner in "$LOCK"/owner-*; do
			[ -f "$owner" ] || continue
			active="${owner##*/owner-}"
		done
		case "$active" in ''|*[!a-zA-Z0-9_-]*) echo 'Another installer is starting.' >&2; return 3 ;; esac
		sh "$SELF" status "$active" 0 >/dev/null 2>&1 || true
		if ! mkdir "$LOCK" 2>/dev/null; then
			echo "Another installer is running (job $active)." >&2
			return 3
		fi
	fi
	: >"$LOCK/owner-$ID"
	mkdir -p "$JOB" || { release_lock; return 1; }
	date +%s >"$JOB/started"
	printf '%s\n' "$$" >"$JOB/pid"
	process_token "$$" >"$JOB/token"
	write_status starting null || { release_lock; return 1; }
	trap 'write_status failed 1; release_lock; exit 1' HUP INT TERM
	if ! cat >"$JOB/command.sh" || [ ! -s "$JOB/command.sh" ]; then
		write_status failed 2; release_lock; return 2
	fi
	cp "$SELF" "$JOB/worker.sh" || { release_lock; return 1; }
	: >"$JOB/install.log"
	# Ignore HUP as well as redirecting every descriptor. This also works on
	# minimal BusyBox systems without the optional nohup applet.
	(
		trap '' HUP
		exec sh "$JOB/worker.sh" worker "$ID"
	) </dev/null >>"$JOB/install.log" 2>&1 &
	pid=$!
	printf '%s\n' "$pid" >"$JOB/launch-pid"
	trap - HUP INT TERM
	printf 'OPENWALLA_JOB|%s\n' "$ID"
}

run_worker() {
	printf '%s\n' "$$" >"$JOB/pid"
	process_token "$$" >"$JOB/token"
	write_status running null || exit 1
	trap 'rc=$?; if [ "$rc" -eq 0 ]; then write_status completed 0; else write_status failed "$rc"; fi; release_lock' EXIT
	child=""
	trap '[ -z "$child" ] || wait "$child"; exit 143' TERM
	trap '[ -z "$child" ] || wait "$child"; exit 130' INT
	printf '[openwalla-job] Started %s at %s\n' "$ID" "$(date '+%Y-%m-%d %H:%M:%S')"
	sh "$JOB/command.sh" &
	child=$!
	printf '%s\n' "$child" >"$JOB/child-pid"
	process_token "$child" >"$JOB/child-token"
	wait "$child"
	rc=$?
	printf '\n[openwalla-job] Finished with exit code %s\n' "$rc"
	exit "$rc"
}

case "$ACTION" in
launch)
	shift 2
	[ "$#" -gt 0 ] || exit 2
	# Quote argv into the same stdin-based launch path used by the app.
	{
		for argument do
			printf "'"
			printf '%s' "$argument" | sed "s/'/'\\\\''/g"
			printf "' "
		done
		printf '\n'
	} | sh "$SELF" start "$ID"
	;;
start) start_job ;;
worker) run_worker ;;
status|status-lines)
	offset="${3:-0}"
	case "$offset" in ''|*[!0-9]*) exit 2 ;; esac
	[ -f "$JOB/status.json" ] || { echo 'Install job not found; the router may have restarted.' >&2; exit 4; }
	reconcile
	cat "$JOB/status.json"
	# Only send newline-terminated records, so a partial write is retried on
	# the next poll rather than duplicated or cut through a UTF-8 character.
	tail -n "+$((offset + 1))" "$JOB/install.log" 2>/dev/null | (
		count=0
		while IFS= read -r line; do
			printf '%s\n' "$line"
			count=$((count + 1))
			[ "$count" -lt 200 ] || break
		done
		exit 0
	)
	;;
*) echo 'Usage: openwalla-install-job.sh start|status|launch JOB_ID [line-offset|command args...]' >&2; exit 2 ;;
esac
