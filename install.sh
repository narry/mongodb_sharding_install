#/bin/bash
. ./conf.sh
scp_path="/usr/local/src"
shardname=$1
if [ -z "$shardname" ];then
        echo -e "\033[;37;31mERROR ! Usage ./`basename $0` shardName\033[0m"
        exit 1
fi
if [ ! -f "$mongodb_install_tar" ] || [ ! -f "$mongodb_shard_install" ];then
        echo -e "\033[;37;31mERROR ! ${mongodb_install_tar} or ${mongodb_shard_install} not exists in $(pwd)\033[0m"
        wget https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-2.4.12.tgz
        if [ $? != 0 ] ; then
        exit 1
        fi
fi

function initParamters(){
        array_allip=""
        string_allip=""
        firstip=""
        ipcount=0
	shardcount=0
	every_shard_countmachines=0
}
initParamters

function SmartSsh()
{
         expect <<EOF
                set timeout -1;
                spawn ssh -o StrictHostKeyChecking=no $1 ${@:2};
                expect {
		    "(yes/no)" {send "yes\r";exp_continue}
                    *assword:* {
                        send "$password\r";
                        expect {
                            *denied* {
                                exit 2;
                            }
                            eof
                        }
                    }
                    eof {
                        exit 1;
                    }
                }
EOF
    return $?
}

function SmartScp()
{
         expect <<EOF
                set timeout -1;
                spawn scp -r $1 $2;
                expect {
		    "(yes/no)" {send "yes\r";exp_continue}
                    *assword:* {
                        send "$password\r";
                        expect {
                            *denied* {
                                exit 2;
                            }
                            eof
                        }
                    }
                    eof {
                        exit 1;
                    }
                }
EOF
    return $?
}


function checkIp(){
	local ip_address="$1"
	local num=$(echo "$ip_address" | awk -F "." '{print NF}')
	if [ $num -ne 4 ];then
		echo -e "\033[;37;31mERROR! $ip_address form error\033[0m"
		return 1
	else
		local fir=$(echo "$ip_address" | awk -F "." '{print $1}')
		local sec=$(echo "$ip_address" | awk -F "." '{print $2}')
		local thi=$(echo "$ip_address" | awk -F "." '{print $3}')
		local fou=$(echo "$ip_address" | awk -F "." '{print $4}')
		if [[  "$fir" =~ [^[:digit:]] ]] || [[  "$sec" =~ [^[:digit:]] ]] || [[  "$thi" =~ [^[:digit:]] ]] || [[  "$fou" =~ [^[:digit:]] ]];then
			echo -e "\033[;37;31mERROR! $ip_address form error\033[0m"
			return 1
		fi
		if [ "$fir" -le 0 -o "$fir" -ge 255 -o "$sec" -le 0 -o "$sec" -ge 255 -o "$thi" -le 0 -o "$thi" -ge 255 -o "$fou" -le 0 -o "$fou" -ge 255 ];then
			echo -e "\033[;37;31mERROR! $ip_address form error\033[0m"
			return 1
		fi
		
	fi
}

function splitTotalIps(){
	local total_string_ip="$1"
	if [ -z "$total_string_ip" ];then
		return 1
	fi
	local old_IFS="$IFS"
	local new_ifs=","
	IFS="${new_ifs}"
	array_allip=($total_string_ip)
	IFS="${old_IFS}"
	ipcount=${#array_allip[@]}
	if [ "$ipcount" -eq 0 ];then
		return 1
	fi
	for each_ip in "${array_allip[@]}"
        do
                checkIp "$each_ip"
		if [ $? -ne 0 ];then
			return 1
		fi

        done
}

function provideArguments(){
	echo -e "\033[;1;32;32m(1) IP is consecutive,only type the first ip \n(2) type all ip address\033[0m"
	read -p "Please type your choice: " ychoice
	case "$ychoice" in
		"1")
			read -p "Please type the first ip: " 	firstip
			checkIp "$firstip"
			while [ $? -ne 0 ]
			do
				read -p "Please type the first ip again : "  firstip
				checkIp "$firstip"
			done
			read -p "Please type the total number machines of the sharding cluster:"  ipcount
			while [[  "$ipcount" =~ [^[:digit:]] ]] || [ "$ipcount" -le 0 ]
			do
				echo -e "\033[;37;31mERROR! Please type positive interger\033[0m"
				read -p "Please type the total number machines of the sharding cluster again : "  ipcount 
			done	
			read -p "Please type the number shard: " shardcount
			while [[  "$shardcount" =~ [^[:digit:]] ]] || [ "$shardcount" -le 1 ] || echo $(echo "scale=20;$ipcount/$shardcount"|bc)|awk -F '.' '{print $2}'|grep '[1-9]' &>/dev/null
			do
				 echo -e "\033[;37;31mERROR! Please type positive interger\033[0m"
				 read -p "Please type the number shard again : " shardcount
			done  
			;;
		"2")
			read -p "Please type the all ip address: " string_allip
			splitTotalIps "$string_allip"
			while [ $? -ne 0 ]
                        do	
                                read -p "Please type the all ip address again: " string_allip
                                splitTotalIps "$string_allip"
                        done
			read -p "Please type the number shard: " shardcount			
			while [[  "$shardcount" =~ [^[:digit:]] ]] || [ "$shardcount" -le 1 ]|| echo $(echo "scale=20;$ipcount/$shardcount"|bc)|awk -F '.' '{print $2}'|grep '[1-9]' &>/dev/null
                        do
                                 echo -e "\033[;37;31mERROR! Please type positive interger\033[0m"
                                 read -p "Please type the number shard again : " shardcount
                        done
			;;

		*)
			echo -e "\033[;37;31mERROR! Only type 1 or 2\033[0m"
			exit 1
			;;
	esac
}

