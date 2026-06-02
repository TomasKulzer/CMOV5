#!/bin/bash
# ---------------------------------------------------------------
# Task 3 + 4 – Bandwidth reconfiguration, RTT, and throughput
# ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh" || die "config.sh missing in ${SCRIPT_DIR}"

BW="${1:-}"
[[ -z "${BW}" ]] && die "Usage: $0 <20|100>"

cleanup_sessions
cleanup_netns
setup_gnb_network

# --- Patching Config (Same as before) ---
cp "${GNB_CONF}" "${GNB_TMP_CONF}"
# [ ... keep your existing patch_config logic here ... ]
if [ "${BW}" == "100" ]; then
    # ... (100MHz patching) ...
    UE_RB=106; UE_FREQ="3450720000"; SSB_FLAG=""
else
    # ... (20MHz patching) ...
    UE_RB=51; UE_FREQ="3450000000"; SSB_FLAG="--ssb 210"
fi

# --- Launch gNB/UEs ---
tmux new-session -d -s "${SESS[gnb]}" "sudo ./nr-softmodem -O ${GNB_TMP_CONF} --rfsim --sa 2>&1 | tee /tmp/gnb_task3_full.log"
wait_for 15 "gNB booting"

sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c1
sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c2
wait_for 5 "Namespaces created"

tmux new-session -d -s "${SESS[ue1]}" "sudo ip netns exec ue1 ./nr-uesoftmodem -r ${UE_RB} --numerology 1 --band 78 -C ${UE_FREQ} --rfsim --sa --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095 ${SSB_FLAG}"
tmux new-session -d -s "${SESS[ue2]}" "sudo ip netns exec ue2 ./nr-uesoftmodem -r ${UE_RB} --numerology 1 --band 78 -C ${UE_FREQ} --rfsim --sa --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096 ${SSB_FLAG}"
wait_for 15 "UEs attaching"

IP_UE1=$(ue_ip ue1)
IP_UE2=$(ue_ip ue2)

# --- Task 4: The "Working" Loop ---
echo "+----------------------+"
echo "|        TASK 4        |"
echo "+----------------------+"

BITRATE="10M" 
TIME="60"

for CURRENT_IP_UE in $IP_UE1 $IP_UE2; do
    echo "[Testing: $CURRENT_IP_UE]"
    NS="ue1"; [ "$CURRENT_IP_UE" == "$IP_UE2" ] && NS="ue2"

    # UDP
    tmux kill-session -t iperf 2>/dev/null
    tmux new-session -d -s iperf "sudo ip netns exec $NS iperf -s -u -i 1 -B $CURRENT_IP_UE"
    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec -it oai-ext-dn iperf -y C -u -t $TIME -i 1 -fk -B $EXT_DN -b $BITRATE -c $CURRENT_IP_UE" | tee /tmp/task4_udp_dl_${NS}_${BW}.csv
    
    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec -d oai-ext-dn iperf -s -u -i 1 -fk -B $EXT_DN"
    sleep 5
    sudo ip netns exec $NS iperf -y C -u -t $TIME -i 1 -fk -b $BITRATE -B $CURRENT_IP_UE -c $EXT_DN | tee /tmp/task4_udp_ul_${NS}_${BW}.csv
    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec oai-ext-dn pkill iperf"

    # TCP
    tmux kill-session -t iperf 2>/dev/null
    tmux new-session -d -s iperf "sudo ip netns exec $NS iperf -s -i 1 -B $CURRENT_IP_UE"
    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec -it oai-ext-dn iperf -y C -t $TIME -i 1 -fk -B $EXT_DN -c $CURRENT_IP_UE" | tee /tmp/task4_tcp_dl_${NS}_${BW}.csv

    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec -d oai-ext-dn iperf -s -i 1 -fk -B $EXT_DN"
    sleep 5
    sudo ip netns exec $NS iperf -y C -t $TIME -i 1 -fk -B $CURRENT_IP_UE -c $EXT_DN | tee /tmp/task4_tcp_ul_${NS}_${BW}.csv
    
    ssh -t ${SSH_USER}@${CORE_HOST} "sudo docker exec oai-ext-dn pkill iperf"
done

tmux kill-session -t iperf 2>/dev/null
echo "Task 4 Complete."