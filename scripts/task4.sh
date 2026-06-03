#!/bin/bash
# ---------------------------------------------------------------
# Task 3 + 4 – Bandwidth reconfiguration, RTT, and throughput
#   - copies stock gNB config, patches for 20|100 MHz @ 3500 MHz
#   - starts gNB with patched config
#   - starts 2 UEs  (each in its own netns)
#   - 60x uplink ping   per UE
#   - 60x downlink ping per UE
#   - 60s iperf throughput tests (UDP/TCP, UL/DL) per UE
# ---------------------------------------------------------------
# Usage:  sudo bash task4.sh <20|100>
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh" || die "config.sh missing in ${SCRIPT_DIR}"

BW="${1:-}"
[[ -z "${BW}" ]] && die "Usage: $0 <20|100>"
[[ "${BW}" != "20" && "${BW}" != "100" ]] && die "Bandwidth must be 20 or 100"

cleanup_sessions
cleanup_netns

setup_gnb_network

cd "${GNB_BUILD}" || die "Build directory not found"

# ---- Patch a copy of the stock gNB config ----
cp "${GNB_CONF}" "${GNB_TMP_CONF}"
echo "[T4] Generating config for ${BW} MHz  @  3500 MHz"

patch_config() {
    local key="$1" value="$2"
    sed -i '/#/!s/^\([[:space:]]*'"${key}"'[[:space:]]*=[[:space:]]*\).*$/\1 '"${value}"';/' "${GNB_TMP_CONF}" 2>/dev/null
}

patch_config_raw() {
    local key="$1" value="$2"
    sed -i 's/^\([[:space:]]*'"${key}"'[[:space:]]*=[[:space:]]*\)[0-9]*/\1 '"${value}"'/' "${GNB_TMP_CONF}" 2>/dev/null
}

if [ "${BW}" == "100" ]; then
    patch_config  absoluteFrequencySSB           630048
    patch_config  dl_absoluteFrequencyPointA      628776
    patch_config  dl_frequencyBand               78
    patch_config  dl_subcarrierSpacing           1
    patch_config  dl_carrierBandwidth            106
    patch_config  initialDLBWPlocationAndBandwidth  28875
    patch_config  initialDLBWPsubcarrierSpacing  1
    patch_config  initialDLBWPcontrolResourceSetZero  11
    patch_config  ul_frequencyBand               78
    patch_config  ul_carrierBandwidth            106
    patch_config  initialULBWPlocationAndBandwidth  28875
    patch_config  initialULBWPsubcarrierSpacing  1
    UE_RB=106
    UE_FREQ="3450720000"
    SSB_FLAG=""
else
    patch_config  absoluteFrequencySSB           630048
    patch_config  dl_absoluteFrequencyPointA      629388
    patch_config  dl_frequencyBand               78
    patch_config  dl_subcarrierSpacing           1
    patch_config  dl_carrierBandwidth            51
    patch_config_raw  initialDLBWPlocationAndBandwidth  13750
    patch_config  initialDLBWPsubcarrierSpacing  1
    patch_config  initialDLBWPcontrolResourceSetZero  10
    patch_config  ul_frequencyBand               78
    patch_config  ul_carrierBandwidth            51
    patch_config_raw  initialULBWPlocationAndBandwidth  13750
    patch_config  initialULBWPsubcarrierSpacing  1
    UE_RB=51
    UE_FREQ="3450000000"
    SSB_FLAG="--ssb 210"
fi

# ---- Launch gNB (patched config) ----
echo "[T4] Starting gNB with modified config"
tmux new-session -d -s "${SESS[gnb]}" \
    "sudo ./nr-softmodem -O ${GNB_TMP_CONF} --gNBs.[0].min_rxtxtime 6 --rfsim --sa 2>&1 | tee /tmp/gnb_task3_full.log"
echo "      -> tmux attach -t ${SESS[gnb]}"
wait_for 15 "gNB booting and connecting to AMF"

# Capture startup log for reference
tmux capture-pane -t "${SESS[gnb]}" -p -S -3000 > /tmp/gnb_task3_full.log 2>/dev/null || true
head -55 /tmp/gnb_task3_full.log > /tmp/gnb_task3_startup.log 2>/dev/null || true

# ---- Namespaces ----
cleanup_netns
chmod +x "${SCRIPT_DIR}/multi-ue.sh"
echo "[T4] Creating network namespaces"
sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c1
wait_for 5
sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c2
wait_for 5 "namespaces settling"

# ---- UEs ----
UE_BASE="sudo ip netns exec"
UE_COMMON="-r ${UE_RB} --numerology 1 --band 78 -C ${UE_FREQ} --rfsim --sa"

echo "[T4] Starting UE1"
tmux new-session -d -s "${SESS[ue1]}" \
    "${UE_BASE} ue1 ./nr-uesoftmodem ${UE_COMMON} --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095 ${SSB_FLAG}"
