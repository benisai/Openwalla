#!/bin/sh

#---------------------------------------------------------------------------------------------------------#
# Restart Netify if memory is too high
if ! pgrep netifyd
then /etc/init.d/netifyd start
else
if [ `top -b -n 1 | grep netify | grep -v "grep" | awk '{print $6}'| tr -d '%'` -gt 25 ];then
echo "Restarting Netify due to high memory"
/etc/init.d/netifyd restart
else
echo "Netify Memory is fine"
fi
fi
