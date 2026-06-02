#!/bin/bash
# ---------------------------------------------------------------
# Task 4 – Throughput measurement (TCP & UDP, UL & DL)
#   Requires a running gNB + 2 UEs (from Task 3)
#   For each UE:
#     - UDP Downlink  (iperf server on UE, client on ext-dn)
#     - UDP Uplink    (iperf server on ext-dn, client on UE)
#     - TCP Downlink  (iperf server on UE, client on ext-dn)
#     - TCP Uplink    (iperf server on ext-dn, client on UE)
# ---------------------------------------------------------------
# Usage:  sudo bash task4.sh <UE1_IP> <UE2_IP> <20|100>
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh" || die "config.sh missing in ${SCRIPT_DIR}"

IP_UE1="${1:-}"
IP_UE2="${2:-}"
BW="${3:-}"

[[ -z "${IP_UE1}" || -z "${IP_UE2}" || -z "${BW}" ]] && \
    die "Usage: $0 <UE1_IP> <UE2_IP> <20|100>"

# Bitrate & duration
BITRATE="10M"
DURATION="60"

# Helper: pick the netns for a given UE IP
netns_of() {
    local ip="$1"
    if sudo ip netns exec ue1 ip addr show oaitun_ue1 2>/dev/null | grep -q "$ip"; then
        echo "ue1"
    elif sudo ip netns exec ue2 ip addr show oaitun_ue1 2>/dev/null | grep -q "$ip"; then
        echo "ue2"
    else
        echo ""
    fi
}

run_iperf_test() {
    local ue_ip="$1" direction="$2" protocol="$3"
    local ns
    ns=$(netns_of "$ue_ip")
    [[ -z "${ns}" ]] && { echo "  [WARN] No netns found for ${ue_ip} — skipping"; return; }

    local suffix="${protocol}_${direction}"
    case "${direction}_${protocol}" in
        dl_udp)
            echo "  [UDP DL] Server on UE, client on ext-dn"
            tmux new-session -d -s "${SESS[iperf]}" \
                "sudo ip netns exec ${ns} iperf -s -u -i 1 -B ${ue_ip}"
            echo "    -> tmux attach -t ${SESS[iperf]}"
            wait_for 10 "iperf server starting"
            ssh -t "${SSH_USER}@${CORE_HOST}" \
                "sudo docker exec -it oai-ext-dn iperf -y C -u -t ${DURATION} -i 1 -fk -B ${EXT_DN} -b ${BITRATE} -c ${ue_ip}" \
                2>/dev/null | tee "${OUTPUT_DIR}/throughput_${suffix}_${ns}_${BW}.csv"
            ;;
        ul_udp)
            echo "  [UDP UL] Server on ext-dn, client on UE"
            ssh -t "${SSH_USER}@${CORE_HOST}" \
                "sudo docker exec -d oai-ext-dn iperf -s -u -i 1 -fk -B ${EXT_DN}" \
                2>/dev/null
            wait_for 10 "iperf server starting"
            sudo ip netns exec "${ns}" iperf -y C -u -t ${DURATION} -i 1 -fk -b ${BITRATE} -B "${ue_ip}" -c "${EXT_DN}" \
                | tee "${OUTPUT_DIR}/throughput_${suffix}_${ns}_${BW}.csv"
            ;;
        dl_tcp)
            echo "  [TCP DL] Server on UE, client on ext-dn"
            tmux new-session -d -s "${SESS[iperf]}" \
                "sudo ip netns exec ${ns} iperf -s -i 1 -B ${ue_ip}"
            echo "    -> tmux attach -t ${SESS[iperf]}"
            wait_for 10 "iperf server starting"
            ssh -t "${SSH_USER}@${CORE_HOST}" \
                "sudo docker exec -it oai-ext-dn iperf -y C -t ${DURATION} -i 1 -fk -B ${EXT_DN} -c ${ue_ip}" \
                2>/dev/null | tee "${OUTPUT_DIR}/throughput_${suffix}_${ns}_${BW}.csv"
            ;;
        ul_tcp)
            echo "  [TCP UL] Server on ext-dn, client on UE"
            ssh -t "${SSH_USER}@${CORE_HOST}" \
                "sudo docker exec -d oai-ext-dn iperf -s -i 1 -fk -B ${EXT_DN}" \
                2>/dev/null
            wait_for 10 "iperf server starting"
            sudo ip netns exec "${ns}" iperf -y C -t ${DURATION} -i 1 -fk -B "${ue_ip}" -c "${EXT_DN}" \
                | tee "${OUTPUT_DIR}/throughput_${suffix}_${ns}_${BW}.csv"
            ;;
    esac

    tmux kill-session -t "${SESS[iperf]}" 2>/dev/null || true
}

# ---- Run for both UEs ----
for UE_IP in "${IP_UE1}" "${IP_UE2}"; do
    echo ""
    echo "=========================================="
    echo "  Testing UE @ ${UE_IP}"
    echo "=========================================="

    echo ""
    echo "--- UDP Downlink ---"
    run_iperf_test "${UE_IP}" dl udp

    echo ""
    echo "--- UDP Uplink ---"
    run_iperf_test "${UE_IP}" ul udp

    echo ""
    echo "--- TCP Downlink ---"
    run_iperf_test "${UE_IP}" dl tcp

    echo ""
    echo "--- TCP Uplink ---"
    run_iperf_test "${UE_IP}" ul tcp
done

echo ""
echo "[T4] All throughput tests done"
echo "      Files saved to ~/throughput_*_${BW}.csv"
