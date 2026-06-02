#!/bin/bash
# ---------------------------------------------------------------
# Core-side packet capture (tcpdump)
#   Run this on the Core machine in a dedicated terminal
#   before launching the corresponding task on the gNB.
# ---------------------------------------------------------------
# Usage:  bash core_capture.sh <task_number>
#   task 1  ->  120 s timeout,  filename /tmp/dl-ul-pings-task1.pcap
#   task 2  ->  180 s timeout,  filename /tmp/dl-ul-pings-task2.pcap
#   task 3  ->  180 s timeout,  filename /tmp/dl-ul-pings-task3.pcap
# ---------------------------------------------------------------

TASK="${1:-}"

if [[ -z "${TASK}" ]]; then
    echo "Usage: $0 <1|2|3>" >&2
    exit 1
fi

case "${TASK}" in
    1) TIMEOUT=120 ;;
    2|3) TIMEOUT=180 ;;
    *)
        echo "Unknown task: ${TASK}" >&2
        echo "Valid: 1, 2, 3" >&2
        exit 1
        ;;
esac

PCAP_FILE="/tmp/dl-ul-pings-task${TASK}.pcap"
EXT_DN="192.168.70.135"

# Clean any previous capture
sudo rm -f "${PCAP_FILE}"

echo "[Capture] Task ${TASK} — listening for ${TIMEOUT}s"
echo "         Saving to ${PCAP_FILE}"
echo "         Filter:  udp port 2152 or host ${EXT_DN}"
echo "         Start your task on the gNB now."

sudo timeout "${TIMEOUT}" tcpdump -i any "udp port 2152 or host ${EXT_DN}" -U -w "${PCAP_FILE}"

echo "[Capture] Done: ${PCAP_FILE}"
