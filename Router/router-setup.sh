#!/bin/sh

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
software="nano vnstat2 vnstati2 luci-app-vnstat2 netifyd netdata nlbwmon luci-app-nlbwmon"
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
    sed -i 's/;SaveInterval 5 /SaveInterval 1 /g' /etc/vnstat.conf
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
 #Copying scripts and lua files to router
 echo 'Copying shell scripts and files from Github to Router'
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/15-second-script.sh -O /usr/bin/15-second-script.sh && chmod +x /usr/bin/15-second-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/1-minute-script.sh -O /usr/bin/1-minute-script.sh && chmod +x /usr/bin/1-minute-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/1-hour-script.sh -O /usr/bin/1-hour-script.sh && chmod +x /usr/bin/1-hour-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/5-minute-script.sh -O /usr/bin/5-minute-script.sh && chmod +x /usr/bin/5-minute-script.sh
 wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/Crontab/12am-script.sh -O /usr/bin/12am-script.sh && chmod +x /usr/bin/12am-script.sh


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
   crontab -l | { cat; echo "* * * * * /usr/bin/15-second-script.sh"; } | crontab -
   crontab -l | { cat; echo "* * * * * sleep 15; /usr/bin/15-second-script.sh"; } | crontab -
   crontab -l | { cat; echo "* * * * * sleep 30; /usr/bin/15-second-script.sh"; } | crontab -
   crontab -l | { cat; echo "* * * * * sleep 45; /usr/bin/15-second-script.sh"; } | crontab -
   elif [[ -n "$C" ]]; then
   echo "Keyword (ready) was found in crontab, no changes made"
 fi


#----------------------------------------------------------------------------------------#  
# === Setting Services to enable and restarting Services =============
 echo 'Enable and Restart services'
 /etc/init.d/cron start
 /etc/init.d/cron enable
 /etc/init.d/cron restart
 /etc/init.d/vnstat restart
 /etc/init.d/dnsmasq restart
 /etc/init.d/firewall restart

#----------------------------------------------------------------------------------------# 
echo 'You should restart the router now for these changes to take effect...'
