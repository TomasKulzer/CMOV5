#!/bin/bash
# ---------------------------------------------------------------
# Task 4 – Throughput measurement (TCP & UDP, UL & DL)
#   Requires a running gNB + 2 UEs (from Task 3)
#   Auto-detects UE IPs from the live netns state
#   For each UE:
#     - UDP Downlink  (iperf server on UE, client on ext-dn)
#     - UDP Uplink    (iperf server on ext-dn, client on UE)
#     - TCP Downlink  (iperf server on UE, client on ext-dn)
#     - TCP Uplink    (iperf server on ext-dn, client on UE)
# ---------------------------------------------------------------
# Usage:  sudo bash task4.sh <20|100>
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh" || die "config.sh missing in ${SCRIPT_DIR}"

BW="${1:-}"

[[ -z "${BW}" ]] && die "Usage: $0 <20|100>"
[[ "${BW}" != "20" && "${BW}" != "100" ]] && die "Bandwidth must be 20 or 100"

BITRATE="10M"
DURATION="60"

start_ue_iperf_server() {
    local ns="$1" ue_ip="$2" protocol="$3"

    tmux kill-session -t iperf 2>/dev/null || true

    case "${protocol}" in
        udp)
            tmux new-session -d -s iperf "sudo ip netns exec ${ns} iperf -s -u -i 1 -B ${ue_ip}"
            ;;
        tcp)
            tmux new-session -d -s iperf "sudo ip netns exec ${ns} iperf -s -i 1 -B ${ue_ip}"
            ;;
    esac

    echo "Run 'tmux attach -t iperf'"
    sleep 10
}

stop_iperf_server() {
    tmux kill-session -t iperf 2>/dev/null || true
}

IP_UE1="$(ue_ip ue1)"
IP_UE2="$(ue_ip ue2)"

[[ -z "${IP_UE1}" || -z "${IP_UE2}" ]] && \
    die "Could not detect UE IPs. Run Task 3 first and make sure ue1/ue2 are still up."

echo "[T4] UE1 IP = ${IP_UE1}"
echo "[T4] UE2 IP = ${IP_UE2}"

run_for_ue() {
    local ns="$1" ue_ip="$2"

    echo ""
    echo "+-------------------------+"
    echo "| Testing: ${ue_ip} |"
    echo "+-------------------------+"

    echo ""
    echo "+----------------------+"
    echo "|          UDP         |"
    echo "+----------------------+"
    echo ""

    echo "[*] Preparing iPerf UDP Downlink for throughput"
    echo "[*] Starting iPerf Server"
    start_ue_iperf_server "${ns}" "${ue_ip}" udp

    echo "[*] Starting iPerf UDP Client for ${DURATION} seconds"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -it oai-ext-dn iperf -y C -u -t ${DURATION} -i 1 -fk -B ${EXT_DN} -b ${BITRATE} -c ${ue_ip}" \
        | tee /tmp/task4_udp_dl_${ns}_${BW}.csv

    echo "[*] Preparing iPerf UDP Uplink for throughput"
    echo "[*] Starting iPerf Server for ${DURATION} seconds"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -d oai-ext-dn iperf -s -u -i 1 -fk -B ${EXT_DN}"

    sleep 10

    echo "[*] Starting iPerf UDP Client"
    sudo ip netns exec "${ns}" iperf -y C -u -t ${DURATION} -i 1 -fk -b ${BITRATE} -B "${ue_ip}" -c "${EXT_DN}" \
        | tee /tmp/task4_udp_ul_${ns}_${BW}.csv

    echo ""
    echo "+----------------------+"
    echo "|          TCP         |"
    echo "+----------------------+"
    echo ""

    stop_iperf_server

    echo "[*] Preparing iPerf TCP Downlink for throughput"
    echo "[*] Starting iPerf Server"
    start_ue_iperf_server "${ns}" "${ue_ip}" tcp

    echo "[*] Starting iPerf TCP Client for ${DURATION} seconds"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -it oai-ext-dn iperf -y C -t ${DURATION} -i 1 -fk -B ${EXT_DN} -c ${ue_ip}" \
        | tee /tmp/task4_tcp_dl_${ns}_${BW}.csv

    echo "[*] Preparing iPerf TCP Uplink for throughput"
    echo "[*] Starting iPerf Server for ${DURATION} seconds"
    ssh -t "${SSH_USER}@${CORE_HOST}" \
        "sudo docker exec -d oai-ext-dn iperf -s -i 1 -fk -B ${EXT_DN}"

    sleep 10

    echo "[*] Starting iPerf TCP Client"
    sudo ip netns exec "${ns}" iperf -y C -t ${DURATION} -i 1 -fk -B "${ue_ip}" -c "${EXT_DN}" \
        | tee /tmp/task4_tcp_ul_${ns}_${BW}.csv

    stop_iperf_server
}

echo "+----------------------+"
echo "|        TASK 4        |"
echo "+----------------------+"

run_for_ue ue1 "${IP_UE1}"
run_for_ue ue2 "${IP_UE2}"

echo ""
echo "[T4] All throughput tests done"
echo "      Files saved to /tmp/task4_*_${BW}.csv"