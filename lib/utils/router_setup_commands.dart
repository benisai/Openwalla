const String kOpenwallaInternetPreflightCommand = r'''
echo "[openwalla-app] Checking router internet connection..."
OPENWALLA_CONNECTIVITY_URL="https://raw.githubusercontent.com/benisai/openwalla-apk/main/openwrt-setup/setup-openwrt-router.sh"
OPENWALLA_INTERNET_OK=0
if command -v wget >/dev/null 2>&1; then
  wget -q -T 10 -O /dev/null "$OPENWALLA_CONNECTIVITY_URL" && OPENWALLA_INTERNET_OK=1
elif command -v curl >/dev/null 2>&1; then
  curl -fsS --connect-timeout 5 --max-time 10 -o /dev/null "$OPENWALLA_CONNECTIVITY_URL" && OPENWALLA_INTERNET_OK=1
else
  echo "[openwalla-app] Internet check unavailable: wget and curl are missing."
  exit 20
fi
if [ "$OPENWALLA_INTERNET_OK" = "1" ]; then
  echo "[openwalla-app] Internet connection: available."
else
  echo "[openwalla-app] Internet connection: unavailable. Connect the router to the internet or configure Wi-Fi repeater, then retry."
  exit 20
fi
''';
