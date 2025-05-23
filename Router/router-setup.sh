#!/bin/sh

#wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/router-setup.sh

# === Set Custom Alias for clear as cls ============
mkdir -p /etc/profile.d
cat << "EOF" > /etc/profile.d/alias.sh
alias cls="clear"
EOF

#----------------------------------------------------------------------------------------#  
# === Check if SD or USB exist ============
get_mounted_location() {
    mount | grep -E '/dev/sd|/dev/mmcblk' | awk '{print $3}' | head -n 1
}
MOUNTED_DIR=$(get_mounted_location)
if [ -n "$MOUNTED_DIR" ]; then
    extexist=1
else
    extexist=0
fi

#----------------------------------------------------------------------------------------#  
# === Update repo =============
 echo 'Updating software packages'
 opkg update
# List of software to check and install
#software="nano vnstat2 vnstati2 luci-app-vnstat2 netifyd netdata nlbwmon luci-app-nlbwmon htop tcpdump-mini adblock luci-app-adblock"
software="nano vnstat2 vnstati2 luci-app-vnstat2 netifyd netdata nlbwmon luci-app-nlbwmon htop tcpdump-mini uhttpd-mod-ubus"

# Loop through the list of software
for s in $software
do
  # Check if the software is installed
  opkg list-installed | grep -q "^$s -"
  if [ $? -ne 0 ]
  then
    # If not installed, install it
    echo "$s is not installed. Installing..."
    opkg install $s
    echo "$s installation complete."
  else
    # If installed, print a message
    echo "$s is already installed."
  fi
done

#----------------------------------------------------------------------------------------#  
# === Changing vnstat backup location to USB or SD Card. === #
if [ "$extexist" -eq 1 ]; then
    dt=$(date '+%d%m%Y%H%M%S')
    DEFAULT_DB_DIR="/var/lib/vnstat"
    VNSTAT_DIR="$MOUNTED_DIR/vnstat"
    mkdir -p "$VNSTAT_DIR"
    # Backup the original vnstat.conf
    echo "Backing up /etc/vnstat.conf to /etc/vnstat.conf.$dt"
    cp /etc/vnstat.conf /etc/vnstat.conf.$dt
    # Update vnStat configuration
    echo "Updating vnStat configuration to use $VNSTAT_DIR"
    sed -i 's/;DatabaseDir /DatabaseDir /g' /etc/vnstat.conf
    sed -i "s,$DEFAULT_DB_DIR,$VNSTAT_DIR,g" /etc/vnstat.conf
    echo "vnStat database location updated to $VNSTAT_DIR"
else
    echo "No mounted directory found. Keeping default vnStat configuration."
fi


#----------------------------------------------------------------------------------------#  
# === Update Netify Config with LAN IP Address === #
LAN_IP=$(uci get network.lan.ipaddr)
CONFIG_FILE="/etc/netifyd.conf"
if [ -n "$LAN_IP" ] && [ -f "$CONFIG_FILE" ]; then
    # Backup the configuration file
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    # Check if listen_address[0] already exists
    if grep -q "^listen_address\[0\]" "$CONFIG_FILE"; then
        # Update the existing line
        sed -i "s|^listen_address\[0\].*|listen_address[0] = $LAN_IP|" "$CONFIG_FILE"
        echo "Updated listen_address[0] with LAN IP: $LAN_IP"
    else
        # Add the line under the [socket] section
        sed -i "/^\[socket\]/a listen_address[0] = $LAN_IP" "$CONFIG_FILE"
        echo "Added listen_address[0] with LAN IP: $LAN_IP"
    fi
else
    echo "Error: Could not retrieve LAN IP or configuration file not found."
fi


#----------------------------------------------------------------------------------------#
# === Update NLBW Config Refresh Interval === #
NLBW_CONFIG_FILE="/etc/config/nlbwmon"
if [ ! -f "$NLBW_CONFIG_FILE" ]; then
  echo "Error: $NLBW_CONFIG_FILE does not exist."
