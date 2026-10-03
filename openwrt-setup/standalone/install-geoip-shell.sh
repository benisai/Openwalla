#!/bin/sh

# Geo-blocking is provided by the geoip-shell project by friendly-bits/antonk:
# https://github.com/friendly-bits/geoip-shell
# Openwalla distributes its unmodified source archive under GPL-3.0 and invokes
# the upstream installer. See openwrt-setup/vendor/geoip-shell/LICENSE.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

GEOIP_VERSION="0.8.5"
ARCHIVE="/tmp/geoip-shell-${GEOIP_VERSION}.tar.gz"
SOURCE_DIR="/tmp/openwalla-geoip-shell-source"
UPSTREAM_DIR="$SOURCE_DIR/geoip-shell-main"
SOURCE_URL="$OPENWALLA_RAW_BASE/vendor/geoip-shell/geoip-shell-${GEOIP_VERSION}.tar.gz"

log "Installing geoip-shell ${GEOIP_VERSION} from bundled GPL source"
if ! have_cmd nft; then
	echo "geoip-shell requires an OpenWrt nftables firewall."
	exit 1
fi
if ! download_file "$SOURCE_URL" "$ARCHIVE"; then
	echo "Unable to download the bundled geoip-shell source archive."
	exit 1
fi

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
if ! tar -xzf "$ARCHIVE" -C "$SOURCE_DIR"; then
	echo "Unable to extract the geoip-shell source archive."
	exit 1
fi
if [ ! -f "$UPSTREAM_DIR/geoip-shell-install.sh" ]; then
	echo "The geoip-shell source archive has an unexpected layout."
	exit 1
fi
chmod 0755 "$UPSTREAM_DIR/geoip-shell-install.sh"

if ! sh "$UPSTREAM_DIR/geoip-shell-install.sh" -w nft -z; then
	echo "The upstream geoip-shell source installer failed."
	rm -rf "$SOURCE_DIR" "$ARCHIVE"
	exit 1
fi
rm -rf "$SOURCE_DIR" "$ARCHIVE"

if ! command -v geoip-shell >/dev/null 2>&1; then
	echo "geoip-shell was not detected after installation."
	exit 1
fi
log "geoip-shell installed. Choose countries in the Openwalla Geo-Blocking screen."
