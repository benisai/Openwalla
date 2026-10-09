#!/bin/sh

# Download and start Openwalla Server from the public Openwalla repository.

set -eu

RAW_BASE="${OPENWALLA_SERVER_RAW_BASE:-https://raw.githubusercontent.com/benisai/Openwalla/main/openwalla-server}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
DEFAULT_INSTALL_DIR="$PWD/openwalla-server"
if [ -f "$SCRIPT_DIR/Dockerfile" ] && [ -d "$SCRIPT_DIR/app" ]; then
	DEFAULT_INSTALL_DIR="$SCRIPT_DIR"
fi
INSTALL_DIR="${OPENWALLA_SERVER_DIR:-$DEFAULT_INSTALL_DIR}"

log() {
	printf '%s\n' "[openwalla-server] $*"
}

fail() {
	printf '%s\n' "[openwalla-server] ERROR: $*" >&2
	exit 1
}

command -v wget >/dev/null 2>&1 || fail "wget is required."
command -v docker >/dev/null 2>&1 || fail "Docker is required."

if docker compose version >/dev/null 2>&1; then
	COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE="docker-compose"
else
	fail "Docker Compose is required."
fi

download() {
	relative_path="$1"
	destination="$INSTALL_DIR/$relative_path"
	temporary="$destination.tmp.$$"
	mkdir -p "$(dirname "$destination")"
	log "Downloading $relative_path"
	wget -qO "$temporary" "$RAW_BASE/$relative_path" || {
		rm -f "$temporary"
		fail "Unable to download $relative_path"
	}
	mv "$temporary" "$destination"
}

mkdir -p "$INSTALL_DIR/app" "$INSTALL_DIR/data"

for file in \
	Dockerfile \
	compose.yaml \
	requirements.txt \
	.env.example \
	app/__init__.py \
	app/config.py \
	app/processor.py \
	app/database.py \
	app/collector.py \
	app/main.py
do
	download "$file"
done

if [ ! -f "$INSTALL_DIR/.env" ]; then
	cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
	log "Created $INSTALL_DIR/.env with default settings."
fi

log "Building and starting Openwalla Server"
(
	cd "$INSTALL_DIR"
	$COMPOSE up -d --build
)

api_port="$(sed -n 's/^OPENWALLA_API_PORT=//p' "$INSTALL_DIR/.env" | tail -n 1)"
[ -n "$api_port" ] || api_port="8080"
log "Openwalla Server is running on port $api_port."
log "Edit $INSTALL_DIR/.env, then rerun this installer to change settings."
