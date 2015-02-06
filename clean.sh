#!/bin/bash

ps aux | grep mongo | grep -v 'grep'|awk '{print $2}'| xargs kill -2
/bin/rm -rf /usr/lib64/libpcap.so.0.9
/bin/rm -rf /export/servers
/bin/rm -rf /export/data
/bin/rm -rf /home/mongo/scripts/cutmongo.sh
/bin/rm -rf /usr/local/src/*

sed -i '/^ulimit -u 266239.*$/d' /etc/profile
sed -i '/^export LANG=en_US.UTF-8.*$/d' /root/.bash_profile
sed -i 's!^PATH=$PATH:$HOME/bin.*$!PATH=$PATH:$HOME/bin!g' /root/.bash_profile
sed -i '/.*mongo.*$/d' /etc/rc.local
sed -i '/.*cutmongo.*$/d' /var/spool/cron/root
