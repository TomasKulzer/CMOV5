#!/bin/bash
# ---------------------------------------------------------------
# Task 3 – Bandwidth reconfiguration & RTT measurement
#   - copies stock gNB config, patches for 20|100 MHz @ 3500 MHz
#   - starts gNB with patched config
#   - starts 2 UEs  (each in its own netns)
#   - 60x uplink ping   per UE
#   - 60x downlink ping per UE
#   - leaves gNB + UEs running so Task 4 can follow
# ---------------------------------------------------------------
# Usage:  sudo bash task3.sh <20|100>
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
echo "[T3] Generating config for ${BW} MHz  @  3500 MHz"

patch_config() {
    local key="$1" value="$2"
    # Try the pattern with a trailing semicolon first, fallback to raw number
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
echo "[T3] Starting gNB with modified config"
tmux new-session -d -s "${SESS[gnb]}" \
    "sudo ./nr-softmodem -O ${GNB_TMP_CONF} --gNBs.[0].min_rxtxtime 6 --rfsim --sa 2>&1 | stdbuf -oL tee /tmp/gnb_task3_full.log"
echo "      -> tmux attach -t ${SESS[gnb]}"
wait_for 15 "gNB booting and connecting to AMF"

# Capture startup log for reference
tmux capture-pane -t "${SESS[gnb]}" -p -S -3000 > /tmp/gnb_task3_full.log 2>/dev/null || true
head -55 /tmp/gnb_task3_full.log > /tmp/gnb_task3_startup.log 2>/dev/null || true

# ---- Namespaces ----
cleanup_netns
chmod +x "${SCRIPT_DIR}/multi-ue.sh"
echo "[T3] Creating network namespaces"
sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c1
sudo bash "${SCRIPT_DIR}/multi-ue.sh" -c2
wait_for 5 "namespaces settling"

# ---- UEs ----
UE_BASE="sudo ip netns exec"
UE_COMMON="-r ${UE_RB} --numerology 1 --band 78 -C ${UE_FREQ} --rfsim --sa"

echo "[T3] Starting UE1"
tmux new-session -d -s "${SESS[ue1]}" \
    "${UE_BASE} ue1 ./nr-uesoftmodem ${UE_COMMON} --uicc0.imsi 001010000000001 --rfsimulator.serveraddr 10.201.1.100 --telnetsrv --telnetsrv.listenport 9095 ${SSB_FLAG}"
echo "      -> tmux attach -t ${SESS[ue1]}"
wait_for 5 "UE1 initializing"

echo "[T3] Starting UE2"
tmux new-session -d -s "${SESS[ue2]}" \
    "${UE_BASE} ue2 ./nr-uesoftmodem ${UE_COMMON} --uicc0.imsi 001010000000002 --rfsimulator.serveraddr 10.202.1.100 --telnetsrv --telnetsrv.listenport 9096 ${SSB_FLAG}"
echo "      -> tmux attach -t ${SESS[ue2]}"
wait_for 15 "UEs attaching"

# ---- Uplink RTT ----
echo "[T3] Uplink ping  (60x)  UE1 -> ext-dn"
sudo ip netns exec ue1 ping -c 10 "${EXT_DN}" -I oaitun_ue1 | tee "${OUTPUT_DIR}/rtt_ul_ue1_${BW}.txt"

echo "[T3] Uplink ping  (60x)  UE2 -> ext-dn"
sudo ip netns exec ue2 ping -c 10 "${EXT_DN}" -I oaitun_ue1 | tee "${OUTPUT_DIR}/rtt_ul_ue2_${BW}.txt"

# ---- Gather IPs ----
IP_UE1=$(ue_ip ue1)
IP_UE2=$(ue_ip ue2)
echo "[T3] UE1 IP = ${IP_UE1}"
echo "[T3] UE2 IP = ${IP_UE2}"

wait_for 5 "preparing downlink"

# ---- Downlink RTT ----
echo "[T3] Downlink ping  (60x)  ext-dn -> UE1"
ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec oai-ext-dn ping -c 10 ${IP_UE1}" 2>/dev/null | tee "${OUTPUT_DIR}/rtt_dl_ue1_${BW}.txt"

echo "[T3] Downlink ping  (60x)  ext-dn -> UE2"
ssh -t "${SSH_USER}@${CORE_HOST}" "sudo docker exec oai-ext-dn ping -c 10 ${IP_UE2}" 2>/dev/null | tee "${OUTPUT_DIR}/rtt_dl_ue2_${BW}.txt"

# ---- Print info for follow-up Task 4 ----
echo ""
echo "============================================"
echo "  Task 3 complete — gNB + UEs still running"
echo "  Bandwidth: ${BW} MHz"
echo "  UE1 IP: ${IP_UE1}"
echo "  UE2 IP: ${IP_UE2}"
echo "  Next:  bash task4.sh ${IP_UE1} ${IP_UE2} ${BW}"
echo "============================================"
