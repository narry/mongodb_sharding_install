#!/bin/bash
cd  /usr/local/src
. ./conf.sh
shardname="$1"
if [ -z "${shardname}" ];then
	echo -e "\033[;37;31mERROR ! Usage ./`basename $0` shardName\033[0m"
        exit 1
fi

function initParameters(){
	local_ip=""
	dns_self=""
	network_hostname=""
	mongodself_rsname=""
	arbiterself_rsname=""
	configsrvfromhosts=""
}
initParameters

function checkEnv(){
	if ! rpm -qa|grep numactl &> /dev/null;then 
        	if ! ping -c 1 -w 1 www.baidu.com &> /dev/null;then 
                	echo -e "\033[;37;31mPlease Check Network Before Setup\033[0m";
                	exit 1;
       		else
                	yum -y install numactl;
        	fi;
	fi
	if [ ! -f $mongodb_install_tar ] || [ ! -f $hosts_file ] || [ ! -f $key_file ];then
		echo "path : $(pwd)"
        	echo -e "\033[;37;31mNo Packets\033[0m";
        	exit 1;
	fi
	if [ `cat /proc/sys/vm/zone_reclaim_mode` != 0 ];then
		echo 0 > /proc/sys/vm/zone_reclaim_mode && echo 'echo 0 > /proc/sys/vm/zone_reclaim_mode' >> /etc/rc.local
	fi
	if ! cat /etc/fstab|grep "/export"|grep "noatime";then
		sed -i 's!/export                 ext4    defaults!/export                 ext4    defaults,noatime!' /etc/fstab
        	mount -o remount /export
	fi
	if ! mount -l|grep "/export"|grep "noatime" &> /dev/null;then 
		echo -e "\033[;37;31mNoatime set fail\033[0m";
		#exit 1;
	fi
}

function initEvn(){
	checkEnv
	ulimit -u 65535
	echo "ulimit -u 65535" >> /etc/profile
	echo "export LANG=en_US.UTF-8" >> /root/.bash_profile
	sed -i 's!PATH=$PATH:$HOME/bin!PATH=$PATH:$HOME/bin:$mongodb_path!' /root/.bash_profile
	source /root/.bash_profile
	ln -s /usr/lib64/libpcap.so.1.0.0 /usr/lib64/libpcap.so.0.9
}

function mkdirectory(){
	mongodb_need_dir=($mongodb_data_path/arbiter $mongodb_data_path/config $mongodb_data_path/dumps $mongodb_data_path/key $mongodb_data_path/log $mongodb_data_path/mongod $mongodb_data_path/pid $mongodb_root_path/servers/ /home/mongo/scripts /home/mongo/logs)
	mkdir -p ${mongodb_need_dir[*]}
	\cp $key_file $mongodb_data_path/key/
}

function decompressMongodb(){
	tar -xzf $mongodb_install_tar -C $mongodb_root_path/servers/
        /bin/rm -rf $mongodb_server_path
	mv $mongodb_root_path/servers/$mongodb_dir  $mongodb_server_path
	mkdir -p $mongodb_server_path/etc
}

function initHosts(){
	local_ip=$(/sbin/ifconfig eth0 |grep "inet addr" |awk '{print $2}' | awk -F ":" '{print $2}')
	\cp $hosts_file /etc/
	network_hostname=$(cat "$hosts_file" | grep "$local_ip" | awk '{print $2}')
	sed -i "s/^HOSTNAME.*$/HOSTNAME=$network_hostname/" /etc/sysconfig/network
	hostname $network_hostname
}

