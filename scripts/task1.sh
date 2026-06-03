#!/bin/bash
# ---------------------------------------------------------------
# Task 1 – Single UE connectivity
# ---------------------------------------------------------------

CORE_IP="10.227.20.62"
EXT_DN="192.168.70.135"
SSH_USR="mobile"

# Absolute paths to bypass background relative path drift
GNB_CONF_PATH="/home/mobile/oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf"
BIN_DIR="/home/mobile/oai/cmake_targets/ran_build/build"

# Clean up legacy runs and locks
sudo killall -9 nr-softmodem nr-uesoftmodem 2>/dev/null
tmux kill-session -t gnb 2>/dev/null
tmux kill-session -t ue 2>/dev/null
tmux kill-session -t iperf 2>/dev/null

echo "+----------------------+"
echo "|        TASK 1        |"
echo "+----------------------+"

echo "[*] Starting gNB"
cd "$BIN_DIR"
tmux new-session -d -s gnb \
    "sudo ./nr-softmodem -O $GNB_CONF_PATH --gNBs.[0].min_rxtxtime 6 --rfsim --sa"

echo "Run 'tmux attach -t gnb'"
sleep 15  # Give gNB time to spin up and bind SCTP to the Core Network

echo "[*] Starting UE"
tmux new-session -d -s ue \
    "sudo ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 127.0.0.1"

echo "Run 'tmux attach -t ue'"
echo "Waiting for cellular interface registration..."
sleep 20  # Crucial: Gives the simulator link time to settle and spawn oaitun_ue1

echo "[*] Pinging Uplink 10 times"
ping -c 10 $EXT_DN -I oaitun_ue1

UE_IP=$(ip addr show oaitun_ue1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

if [ -z "$UE_IP" ]; then
    echo "[ERROR] UE failed to secure an IP interface. Check 'tmux attach -t ue'"
    exit 1
fi

echo "IP of UE1: $UE_IP"
sleep 5

echo "[*] Pinging Downlink 10 times"
ssh -t ${SSH_USR}@${CORE_IP} "sudo docker exec oai-ext-dn ping -c 10 $UE_IP"

echo "[T1] Done"