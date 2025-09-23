#!/usr/local/bin/bash
INTERFACE="$1"

CHECKHOSTS[0]="a.root-servers.net"
CHECKHOSTS[1]="b.root-servers.net"
CHECKHOSTS[2]="c.root-servers.net"
CHECKHOSTS[3]="e.root-servers.net"
CHECKHOSTS[4]="f.root-servers.net"
CHECKHOSTS[5]="i.root-servers.net"
CHECKHOSTS[6]="j.root-servers.net"
CHECKHOSTS[7]="k.root-servers.net"
CHECKHOSTS[8]="l.root-servers.net"
CHECKHOSTS[9]="m.root-servers.net"

if ! [ -z "${INTERFACE}" ]
then
        IP=$(/sbin/ifconfig ${INTERFACE} | /usr/bin/grep 'inet ' | /usr/bin/grep -v 0xffffffff | /usr/bin/awk '{print $2}')
        PINGPARAM="-W 1000 -S ${IP}"
fi

SIZE=${#CHECKHOSTS[@]}
INDEX=$(($RANDOM % $SIZE))

for (( i=$INDEX; i<=($INDEX + 9); i++ )); do
        HOST=$(($i % 10))
        /sbin/ping -c 1 ${PINGPARAM} ${CHECKHOSTS[$HOST]} 1>/dev/null 2>&1 && echo -n 1 && exit 0
done
echo -n 0
exit 1
