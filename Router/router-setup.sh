#!/bin/sh

# Set colors for better output
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
NC='\033[0m' # No Color

# Helper functions for box drawing and messages
draw_box_line() {
    echo -e "${CYAN}+----------------------------------------------------${NC}+"
}
draw_box_title() {
    local title="$1"
    local padding=$((50 - ${#title}))
    local left_pad=$((padding / 2))
    local right_pad=$((padding - left_pad))
    printf "${CYAN}|${NC} ${YELLOW}%*s%s%*s${NC} ${CYAN}|${NC}\n" $left_pad "" "$title" $right_pad ""
}
success_msg() {
    echo -e "${GREEN}\u2713${NC} $1" # \u2713 is a checkmark
}
error_msg() {
    echo -e "${RED}\u2717${NC} $1" # \u2717 is a ballot x (use \u2716 or \u2717 or \u2718)
}
info_msg() {
    echo -e "${CYAN}i${NC} $1"
}

# --- Section 1: Setup Custom Alias ---
draw_box_line
draw_box_title "1. Setting Up Custom 'cls' Alias"
draw_box_line
mkdir -p /etc/profile.d
cat << "EOF" > /etc/profile.d/alias.sh
alias cls="clear"
EOF
success_msg "Custom alias 'cls=\"clear\"' created in /etc/profile.d/alias.sh"

# --- Section 2: Check for External Storage ---
draw_box_line
draw_box_title "2. Checking for External Storage (SD/USB)"
draw_box_line
get_mounted_location() {
    mount | grep -E '/dev/sd|/dev/mmcblk' | awk '{print $3}' | head -n 1
}
MOUNTED_DIR=$(get_mounted_location)
if [ -n "$MOUNTED_DIR" ]; then
    extexist=1
    success_msg "External storage found at: ${GREEN}$MOUNTED_DIR${NC}"
else
    extexist=0
    info_msg "No external storage (SD/USB) detected."
fi

# --- Section 3: Update and Install Software ---
draw_box_line
draw_box_title "3. Updating Repositories and Installing Software"
draw_box_line

echo -e "${YELLOW}i${NC} Updating software packages..."
opkg update > /dev/null 2>&1
success_msg "opkg repositories updated."

software="nano vnstat2 vnstati2 luci-app-vnstat2 netifyd netdata nlbwmon luci-app-nlbwmon htop tcpdump-mini uhttpd-mod-ubus"

for s in $software
do
  printf "   - Checking %-25s..." "$s"
  opkg list-installed | grep -q "^$s -"
  if [ $? -ne 0 ]; then
    printf "\r   - Installing ${YELLOW}%-25s${NC}..." "$s"
    opkg install $s > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      success_msg "$s installation complete."
    else
      error_msg "$s installation failed."
    fi
  else
    success_msg "$s is already installed."
  fi
done

# --- Section 4: Configure vnStat Database Location ---
draw_box_line
draw_box_title "4. Configuring vnStat Database Location"
draw_box_line
if [ "$extexist" -eq 1 ]; then
    dt=$(date '+%d%m%Y%H%M%S')
    DEFAULT_DB_DIR="/var/lib/vnstat"
    VNSTAT_DIR="$MOUNTED_DIR/vnstat"
    mkdir -p "$VNSTAT_DIR"
    info_msg "Backing up /etc/vnstat.conf to /etc/vnstat.conf.$dt"
    cp /etc/vnstat.conf /etc/vnstat.conf.$dt
    info_msg "Updating vnStat configuration to use ${GREEN}$VNSTAT_DIR${NC}"
    sed -i 's/;DatabaseDir /DatabaseDir /g' /etc/vnstat.conf
    sed -i "s,$DEFAULT_DB_DIR,$VNSTAT_DIR,g" /etc/vnstat.conf
    success_msg "vnStat database location updated to $VNSTAT_DIR"
else
    info_msg "No external storage. Keeping default vnStat configuration."
fi

# --- Section 5: Configure Netifyd Listen Address ---
draw_box_line
draw_box_title "5. Updating Netifyd Configuration"
draw_box_line
LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null)
CONFIG_FILE="/etc/netifyd.conf"
if [ -n "$LAN_IP" ] && [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    info_msg "Backed up $CONFIG_FILE to $CONFIG_FILE.bak"
    if grep -q "^listen_address\[0\]" "$CONFIG_FILE"; then
        sed -i "s|^listen_address\[0\].*|listen_address[0] = $LAN_IP|" "$CONFIG_FILE"
        success_msg "Updated listen_address[0] with LAN IP: ${GREEN}$LAN_IP${NC}"
    else
        sed -i "/^\[socket\]/a listen_address[0] = $LAN_IP" "$CONFIG_FILE"
        success_msg "Added listen_address[0] with LAN IP: ${GREEN}$LAN_IP${NC}"
    fi
else
    error_msg "Could not retrieve LAN IP or configuration file not found."
fi

# --- Section 6: Update NLBW Refresh Interval ---
draw_box_line
draw_box_title "6. Updating NLBW Monitor Config"
draw_box_line
NLBW_CONFIG_FILE="/etc/config/nlbwmon"
if [ ! -f "$NLBW_CONFIG_FILE" ]; then
    error_msg "Error: $NLBW_CONFIG_FILE does not exist."
else
    sed -i 's/option refresh_interval 30s/option refresh_interval 10s/' "$NLBW_CONFIG_FILE"
    success_msg "Updated 'option refresh_interval' to 10s in $NLBW_CONFIG_FILE."
fi

# --- Section 7: Copying Scripts and Files ---
draw_box_line
draw_box_title "7. Downloading and Installing Router Scripts"
draw_box_line
info_msg "Removing old script files..."
# Check if file exists and remove it (one line each)
[ -f /usr/bin/1-minute-script.sh ] && rm -f /usr/bin/1-minute-script.sh && success_msg "Removed /usr/bin/1-minute-script.sh"
[ -f /usr/bin/5-minute-script.sh ] && rm -f /usr/bin/5-minute-script.sh && success_msg "Removed /usr/bin/5-minute-script.sh"
[ -f /usr/bin/1-hour-script.sh ] && rm -f /usr/bin/1-hour-script.sh && success_msg "Removed /usr/bin/1-hour-script.sh"
[ -f /usr/bin/12am-script.sh ] && rm -f /usr/bin/12am-script.sh && success_msg "Removed /usr/bin/12am-script.sh"
[ -f /etc/init.d/nlbw-compare-rate-service.sh ] && rm -f /etc/init.d/nlbw-compare-rate-service.sh && success_msg "Removed /etc/init.d/nlbw-compare-rate-service.sh"
[ -f /usr/bin/nlbw-compare-rate.sh ] && rm -f /usr/bin/nlbw-compare-rate.sh && success_msg "Removed /usr/bin/nlbw-compare-rate.sh"

echo -e "${YELLOW}i${NC} Downloading new scripts and setting permissions..."
# Use a simple function to handle download and chmod
download_script() {
    local url="$1"
    local dest="$2"
    wget -q "$url" -O "$dest" && chmod +x "$dest"
    if [ $? -eq 0 ]; then
        success_msg "Downloaded and set execute on ${GREEN}$dest${NC}"
    else
        error_msg "Failed to download ${RED}$dest${NC}"
    fi
}

BASE_URL="https://raw.githubusercontent.com/benisai/Openwalla/main/Router"
download_script "$BASE_URL/Crontab/1-minute-script.sh" "/usr/bin/1-minute-script.sh"
download_script "$BASE_URL/Crontab/5-minute-script.sh" "/usr/bin/5-minute-script.sh"
download_script "$BASE_URL/Crontab/1-hour-script.sh" "/usr/bin/1-hour-script.sh"
download_script "$BASE_URL/Crontab/12am-script.sh" "/usr/bin/12am-script.sh"
download_script "$BASE_URL/Scripts/nlbw-compare-rate-service.sh" "/etc/init.d/nlbw-compare-rate-service.sh"
download_script "$BASE_URL/Scripts/nlbw-compare-rate.sh" "/usr/bin/nlbw-compare-rate.sh"


# --- Section 8: Updating Crontab Entries ---
draw_box_line
draw_box_title "8. Updating Crontab Scheduled Tasks"
draw_box_line
C=$(crontab -l 2>/dev/null | grep "ready")
if [[ -z "$C" ]]; then
    info_msg "Adding scheduled scripts to crontab..."
    (crontab -l 2>/dev/null; echo "59 * * 12 * /ready"; echo "1 0 * * * /usr/bin/12am-script.sh"; echo "0 * * * * /usr/bin/1-hour-script.sh"; echo "*/1 * * * * /usr/bin/1-minute-script.sh") | crontab -
    success_msg "New scheduled tasks added to crontab."
elif [[ -n "$C" ]]; then
    info_msg "Keyword (ready) was found in crontab. No changes made."
fi

# --- Section 9: Enable and Restart Services ---
draw_box_line
draw_box_title "9. Enabling and Restarting Services"
draw_box_line
SERVICES=(
    "/etc/init.d/nlbw-compare-rate-service.sh"
    "/etc/init.d/cron"
    "/etc/init.d/vnstat"
)

for svc in "${SERVICES[@]}"; do
    printf "   - Enabling and Restarting ${CYAN}%-30s${NC}..." "$(basename "$svc")"
    "$svc" enable > /dev/null 2>&1
    "$svc" restart > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        success_msg "Service $(basename "$svc") processed."
    else
        error_msg "Service $(basename "$svc") failed to start/restart."
    fi
done

info_msg "Restarting netifyd separately..."
service netifyd restart > /dev/null 2>&1
success_msg "netifyd service restarted."

# --- Section 10: Create Symlinks ---
draw_box_line
draw_box_title "10. Creating Web Interface Symlinks"
draw_box_line
ln -s /www/vnstat.txt /www/vnstat.txt
success_msg "Symlink for vnstat.txt created."
ln -s /tmp/nlbw.html /www/nlbw.html
success_msg "Symlink for nlbw.html created."
ln -s /tmp/clientlist.html /www/clientlist.html
success_msg "Symlink for clientlist.html created."

# --- Final Message Box ---
echo
draw_box_line
draw_box_title "INSTALLATION COMPLETE"
draw_box_line
echo -e "${CYAN}|${NC} ${YELLOW}Remember to ${RED}RESTART THE ROUTER${YELLOW} for all changes to take effect.${NC} ${CYAN}|${NC}"
draw_box_line