function initCNF(){

cat >> $mongodb_server_path/etc/mongod.cnf << EOF
keyFile=$mongodb_data_path/key/key
dbpath=$mongodb_data_path/mongod
logpath=$mongodb_data_path/log/mongod.log
pidfilepath=$mongodb_data_path/pid/mongod.pid
directoryperdb=true
replSet=replSet
logappend=true
port=$mongod_port
maxConns=12000
fork=true
EOF

cat >> $mongodb_server_path/etc/arbiter.cnf << EOF
keyFile=$mongodb_data_path/key/key
dbpath=$mongodb_data_path/arbiter
logpath=$mongodb_data_path/log/arbiter.log
pidfilepath=$mongodb_data_path/pid/arbiter.pid
directoryperdb=true
replSet=replSet
logappend=true
port=$arbiter_port
nojournal=true
oplogSize=1
fork=true
EOF

cat >> $mongodb_server_path/etc/config.cnf << EOF
keyFile=$mongodb_data_path/key/key
dbpath=$mongodb_data_path/config
logpath=$mongodb_data_path/log/config.log
pidfilepath=$mongodb_data_path/pid/config.pid
configsvr=true
logappend=true
port=$config_port
maxConns=8000
fork=true
EOF

cat >> $mongodb_server_path/etc/mongos.cnf << EOF
keyFile=$mongodb_data_path/key/key
configdb=configsrvfromhosts
logpath=$mongodb_data_path/log/mongos.log
pidfilepath=$mongodb_data_path/pid/mongos.pid
logappend=true
port=$mongos_port
maxConns=12000
fork=true
EOF
}

function settingCnf(){
	dns_self=$(cat "$hosts_file" | grep "$local_ip")
	mongodself_rsname=$(echo "$dns_self" | awk '{print $2}' | sed 's/.$//')
	if echo "$dns_self" | grep "arbiter" &>/dev/null ;then
		arbiterself_rsname=$(echo "$dns_self" | sed "s/.*arbiter/$shardname/" | awk '{print $1}')
	fi
	configsvr=$(cat "$hosts_file" | grep config | awk '{print $2":'$config_port'"}')
	configsrvfromhosts=$(echo $configsvr |sed 's/ /,/g')
	sed -i "s/replSet=replSet/replSet=${mongodself_rsname}/" $mongodb_server_path/etc/mongod.cnf
	sed -i "s/replSet=replSet/replSet=${arbiterself_rsname}/" $mongodb_server_path/etc/arbiter.cnf
	sed -i "s/configsrvfromhosts/${configsrvfromhosts}/" $mongodb_server_path/etc/mongos.cnf
}

function rotateLog(){

cat >> /home/mongo/scripts/cutmongo.sh << EOF
#!/bin/bash

auth_conf=""
user_name="admin"
paswd="yvhkfhvk_brysj_chrdw@10gen"
mongo="$mongodb_path/mongo"
if [ ! -f \$mongo ];then
        mongo=\$(find /export -name mongo | head -1)
fi
array_mongodb_ports=($mongod_port $arbiter_port $config_port $mongos_port)
anyone_mongod_cnf=\$(ps aux | grep mongod |grep -v 'grep'| grep cnf | head -1 |awk '{print \$13}')

if cat "\${anyone_mongod_cnf}" | grep "^keyFile" ;then
	auth_conf="-u \${user_name} -p \${paswd}"
fi

function rotatelog(){
        local port=\$1
	if [ \$port -eq $arbiter_port ];then
        	\$mongo --port \$port admin --quiet --eval "db.runCommand({logRotate:1})"
	else
		\$mongo --port \$port admin \${auth_conf} --quiet --eval "db.runCommand({logRotate:1})"
	fi
}

for each_port in \${array_mongodb_ports[@]}
do
	if netstat -ln | grep \$each_port &>/dev/null;then
        	rotatelog \$each_port
	fi
done

find $mongodb_data_path/log -mtime +7 -type f |xargs rm -f

if [ -d "$mongodb_data_path/dumps/logs" ];then
        find $mongodb_data_path/dumps/logs -mtime +7 -type f |xargs rm -f
fi

EOF

echo "1 0 * * * sh /home/mongo/scripts/cutmongo.sh" >> /var/spool/cron/root
/etc/init.d/crond reload
}

function startServers(){
	numactl --interleave=all $mongodb_path/mongod -f $mongodb_server_path/etc/mongod.cnf
	if echo "$dns_self" | grep "arbiter" &>/dev/null;then
		numactl --interleave=all $mongodb_path/mongod -f $mongodb_server_path/etc/arbiter.cnf
	fi
	if echo "$dns_self" | grep "config" &>/dev/null;then
		numactl --interleave=all $mongodb_path/mongod -f $mongodb_server_path/etc/config.cnf
	fi
	sleep 10
#	$mongodb_path/mongos -f $mongodb_server_path/etc/mongos.cnf
}

