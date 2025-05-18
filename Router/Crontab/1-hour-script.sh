#!/bin/sh

# #---------------------------------------------------------------------------------------------------------#
# #service netifyd restart to keep memory in check. 
# PID=`ps | grep "netifyd" | grep -v "grep" | awk '{print $1}'`
# if test -d /proc/$PID/; then
#     echo Netify Netcat Process Found, killing Process $PID
#     kill -9 $PID 1>&2
# fi

# #---------------------------------------------------------------------------------------------------------#

#---------------------------------------------------------------------------------------------------------#
# Restart Netify if service is using too much memory
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