function initAllIp(){
	if [ "$ychoice" -eq 1 ];then
		array_allip[0]="$firstip"
		local prefix=$(echo "$firstip" | awk -F "." '{print $1"."$2"."$3}')
		local init_fou=$(echo "$firstip" | awk -F "." '{print $4}')
		for ((i=1;i<$ipcount;i++))
		do
			local fou=$(($init_fou+$i))
			local ip="$prefix.$fou" 
			array_allip[$i]="$ip"
		done
	fi
}

function createHosts(){
	if [ -f "$hosts_file" ];then
		mv "$hosts_file" hosts_file_back
	fi
	local startPoint=0
	every_shard_countmachines=$(($ipcount/$shardcount))
	for ((x=1;x<=$shardcount;x++))
	do
		for ((y=1;y<=$every_shard_countmachines;y++))
		do
			local dns_line="${array_allip[$startPoint]} $shardname$x$y"
			if [ $startPoint -lt 3 ];then
				dns_line="$dns_line config$(($startPoint+1))"
			fi
			if [ $y -eq $every_shard_countmachines ];then
				local arbiter=$(($shardcount-x+1))
				dns_line="${dns_line} arbiter${arbiter}"
			fi
			echo "$dns_line" >> "$hosts_file"
			startPoint=$(($startPoint+1))
		done
	done
	echo "127.0.0.1	localhost.localdomain localhost" >> "$hosts_file"
}

function initKey(){
	openssl rand -base64 753 > "$key_file"
	chmod 600 "$key_file"
}

function scpToRemote(){
	if ! ping -c 1 -w 1 www.baidu.com &> /dev/null;then 
		echo -e "\033[;37;31mPlease Check Network Before Setup\033[0m";
		exit 1;
	else
		for each_ip in ${array_allip[@]}
		do
			if ! ping -c 1 -w 1 $each_ip &> /dev/null;then
				echo -e "\033[;37;31mCan not ping $each_ip from local. Please Check Network\033[0m";
                 		exit 1;
			fi
			SmartScp "$mongodb_install_tar $mongodb_shard_install $hosts_file $key_file conf.sh" "root@$each_ip:${scp_path}" & 
		done 
		echo -e "\033[;1;32;32m---------------------------Waiting for Scp file to all machines 30 seconds---------------------------\033[0m"
		sleep 30
		
	fi
}

function sshToRemote(){
	for each_ip in ${array_allip[@]}
	do
		SmartSsh "root@$each_ip" "sh ${scp_path}/${mongodb_shard_install} $shardname" &
	done
	echo -e "\033[;1;32;32m---------------------------Waiting for Installation of Mongodb 180 seconds---------------------------\033[0m"
	sleep 180
}

function checkAllRepls() {
cat ./hosts|awk '{print $1}'|while read host ; 
do
    while nmap -p$mongod_port $host | grep "closed" &>/dev/null  
    do
    echo "host $host:$mongod_port is not up, waiting..."
    sleep 30
    done
done
}
function startMongos(){
#	password=$(echo "YCE2S318R3Z5XCc6c2tEUlU2I2ZsWih5TkoK" | base64 -d 2> /dev/null)
	for each_ip in ${array_allip[@]}
	do
		SmartSsh "root@$each_ip" "numactl --interleave=all $mongodb_path/mongos -f $mongodb_server_path/etc/mongos.cnf" &
	done
	echo -e "\033[;1;32;32m---------------------------Waiting for Starting Mongos 30 seconds---------------------------\033[0m"
        sleep 30
}

function addshard(){
	local any_mongos=$(head -1 $hosts_file | awk '{print $1}')
	for ((i=1;i<=$shardcount;i++))
	do
		local rs_name="${shardname}$i"
		local any_mongod=$(cat $hosts_file | grep "$rs_name" | awk '{print $2}'|head -1)
		addshard_conf="--quiet --eval db.runCommand({addshard:\"$rs_name/${any_mongod}:$mongod_port\",name:\"$rs_name\"})"
		$mongodb_path/mongo --host "$any_mongos" --port $mongos_port admin -u $mongo_admin_user -p $mongo_admin_passwd  $addshard_conf
	done
}

provideArguments
initAllIp
createHosts
initKey
scpToRemote
sshToRemote
checkAllRepls
startMongos
addshard