function addUserForConfigServer(){
	if echo "$dns_self" | grep "config" &>/dev/null;then
		$mongodb_path/mongo --port $config_port admin --quiet --eval "db.createUser({user:\"$mongo_admin_user\",pwd:\"$mongo_admin_passwd\", roles:[\"root\"]})"
		$mongodb_path/mongo --port $config_port admin -u $mongo_admin_user -p $mongo_admin_passwd  --eval "db.createUser({user:\"$mongo_monitor_user\", pwd:\"$mongo_monitor_passwd\", roles:[\"dbAdmin\",\"clusterAdmin\",\"readAnyDatabase\"]})"
	fi
}

function settingRsImpl(){
        local rs_config="$1"
        echo "rs_config:" $rs_config
        $mongodb_path/mongo --port $mongod_port admin --quiet --eval "db.runCommand({replSetInitiate:$rs_config})"
        echo -e "\033[;1;32;32m---------------------------Waiting for Setting for Replica Set $mongodself_rsname 30  seconds---------------------------\033[0m"
        sleep 30
        if [ $? != 0 ];then echo "$shardname initiate is not OK!"
        echo "exit..." 
        exit 1;
        fi
        echo -e "\033[;1;32;32m---------------------------Setting for Replica Set $mongodself_rsname Completed---------------------------\033[0m"
        $mongodb_path/mongo --port $mongod_port admin --quiet --eval "db.createUser({user:\"$mongo_admin_user\",pwd:\"$mongo_admin_passwd\",roles:[\"root\"]})"
        sleep 10
        $mongodb_path/mongo --port $mongod_port admin -u $mongo_admin_user -p $mongo_admin_passwd --quiet --eval "db.createUser({user:\"$mongo_monitor_user\",pwd:\"$mongo_monitor_passwd\",roles:[\"dbAdmin\",\"clusterAdmin\",\"clusterMonitor\",\"readAnyDatabase\"]})"
}

function settingRs(){
	local shardself_point=$(echo $mongodself_rsname | sed "s/$shardname//")
	local rsself_point=$(echo $network_hostname | sed "s/$mongodself_rsname//")
	if [ $rsself_point -eq 1 ];then
		local forsub=""
		local every_shard_countmachines=$(cat $hosts_file |awk '{print $2}'|grep "$mongodself_rsname.$" |wc -l)
	        local rs_members=$(cat $hosts_file |awk '{print $2}'|grep "$mongodself_rsname.$")
        	local setrs_config="{_id:\"$mongodself_rsname\",members:[allmembers]}"
	        for ((j=0;j<$every_shard_countmachines;j++))
        	do
                	local member=$(echo ${rs_members} | awk '{print $"'$((j+1))'"}')
	                if [ $j -eq 0 ];then
                	        forsub="{_id:$j,host:\"${member}:$mongod_port\"}"
                	else
                        	forsub="$forsub,{_id:$j,host:\"${member}:$mongod_port\"}"
                	fi
                	if [ $j -eq $(($every_shard_countmachines-1)) ];then
                        	forsub="$forsub,{_id:$every_shard_countmachines,host:\"arbiter${shardself_point}:$arbiter_port\",arbiterOnly:true}"
                	fi
			while nmap -p$mongod_port $member | grep "closed" &>/dev/null  
			do
				echo "$member $mongod_port is not up, waiting..."
				sleep 30
			done
        	done
        	setrs_config=$(echo $setrs_config | sed "s/allmembers/$forsub/")
        	echo "setrs_config: $setrs_config"
		while nmap -p$arbiter_port "arbiter${shardself_point}" | grep "closed" &>/dev/null  
                do
			echo "sleep 30 arbiter${shardself_point}"
                        sleep 30
                done
		settingRsImpl ${setrs_config}
	fi
}


initEvn
mkdirectory
initHosts
decompressMongodb
initCNF
rotateLog
settingCnf
startServers
addUserForConfigServer
settingRs