else
  {
    # Update 'option refresh_interval' from 30s to 10s
    sed -i 's/option refresh_interval 30s/option refresh_interval 10s/' "$NLBW_CONFIG_FILE"
    echo "Updated 'option refresh_interval' to 10s in $NLBW_CONFIG_FILE."
  }
fi


#----------------------------------------------------------------------------------------#  
 #Copying scripts and lua files to router


#!/bin/sh
#----------------------------------------------------------------------------------------#  
 # Check if file exists and remove it (one line each)
 [ -f /usr/bin/1-minute-script.sh ] && rm -f /usr/bin/1-minute-script.sh && echo "Removed 1-minute-script.sh"
 [ -f /usr/bin/5-minute-script.sh ] && rm -f /usr/bin/5-minute-script.sh && echo "Removed 5-minute-script.sh"
 [ -f /usr/bin/1-hour-script.sh ] && rm -f /usr/bin/1-hour-script.sh && echo "Removed 1-hour-script.sh"
 [ -f /usr/bin/12am-script.sh ] && rm -f /usr/bin/12am-script.sh && echo "Removed 12am-script.sh"
 [ -f /etc/init.d/nlbw-compare-rate-service.sh ] && rm -f /etc/init.d/nlbw-compare-rate-service.sh && echo "Removed nlbw-compare-rate-service.sh"
 [ -f /usr/bin/nlbw-compare-rate.sh ] && rm -f /usr/bin/nlbw-compare-rate.sh && echo "Removed nlbw-compare-rate.sh"
 
 echo 'Copying shell scripts and files from Github to Router'
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/1-minute-script.sh -O /usr/bin/1-minute-script.sh && chmod +x /usr/bin/1-minute-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/5-minute-script.sh -O /usr/bin/5-minute-script.sh && chmod +x /usr/bin/5-minute-script.sh 
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/1-hour-script.sh -O /usr/bin/1-hour-script.sh && chmod +x /usr/bin/1-hour-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/12am-script.sh -O /usr/bin/12am-script.sh && chmod +x /usr/bin/12am-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Scripts/nlbw-compare-rate-service.sh -O /etc/init.d/nlbw-compare-rate-service.sh && chmod +x /etc/init.d/nlbw-compare-rate-service.sh 
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Scripts/nlbw-compare-rate.sh -O /usr/bin/nlbw-compare-rate.sh && chmod +x /usr/bin/nlbw-compare-rate.sh


#----------------------------------------------------------------------------------------#  
 #Adding scripts to Crontab
 echo 'Add Scripts to crontab'
 C=$(crontab -l | grep "ready")
 if [[ -z "$C" ]]; then
   echo "Adding Scripts*.sh to crontab"
   crontab -l | { cat; echo "59 * * 12 * /ready"; } | crontab -
   crontab -l | { cat; echo "1 0 * * * /usr/bin/12am-script.sh"; } | crontab -
   crontab -l | { cat; echo "0 * * * * /usr/bin/1-hour-script.sh"; } | crontab -
   crontab -l | { cat; echo "*/1 * * * * /usr/bin/1-minute-script.sh"; } | crontab -
   elif [[ -n "$C" ]]; then
   echo "Keyword (ready) was found in crontab, no changes made"
 fi


#----------------------------------------------------------------------------------------#  
# === Setting Services to enable and restarting Services =============
 echo 'Enable and Restart services'
 /etc/init.d/nlbw-compare-rate-service.sh enable
 /etc/init.d/nlbw-compare-rate-service.sh restart
 /etc/init.d/cron start
 /etc/init.d/cron enable
 /etc/init.d/cron restart
 /etc/init.d/vnstat enable
 /etc/init.d/vnstat restart
 service netifyd restart

#----------------------------------------------------------------------------------------# 
# symlink some files
ln -s /www/vnstat.txt /www/vnstat.txt
ln -s /tmp/nlbw.html /www/nlbw.html
ln -s /tmp/clientlist.html /www/clientlist.html

#----------------------------------------------------------------------------------------# 
echo 'You should restart the router now for these changes to take effect...'
