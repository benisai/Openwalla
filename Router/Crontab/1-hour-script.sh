#!/bin/sh

#---------------------------------------------------------------------------------------------------------#
#service netifyd restart to keep memory in check. 
PID=`ps | grep "netifyd" | grep -v "grep" | awk '{print $1}'`
if test -d /proc/$PID/; then
    echo Netify Netcat Process Found, killing Process $PID
    kill -9 $PID 1>&2
fi

#---------------------------------------------------------------------------------------------------------#
