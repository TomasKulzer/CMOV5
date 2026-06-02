#!/bin/bash

IP_HOST_CORE="10.227.20.82"
IP_HOST_GNB="10.227.20.72"

IP_DOCKER_CORE_SUBNET="192.168.70.128/26"
IP_AMF="192.168.70.132"
IP_EXT_DN="192.168.70.135"

CONF_PATH=~/oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf

if [ "$1" == "gnb" ]; then
	sudo ip route del $IP_DOCKER_CORE_SUBNET 2>/dev/null
	sudo ip route add $IP_DOCKER_CORE_SUBNET via $IP_HOST_CORE dev eno1

	sudo iptables -t nat -F
	sudo iptables -t mangle -F
	sudo iptables -t raw -F
	sudo iptables -t filter -F

	sudo sysctl net.ipv4.conf.all.forwarding=1
    sudo iptables -P FORWARD ACCEPT
	sudo iptables-save 
	sudo sed -i "s|192.168.70.129/24|${IP_HOST_GNB}/32|g" "$CONF_PATH"
	echo "[*] Pinging AMF"
	ping -c 2 $IP_AMF
	echo "[*] Pinging External DN"
	ping -c 2 $IP_EXT_DN

elif [ "$1" == "core" ]; then 

	cd ~/oai-cn5g

	echo "[*] Initiating Core"
	sudo docker compose up -d
	sudo docker ps

	sudo iptables -t raw -F
	sudo iptables -t filter -F
	sudo sysctl net.ipv4.conf.all.forwarding=1
    sudo iptables -P FORWARD ACCEPT
	sudo iptables-save 
else 
	echo "Usage: ./$0 <gnb/core>"
	exit 1
fi

