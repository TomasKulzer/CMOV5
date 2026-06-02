#!/bin/bash 

IP_HOST_CORE="10.227.20.82"

IP_HOST_GNB="10.227.20.72"

IP_DOCKER_CORE_SUBNET="192.168.70.128/26"
IP_AMF="192.168.70.132"
IP_EXT_DN="192.168.70.135"

CONF_PATH=~/oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf
CONF_PATH_TMP=/tmp/gnb_task3.conf

# Killing previous Task 1 occurences
tmux kill-session -t gnb 2>/dev/null
tmux kill-session -t ue 2>/dev/null

# Killing previous Task 2 occurences
tmux kill-session -t ue1 2>/dev/null
tmux kill-session -t ue2 2>/dev/null

tmux kill-session -t iperf 2>/dev/null

if [ "$1" == "gnb" ]; then 


	########################
	#        TASK 1        #
	########################

	cd ~/oai/cmake_targets/ran_build/build

	
	if [ "$2" == "1" ] || [ "$2" == "one" ]; then

		echo "+----------------------+"
		echo "|        TASK 1        |"
		echo "+----------------------+"

		echo "[*] Starting gNB"
		tmux new-session -d -s gnb \
			"sudo ./nr-softmodem -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf --gNBs.[0].min_rxtxtime 6 --rfsim --sa"

		echo "Run 'tmux attach -t gnb'"
		sleep 10

		echo "[*] Starting UE"

		tmux new-session -d -s ue \
	        "sudo ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 127.0.0.1"

		echo "Run 'tmux attach -t ue'"
		sleep 10

		echo "[*] Pinging Uplink 10 times"
		ping -c 10 $IP_EXT_DN -I oaitun_ue1 

		IP_UE=$(ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

		echo "IP of UE1: $IP_UE"

		sleep 5

		echo "[*] Pinging Downlink 10 times"
		ssh -t mobile@${IP_HOST_CORE} "sudo docker exec oai-ext-dn ping -c 10 $IP_UE"

		

	########################
	#        TASK 2        #
	########################
	elif [ "$2" == "2" ] || [ "$2" == "two" ]; then

		echo "+----------------------+"
		echo "|        TASK 2        |"
		echo "+----------------------+"

		echo "[*] Starting gNB"
		tmux new-session -d -s gnb \
			"sudo ./nr-softmodem -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf --gNBs.[0].min_rxtxtime 6 --rfsim --sa"

		echo "Run 'tmux attach -t gnb'"

		sleep 10

		chmod +x ~/multi-ue.sh  

		echo "[*] Creating Namespaces for UE1 and UE2"
		sudo ~/multi-ue.sh -c1
		sudo ~/multi-ue.sh -c2

		echo "[*] Starting UE1 in namespace ue1"
		tmux new-session -d -s ue1 \
		    "sudo ip netns exec ue1 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095"

		echo "Run 'tmux attach -t ue1'"

		echo "[*] Starting UE2 in namespace ue2"
		tmux new-session -d -s ue2 \
		    "sudo ip netns exec ue2 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096"

		echo "Run 'tmux attach -t ue2'"

		sleep 10 # Giving time for UEs to start		

		echo "[*] Pinging Uplink 10 times from UE1"
		sudo ip netns exec ue1 ping -c 10 $IP_EXT_DN -I oaitun_ue1 

		echo "[*] Pinging Uplink 10 times from UE2"
		sudo ip netns exec ue2 ping -c 10 $IP_EXT_DN -I oaitun_ue1 # UE2 gets associated still to "oaitun_ue1"

		IP_UE1=$(sudo ip netns exec ue1 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
		IP_UE2=$(sudo ip netns exec ue2 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1) # UE2 gets associated still to "oaitun_ue1"

		echo "IP of UE1: $IP_UE1"
		echo "IP of UE2: $IP_UE2"

		sleep 5

		echo "[*] Pinging Downlink 10 times to UE1"
		ssh -t mobile@${IP_HOST_CORE} "sudo docker exec oai-ext-dn ping -c 10 $IP_UE1"

		echo "[*] Pinging Downlink 10 times to UE2"
		ssh -t mobile@${IP_HOST_CORE} "sudo docker exec oai-ext-dn ping -c 10 $IP_UE2"


	########################
	#        TASK 3        #
	########################

	elif [ "$2" == "3" ] || [ "$2" == "three" ]; then

		echo "+----------------------+"
		echo "|        TASK 3        |"
		echo "+----------------------+"

		cp "$CONF_PATH" "$CONF_PATH_TMP"

		if [ "$3" == "100" ]; then

			echo "[*] Changing gNB settings to 3500MHz center frequency and 100MHz bandwidth"

			sed -i '/#/!s/^\([[:space:]]*absoluteFrequencySSB[[:space:]]*=[[:space:]]*\).*$/\1 630048;/' "$CONF_PATH_TMP" # absoluteFrequencySSB = 630000

			sed -i '/#/!s/^\([[:space:]]*dl_absoluteFrequencyPointA[[:space:]]*=[[:space:]]*\).*$/\1 628776;/' "$CONF_PATH_TMP" # dl_absoluteFrequencyPointA = 626724. Had to change to 628776 because OAI doesn't support this value. even though 3GPP does

			sed -i '/#/!s/^\([[:space:]]*dl_frequencyBand[[:space:]]*=[[:space:]]*\).*$/\1 78;/' "$CONF_PATH_TMP"  # dl_frequencyBand = 78

			sed -i '/#/!s/^\([[:space:]]*dl_subcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"  # dl_subcarrierSpacing = 1

			sed -i '/#/!s/^\([[:space:]]*dl_carrierBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 106;/' "$CONF_PATH_TMP"  # dl_carrierBandwidth = 106 

			sed -i '/#/!s/^\([[:space:]]*initialDLBWPlocationAndBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 28875;/' "$CONF_PATH_TMP"  # initialDLBWPlocationAndBandwidth = 1099. Had to change to 28875 because OAI doesn't support this value. even though 3GPP does


			sed -i '/#/!s/^\([[:space:]]*initialDLBWPsubcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"  # initialDLBWPsubcarrierSpacing = 1

			sed -i '/#/!s/^\([[:space:]]*initialDLBWPcontrolResourceSetZero[[:space:]]*=[[:space:]]*\).*$/\1 11;/' "$CONF_PATH_TMP"  # CORESET0

			sed -i '/#/!s/^\([[:space:]]*ul_frequencyBand[[:space:]]*=[[:space:]]*\).*$/\1 78;/' "$CONF_PATH_TMP"  # ul_frequencyBand = 78

			sed -i '/#/!s/^\([[:space:]]*ul_carrierBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 106;/' "$CONF_PATH_TMP"  # ul_carrierBandwidth = 106

			sed -i '/#/!s/^\([[:space:]]*initialULBWPlocationAndBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 28875;/' "$CONF_PATH_TMP"  # initialULBWPlocationAndBandwidth = 1099

			sed -i '/#/!s/^\([[:space:]]*initialULBWPsubcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"  # initialULBWPsubcarrierSpacing = 1
		
		elif [ "$3" == "20" ]; then			

			echo "[*] Changing gNB settings to 3500MHz center frequency and 20MHz bandwidth"

			sed -i '/#/!s/^\([[:space:]]*absoluteFrequencySSB[[:space:]]*=[[:space:]]*\).*$/\1 630048;/' "$CONF_PATH_TMP"             # absoluteFrequencySSB = 630000

			sed -i '/#/!s/^\([[:space:]]*dl_absoluteFrequencyPointA[[:space:]]*=[[:space:]]*\).*$/\1 629388;/' "$CONF_PATH_TMP"       # dl_absoluteFrequencyPointA = 626724

			sed -i '/#/!s/^\([[:space:]]*dl_frequencyBand[[:space:]]*=[[:space:]]*\).*$/\1 78;/' "$CONF_PATH_TMP"                    # dl_frequencyBand = 78

			sed -i '/#/!s/^\([[:space:]]*dl_subcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"                 # dl_subcarrierSpacing = 1 

			sed -i '/#/!s/^\([[:space:]]*dl_carrierBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 51;/' "$CONF_PATH_TMP"                 # dl_carrierBandwidth = 66

			sed -i 's/^\([[:space:]]*initialDLBWPlocationAndBandwidth[[:space:]]*=[[:space:]]*\)[0-9]*/\1 13750/' "$CONF_PATH_TMP"  # initialDLBWPlocationAndBandwidth = 4700 

			sed -i '/#/!s/^\([[:space:]]*initialDLBWPsubcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"        # initialDLBWPsubcarrierSpacing = 1

			sed -i '/#/!s/^\([[:space:]]*initialDLBWPcontrolResourceSetZero[[:space:]]*=[[:space:]]*\).*$/\1 10;/' "$CONF_PATH_TMP"  # CORESET0. Had to change to 17 because OAI doesn't support this value. even though 3GPP does

			sed -i '/#/!s/^\([[:space:]]*ul_frequencyBand[[:space:]]*=[[:space:]]*\).*$/\1 78;/' "$CONF_PATH_TMP"                    # ul_frequencyBand = 78

			sed -i '/#/!s/^\([[:space:]]*ul_carrierBandwidth[[:space:]]*=[[:space:]]*\).*$/\1 51;/' "$CONF_PATH_TMP"                 # ul_carrierBandwidth = 66

			sed -i 's/^\([[:space:]]*initialULBWPlocationAndBandwidth[[:space:]]*=[[:space:]]*\)[0-9]*/\1 13750/' "$CONF_PATH_TMP"  # initialULBWPlocationAndBandwidth = 4700 

			sed -i '/#/!s/^\([[:space:]]*initialULBWPsubcarrierSpacing[[:space:]]*=[[:space:]]*\).*$/\1 1;/' "$CONF_PATH_TMP"        # initialULBWPsubcarrierSpacing = 1

		else 
			echo "For the third argument use either 20 (for 20MHz bandwidth) or 100 (for 100MHz bandwidth)"
			exit 1
		fi

		echo "[*] Starting gNB"

		tmux new-session -d -s gnb \
    		"sudo ./nr-softmodem -O ${CONF_PATH_TMP} --gNBs.[0].min_rxtxtime 6 --rfsim --sa 2>&1 | stdbuf -oL tee /tmp/gnb_task3_full.log"

		echo "Run 'tmux attach -t gnb'"

		sleep 10

		tmux capture-pane -t gnb -p -S -3000 > /tmp/gnb_task3_full.log 
		
		head -55 /tmp/gnb_task3_full.log > /tmp/gnb_task3_startup.log 


		rm /run/netns/ue* # TO guarantee there is no previous ue

		chmod +x ~/multi-ue.sh  

		echo "[*] Creating Namespaces for UE1 and UE2"
		sudo ~/multi-ue.sh -c1
		sudo ~/multi-ue.sh -c2

		if [ "$3" == "100" ]; then
			BW="100"

			tmux new-session -d -s ue1 \
		   		"sudo ip netns exec ue1 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3450720000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095"

			tmux new-session -d -s ue2 \
		    	"sudo ip netns exec ue2 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3450720000 --rfsim --sa --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096"

		elif [ "$3" == "20" ]; then
			BW="20"

			tmux new-session -d -s ue1 \
		   		"sudo ip netns exec ue1 ./nr-uesoftmodem -r 51 --numerology 1 --band 78 -C 3450000000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --ssb 210 --telnetsrv --telnetsrv.listenport 9095"

			tmux new-session -d -s ue2 \
		    	"sudo ip netns exec ue2 ./nr-uesoftmodem -r 51 --numerology 1 --band 78 -C 3450000000 --rfsim --sa --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --ssb 210 --telnetsrv --telnetsrv.listenport 9096"

		fi

		echo "Run 'tmux attach -t ue1'"
		echo "Run 'tmux attach -t ue2'"

		sleep 15

		echo "[*] Pinging Uplink 10 times from UE1"
		sudo ip netns exec ue1 ping -c 60 $IP_EXT_DN -I oaitun_ue1 | tee ~/rtt_ul_ue1_${BW}.txt

		echo "[*] Pinging Uplink 10 times from UE2"
		sudo ip netns exec ue2 ping -c 60 $IP_EXT_DN -I oaitun_ue1 | tee ~/rtt_ul_ue2_${BW}.txt # UE2 gets associated still to "oaitun_ue1"

		IP_UE1=$(sudo ip netns exec ue1 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
		IP_UE2=$(sudo ip netns exec ue2 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1) # UE2 gets associated still to "oaitun_ue1"

		echo "IP of UE1: $IP_UE1"
		echo "IP of UE2: $IP_UE2"

		sleep 5

		echo "[*] Pinging Downlink 10 times to UE1"
		ssh -t mobile@${IP_HOST_CORE} "sudo docker exec oai-ext-dn ping -c 60 $IP_UE1" | tee ~/rtt_dl_ue1_${BW}.txt

		echo "[*] Pinging Downlink 10 times to UE2"
		ssh -t mobile@${IP_HOST_CORE} "sudo docker exec oai-ext-dn ping -c 60 $IP_UE2" | tee ~/rtt_dl_ue2_${BW}.txt


		echo "+----------------------+"
		echo "|        TASK 4        |"
		echo "+----------------------+"

		for CURRENT_IP_UE in $IP_UE1 $IP_UE2; do

			
			echo "+-------------------------+"
			echo "| Testing: $CURRENT_IP_UE |"
			echo "+-------------------------+"


			echo "+----------------------+"
			echo "|          UDP         |"
			echo "+----------------------+"

			echo -en "\n\n\n"

			echo "[*] Preparing iPerf UDP Downlink for throughput"

			if [ "$CURRENT_IP_UE" == "$IP_UE1" ]; then
				NS="ue1"
			else
				NS="ue2"
			fi

			echo "[*] Starting iPerf Server"
			tmux new-session -d -s iperf \
				"sudo ip netns exec $NS iperf -s -u -i 1 -B $CURRENT_IP_UE"

			echo "Run 'tmux attach -t iperf'"

			sleep 10
			
			echo "[*] Starting iPerf UDP Client for 60 seconds"

			BITRATE="10M" # 10Mbits per second
			TIME="60" # in seconds

			ssh -t mobile@${IP_HOST_CORE} "sudo docker exec -it oai-ext-dn iperf -y C -u -t $TIME -i 1 -fk -B $IP_EXT_DN -b $BITRATE -c $CURRENT_IP_UE" | tee ~/throughput_udp_dl_${NS}_${BW}.csv

			echo "[*] Preparing iPerf UDP Uplink for throughput"

			echo "[*] Starting iPerf Server for 60 seconds"
			ssh -t mobile@${IP_HOST_CORE} "sudo docker exec -d oai-ext-dn iperf -s -u -i 1 -fk -B $IP_EXT_DN" 

			sleep 10

			echo "[*] Starting iPerf UDP Client"
			sudo ip netns exec $NS iperf -y C -u -t $TIME -i 1 -fk -b $BITRATE -B $CURRENT_IP_UE -c $IP_EXT_DN	| tee ~/throughput_udp_ul_${NS}_${BW}.csv


			echo -en "\n\n\n"

			echo "+----------------------+"
			echo "|          TCP         |"
			echo "+----------------------+"

			echo -en "\n\n\n"


			tmux kill-session -t iperf 2>/dev/null

			echo "[*] Preparing iPerf TCP Downlink for throughput"

			echo "[*] Starting iPerf Server"
			tmux new-session -d -s iperf \
				"sudo ip netns exec $NS iperf -s -i 1 -B $CURRENT_IP_UE" 
			
			echo "Run 'tmux attach -t iperf'"

			sleep 10

			echo "[*] Starting iPerf TCP Client for 60 seconds"

			BITRATE="10M" # 10Mbits per second

			ssh -t mobile@${IP_HOST_CORE} "sudo docker exec -it oai-ext-dn iperf -y C -t $TIME -i 1 -fk -B $IP_EXT_DN -c $CURRENT_IP_UE" | tee ~/throughput_tcp_dl_${NS}_${BW}.csv

			echo -en "\n\n\n"


			echo "[*] Preparing iPerf TCP Uplink for throughput"

			echo "[*] Starting iPerf Server for 60 seconds"
			ssh -t mobile@${IP_HOST_CORE} "sudo docker exec -d oai-ext-dn iperf -s -i 1 -fk -B $IP_EXT_DN" 

			sleep 10


			echo "[*] Starting iPerf TCP Client"
			sudo ip netns exec $NS iperf -y C -t $TIME -i 1 -fk -B $CURRENT_IP_UE -c $IP_EXT_DN | tee ~/throughput_tcp_ul_${NS}_${BW}.csv
			

			echo -en "\n\n\n"

			tmux kill-session -t iperf 2>/dev/null
		
		done
			

	fi



elif [ "$1" == "core" ]; then
	cd ~/oai-cn5g

	echo "[*] Initiating Core"
	sudo docker compose up -d
	sudo docker ps

	########################
	#        TASK 1        #
	########################

	if [ "$2" == "1" ] || [ "$2" == "one" ]; then
		sudo rm ~/dl-ul-pings-task1.pcap

		echo "[*] Listening for ${IP_EXT_DN} IP for Task 1 communicating with one UE"
		sudo timeout 120 tcpdump -i any "udp port 2152 or host ${IP_EXT_DN}" -U -w ~/dl-ul-pings-task1.pcap


	########################
	#        TASK 2        #
	########################
	elif [ "$2" == "2" ] || [ "$2" == "two" ]; then
		sudo rm ~/dl-ul-pings-task2.pcap

		echo "[*] Listening for ${IP_EXT_DN} IP for Task 2 communicating with UE1 and then UE2"
		sudo timeout 180 tcpdump -i any "udp port 2152 or host ${IP_EXT_DN}" -U -w ~/dl-ul-pings-task2.pcap
	
	

	########################
	#        TASK 3        #
	########################
	
	elif [ "$2" == "3" ] || [ "$2" == "three" ]; then

		sudo rm ~/dl-ul-pings-task3.pcap

		echo "[*] Listening for ${IP_EXT_DN} IP for Task 3 communicating with one UE at 100MHz at a 3500MHz"
		sudo timeout 180 tcpdump -i any "udp port 2152 or host ${IP_EXT_DN}" -U -w ~/dl-ul-pings-task3.pcap

	fi

else
	echo "Usage: ./$0 <gnb/core> <(1|one)/(2|two)/(3|three)>"
	exit 1
fi
