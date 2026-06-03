#!/bin/bash
# ---------------------------------------------------------------
# Task 1 – Single UE connectivity
#   - starts gNB + 1 UE
#   - 10x uplink ping   (UE -> ext-dn)
#   - 10x downlink ping (ext-dn -> UE)
#
# Prerequisites:  bash initial_setup.sh gnb  (run once beforehand)
# ---------------------------------------------------------------

CORE_IP="10.227.20.62"
EXT_DN="192.168.70.135"
SSH_USR="mobile"

# Kill any previous sessions
tmux kill-session -t gnb 2>/dev/null
tmux kill-session -t ue 2>/dev/null
tmux kill-session -t iperf 2>/dev/null

cd ~/oai/cmake_targets/ran_build/build

echo "+----------------------+"
echo "|        TASK 1        |"
echo "+----------------------+"

echo "[*] Starting gNB"
tmux new-session -d -s gnb \
    "sudo ./nr-softmodem -O /home/mobile/oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf --gNBs.[0].min_rxtxtime 6 --rfsim --sa"
echo "Run 'tmux attach -t gnb'"
sleep 10

echo "[*] Starting UE"
tmux new-session -d -s ue \
    "sudo ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 127.0.0.1"

echo "Run 'tmux attach -t ue'"
sleep 10

echo "[*] Pinging Uplink 10 times"
ping -c 10 $EXT_DN -I oaitun_ue1

UE_IP=$(ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo "IP of UE1: $UE_IP"

sleep 5

echo "[*] Pinging Downlink 10 times"
ssh -t ${SSH_USR}@${CORE_IP} "sudo docker exec oai-ext-dn ping -c 10 $UE_IP"

echo "[T1] Done"
