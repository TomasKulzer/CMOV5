#!/bin/bash
# ---------------------------------------------------------------
# Task 2 – Multi-UE connectivity
#   - starts gNB + 2 UEs (each in its own netns)
#   - 10x uplink ping   per UE
#   - 10x downlink ping per UE
#
# Prerequisites:  bash initial_setup.sh gnb  (run once beforehand)
# ---------------------------------------------------------------

CORE_IP="10.227.20.82"
EXT_DN="192.168.70.135"
SSH_USR="mobile"

# Kill any previous sessions
tmux kill-session -t gnb 2>/dev/null
tmux kill-session -t ue1 2>/dev/null
tmux kill-session -t ue2 2>/dev/null
tmux kill-session -t iperf 2>/dev/null

cd ~/oai/cmake_targets/ran_build/build

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
sudo multi-ue.sh -c1
sudo multi-ue.sh -c2

echo "[*] Starting UE1 in namespace ue1"
tmux new-session -d -s ue1 \
    "sudo ip netns exec ue1 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095"

echo "Run 'tmux attach -t ue1'"

echo "[*] Starting UE2 in namespace ue2"
tmux new-session -d -s ue2 \
    "sudo ip netns exec ue2 ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096"

echo "Run 'tmux attach -t ue2'"

sleep 10

echo "[*] Pinging Uplink 10 times from UE1"
sudo ip netns exec ue1 ping -c 10 $EXT_DN -I oaitun_ue1

echo "[*] Pinging Uplink 10 times from UE2"
sudo ip netns exec ue2 ping -c 10 $EXT_DN -I oaitun_ue1

UE1_IP=$(sudo ip netns exec ue1 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
UE2_IP=$(sudo ip netns exec ue2 ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo "IP of UE1: $UE1_IP"
echo "IP of UE2: $UE2_IP"

sleep 5

echo "[*] Pinging Downlink 10 times to UE1"
ssh -t ${SSH_USR}@${CORE_IP} "sudo docker exec oai-ext-dn ping -c 10 $UE1_IP"

echo "[*] Pinging Downlink 10 times to UE2"
ssh -t ${SSH_USR}@${CORE_IP} "sudo docker exec oai-ext-dn ping -c 10 $UE2_IP"

echo "[T2] Done"
