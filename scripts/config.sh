#!/bin/bash

# ---------------------------------------------------------------
# Shared configuration & helpers for OAI 5G lab tasks
# Source this from task scripts:  source config.sh
# ---------------------------------------------------------------

# --- Network addresses ---
CORE_HOST="10.227.20.82"
GNB_HOST="10.227.20.72"
EXT_DN="192.168.70.135"
AMF_IP="192.168.70.132"
DOCKER_SUBNET="192.168.70.128/26"

# --- Detect real user home (works with/without sudo) ---
if [ -n "${SUDO_USER}" ]; then
    REAL_USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_USER_HOME="${HOME}"
fi

# --- User paths (resolved for regular user even under sudo) ---
OUTPUT_DIR="${REAL_USER_HOME}"

# --- Paths ---
GNB_BUILD="${REAL_USER_HOME}/oai/cmake_targets/ran_build/build"
GNB_CONF="${REAL_USER_HOME}/oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf"
GNB_TMP_CONF="/tmp/gnb_task3.conf"
CORE_DIR="${REAL_USER_HOME}/oai-cn5g"

# --- SSH ---
SSH_USER="mobile"

# --- Tmux session identifiers ---
declare -A SESS
SESS[gnb]="gnb"
SESS[ue1]="ue1"
SESS[ue2]="ue2"
SESS[iperf]="iperf"

# ---------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

cleanup_sessions() {
    for tag in gnb ue1 ue2 iperf; do
        tmux kill-session -t "${SESS[$tag]}" 2>/dev/null || true
    done
}

cleanup_netns() {
    sudo ip netns del ue1 2>/dev/null || true
    sudo ip netns del ue2 2>/dev/null || true
    sudo ip link del v-eth1 2>/dev/null || true
    sudo ip link del v-eth2 2>/dev/null || true
    sudo rm -f /run/netns/ue* 2>/dev/null || true
}

ue_ip() {
    local ns="$1"
    sudo ip netns exec "$ns" ip addr show oaitun_ue1 2>/dev/null \
        | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo ""
}

wait_for() {
    local secs="$1" label="$2"
    echo "  >> ${label}  (${secs}s)"
    sleep "$secs"
}

wait_for_iface() {
    local ns="$1" iface="$2" max="${3:-30}" delay="${4:-2}"
    echo "  >> Waiting for ${iface} to get an IP..." >&2
    for i in $(seq 1 "${max}"); do
        local ip=""
        if [ "${ns}" = "host" ]; then
            ip=$(ip addr show "${iface}" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        else
            ip=$(sudo ip netns exec "${ns}" ip addr show "${iface}" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        fi
        if [ -n "${ip}" ]; then
            echo "    got IP ${ip} after $((i * delay))s" >&2
            echo "${ip}"
            return 0
        fi
        sleep "${delay}"
    done
    echo "    WARNING: ${iface} not ready after $((max * delay))s" >&2
    echo ""
    return 1
}
setup_gnb_network() {
    echo "[SETUP] Checking gNB network configuration..."

    # --- Route to Core subnet ---
    if ! ip route | grep -q "${DOCKER_SUBNET}"; then
        local ifaceCONF
        iface=$(ip route get "${CORE_HOST}" 2>/dev/null | awk '{print $5; exit}')
        [[ -z "${iface}" ]] && die "Cannot find interface to reach Core at ${CORE_HOST}"
        sudo ip route add "${DOCKER_SUBNET}" via "${CORE_HOST}" dev "${iface}"
        echo "  >> Added route: ${DOCKER_SUBNET} via ${CORE_HOST} dev ${iface}"
        sleep 2
    else
        echo "  >> Route to ${DOCKER_SUBNET} already present"
    fi

    # --- Fix gNB config: AMF address ---
    if grep -q "192.168.70.129/24" "${GNB_CONF}" 2>/dev/null; then
        sudo sed -i "s|192.168.70.129/24|${GNB_HOST}/32|g" "${GNB_CONF}"
        echo "  >> Fixed gNB config: 192.168.70.129/24 -> ${GNB_HOST}/32"
        sleep 2
    else
        echo "  >> gNB config AMF address already set"
    fi

    # --- Enable forwarding ---
    sudo sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null 2>&1
    sudo iptables -P FORWARD ACCEPT 2>/dev/null

    # --- Verify Core reachability ---
    if ping -c 2 -W 3 "${AMF_IP}" > /dev/null 2>&1; then
        echo "  >> AMF (${AMF_IP}) reachable"
    else
        echo "  [WARN] Cannot reach AMF at ${AMF_IP}"
    fi
    if ping -c 2 -W 3 "${EXT_DN}" > /dev/null 2>&1; then
        echo "  >> ext-dn (${EXT_DN}) reachable"
    else
        echo "  [WARN] Cannot reach ext-dn at ${EXT_DN}"
    fi

    echo "  >> Network setup done, settling..."
    sleep 3
}
