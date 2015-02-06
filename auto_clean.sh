#!/bin/bash
scp_path=/usr/local/src
password="123456"
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

n=0;
while read ip;
do array_allip[$n]=$ip;
((n++));
done<ip.txt  


function scpToRemote(){
		for each_ip in ${array_allip[@]}
		do 
		    SmartScp  clean.sh "root@$each_ip:${scp_path}"    &
		done
	sleep 5	
}

function sshToRemote(){
	for each_ip in ${array_allip[@]}
	do
		SmartSsh -o StrictHostKeyChecking=no "root@$each_ip" "sh /$scp_path/clean.sh"  &
	done
        sleep 10 
}

scpToRemote
sshToRemote
