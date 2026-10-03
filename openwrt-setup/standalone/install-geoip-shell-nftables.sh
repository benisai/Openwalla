#!/bin/sh

# Installs the nftables package published by friendly-bits/geoip-shell:
# https://github.com/friendly-bits/geoip-shell
# The pinned GPL-3.0 package is mirrored in the Openwalla repository.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

PACKAGE_NAME="geoip-shell_0.8.5-r1.apk"
PACKAGE_PATH="/tmp/$PACKAGE_NAME"
PACKAGE_URL="$OPENWALLA_RAW_BASE/apk-packages/geoip/$PACKAGE_NAME"

log "Installing geoip-shell 0.8.5 for nftables"
if ! have_cmd apk; then
	echo "This GeoIP package requires an apk-based OpenWrt release."
	exit 1
fi
if command -v geoip-shell >/dev/null 2>&1 && \
	! apk info -e geoip-shell >/dev/null 2>&1 && \
	! apk info -e geoip-shell-iptables >/dev/null 2>&1; then
	log "Removing the previous source-based geoip-shell installation"
	if command -v geoip-shell-uninstall.sh >/dev/null 2>&1; then
		geoip-shell-uninstall.sh || {
			echo "Unable to remove the previous source-based installation."
			exit 1
		}
	else
		echo "A source-based geoip-shell installation exists but its uninstaller is missing."
		exit 1
	fi
fi
if ! download_file "$PACKAGE_URL" "$PACKAGE_PATH"; then
	echo "Unable to download $PACKAGE_NAME from the Openwalla repository."
	exit 1
fi
if ! apk --allow-untrusted add "$PACKAGE_PATH"; then
	echo "Unable to install the nftables GeoIP package."
	rm -f "$PACKAGE_PATH"
	exit 1
fi
rm -f "$PACKAGE_PATH"

command -v geoip-shell >/dev/null 2>&1 || {
	echo "geoip-shell was not detected after package installation."
	exit 1
}
log "geoip-shell nftables package installed. Choose countries in Openwalla."
