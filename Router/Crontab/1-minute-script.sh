#!/bin/sh

#---------------------------------------------------------------------------------------------------------#
#---Adblock-Details--------#
/etc/init.d/adblock report > /tmp/adblock.txt
/etc/init.d/adblock list | grep " x " | sed 's/+//g' | cut -d " " -f2- > /tmp/adblock-list.txt

ln -s /tmp/adblock.txt /www/adblock.txt
ln -s /tmp/adblock-list.txt /www/adblock-list.txt

#---------------------------------------------------------------------------------------------------------#
#########----------Device-Details-------------###############
OUTPUT_FILE="/tmp/clientlist.html"
LEASES_FILE="/tmp/dhcp.leases"
ARP_FILE="/proc/net/arp"
# Remove the output file if it exists
[ -f "$OUTPUT_FILE" ] && rm "$OUTPUT_FILE"
# Parse DHCP leases
if [ -f "$LEASES_FILE" ]; then
    while read -r timestamp mac ip hostname id; do
        [ -z "$ip" ] && continue
        [ "$hostname" = "*" ] && hostname="Unknown"
        printf "%-20s %-17s %-15s %-20s\n" "$hostname" "$mac" "$ip" "DHCP Lease" >> "$OUTPUT_FILE"
    done < "$LEASES_FILE"
else
    echo "DHCP leases file not found: $LEASES_FILE" >> "$OUTPUT_FILE"
fi
# Parse ARP table for additional clients
if [ -f "$ARP_FILE" ]; then
    awk 'NR>1 {print $1, $4}' "$ARP_FILE" | while read -r ip mac; do
        if ! grep -q "$ip" "$LEASES_FILE"; then
            printf "%-20s %-17s %-15s %-20s\n" "Unknown" "$mac" "$ip" "ARP Only" >> "$OUTPUT_FILE"
        fi
    done
else
    echo "ARP file not found: $ARP_FILE" >> "$OUTPUT_FILE"
fi

ln -s /tmp/clientlist.html /www/clientlist.html

#---------------------------------------------------------------------------------------------------------#
#########----------nlbwmon-------------###############
nlbw -c csv -g ip,mac -o ip | tr -d '"' | tail -n +2 > /tmp/nlbw.html

ln -s /tmp/nlbwmon.html /www/nlbwmon.html


#---------------------------------------------------------------------------------------------------------#
#-vnstat-#
# Automatically determine the current year
YEAR=$(date +"%Y")
# Define the network interface (default is "br-lan")
INTERFACE="br-lan"
# Define the output text file
#OUTPUT_FILE="/tmp/vnstat.out"
OUTPUT_FILE="/www/vnstat.txt"
# Generate vnstat output and clean it in CSV format
{
    # Monthly data
    vnstat -i "$INTERFACE" --xml | grep -hnr "month id" | sed "s/^[0-9]*: //;s/<[^>]*>/ /g" | while read -r line; do
        echo "$INTERFACE,Monthly,$line" | sed 's/  */,/g'
    done
    # Daily data
    vnstat -i "$INTERFACE" --xml | grep -hnr "day id" | sed "s/^[0-9]*: //;s/<[^>]*>/ /g" | while read -r line; do
        echo "$INTERFACE,Daily,$line" | sed 's/  */,/g'
    done
    # Hourly data
    vnstat -i "$INTERFACE" --xml | grep -hnr "hour id" | sed "s/^[0-9]*: //;s/<[^>]*>/ /g" | while read -r line; do
        echo "$INTERFACE,Hourly,$line" | sed 's/  */,/g'
    done
} > "$OUTPUT_FILE"
# Notify the user
echo "Cleaned output saved to $OUTPUT_FILE."

ln -s /www/vnstat.txt /www/vnstat.txt


#---------------------------------------------------------------------------------------------------------#
# Restart Netify if service is not running
if ! pgrep netifyd
then /etc/init.d/netifyd start
else
#Restart Netify is it uses high memory
if [ `top -b -n 1 | grep netify | grep -v "grep" | awk '{print $6}'| tr -d '%'` -gt 25 ];then
echo "Restarting Netify due to high memory"
/etc/init.d/netifyd restart
else
echo "Netify Memory is fine"
fi
fi