echo "      -> tmux attach -t ${SESS[ue1]}"
wait_for 5 "UE1 initializing"

echo "[T4] Starting UE2"
tmux new-session -d -s "${SESS[ue2]}" \
    "${UE_BASE} ue2 ./nr-uesoftmodem ${UE_COMMON} --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096 ${SSB_FLAG}"
echo "      -> tmux attach -t ${SESS[ue2]}"
wait_for 15 "UEs attaching"

# ---- Uplink RTT ----
echo "[T4] Uplink ping  (60x)  UE1 -> ext-dn"
sudo ip netns exec ue1 ping -c 1 "${EXT_DN}" -I oaitun_ue1 | tee "/tmp/rtt_ul_ue1_${BW}.txt"

echo "[T4] Uplink ping  (60x)  UE2 -> ext-dn"
sudo ip netns exec ue2 ping -c 1 "${EXT_DN}" -I oaitun_ue1 | tee "/tmp/rtt_ul_ue2_${BW}.txt"

# ---- Gather IPs ----
IP_UE1=$(ue_ip ue1)
IP_UE2=$(ue_ip ue2)
echo "[T4] UE1 IP = ${IP_UE1}"
echo "[T4] UE2 IP = ${IP_UE2}"

# ---- Add default routes in namespaces for iperf ----
for ns in ue1 ue2; do
    sudo ip netns exec "${ns}" ip route del default 2>/dev/null || true
    sudo ip netns exec "${ns}" ip route add default dev oaitun_ue1
    echo "[T4] Added default route via oaitun_ue1 in ${ns}"
done

wait_for 5 "preparing downlink"

# ---- Downlink RTT ----
echo "[T4] Downlink ping  (60x)  ext-dn -> UE1"
ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec oai-ext-dn ping -c 1 ${IP_UE1}" 2>/dev/null | tee "/tmp/rtt_dl_ue1_${BW}.txt"

echo "[T4] Downlink ping  (60x)  ext-dn -> UE2"
ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec oai-ext-dn ping -c 1 ${IP_UE2}" 2>/dev/null | tee "/tmp/rtt_dl_ue2_${BW}.txt"

# ---- Throughput (Task 4) ----
BITRATE="10M"
DURATION="60"

run_iperf_suite() {
    local ns="$1" ue_ip="$2"

    

   

    echo "[T4] UDP Downlink  ${ns}"
    tmux new-session -d -s "${SESS[iperf]}" \
        "sudo ip netns exec ${ns} iperf -s -u -i 1 -B ${ue_ip}"
    echo "      -> tmux attach -t ${SESS[iperf]}"
    wait_for 10 "iperf server starting"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -it oai-ext-dn iperf -y C -u -t ${DURATION} -i 1 -fk -B ${EXT_DN} -b ${BITRATE} -c ${ue_ip}" \
        2>/dev/null | tee /tmp/task4_udp_dl_${ns}_${BW}.csv

    echo "[T4] UDP Uplink  ${ns}"
    echo "      -> iperf server running detached on Core"
    ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec -d oai-ext-dn iperf -s -u -i 1 -fk -B ${EXT_DN}" 2>/dev/null
    wait_for 10 "iperf server starting"
    sudo ip netns exec "${ns}" iperf -y C -u -t ${DURATION} -i 1 -fk -b ${BITRATE} -B "${ue_ip}" -c "${EXT_DN}" \
        | tee /tmp/task4_udp_ul_${ns}_${BW}.csv

    echo "[T4] TCP Downlink  ${ns}"
    tmux kill-session -t "${SESS[iperf]}" 2>/dev/null || true
    tmux new-session -d -s "${SESS[iperf]}" \
        "sudo ip netns exec ${ns} iperf -s -i 1 -B ${ue_ip}"
    echo "      -> tmux attach -t ${SESS[iperf]}"
    wait_for 10 "iperf server starting"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -it oai-ext-dn iperf -y C -t ${DURATION} -i 1 -fk -B ${EXT_DN} -c ${ue_ip}" \
        2>/dev/null | tee /tmp/task4_tcp_dl_${ns}_${BW}.csv

     echo "[T4] TCP Uplink  ${ns}"
    echo "      -> iperf server running detached on Core"
    ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec -d oai-ext-dn iperf -s -i 1 -fk -B ${EXT_DN}" 2>/dev/null
    wait_for 10 "iperf server starting"
    sudo ip netns exec "${ns}" iperf -y C -t ${DURATION} -i 1 -fk -B "${ue_ip}" -c "${EXT_DN}" \
        | tee /tmp/task4_tcp_ul_${ns}_${BW}.csv

    tmux kill-session -t "${SESS[iperf]}" 2>/dev/null || true
}


run_iperf_suite ue1 "${IP_UE1}"
run_iperf_suite ue2 "${IP_UE2}"



echo ""
echo "[T4] All RTT + throughput tests done"
echo "      Files saved to /tmp/rtt_*_${BW}.txt and /tmp/task4_*_${BW}.csv"