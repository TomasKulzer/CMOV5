#!/bin/bash
# ---------------------------------------------------------------
# Task 5 – Script/Web Interface to monitor and plot metrics
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEXRIC_DIR="${HOME}/flexric"

# 1. Start the core nearRT-RIC daemon
echo "[T5] Starting nearRT-RIC..."
tmux kill-session -t ric_daemon 2>/dev/null
tmux new-session -d -s ric_daemon "cd ${FLEXRIC_DIR} && ./build/examples/ric/nearRT-RIC"
sleep 3 # Give the RIC a few seconds to fully boot

# 2. Start the KPM Monitor xApp 
# We run it directly in the SCRIPT_DIR so if it natively creates kpm_results.csv, it drops it here.
echo "[T5] Starting KPIMON xApp..."
tmux kill-session -t xapp_monitor 2>/dev/null

# Option A: If your lab's xApp natively generates the CSV, use this line:
tmux new-session -d -s xapp_monitor "cd ${SCRIPT_DIR} && ${FLEXRIC_DIR}/build/examples/xApp/c/monitor/xapp_kpm_moni"

# Option B: If it just prints to the terminal and you NEED awk to parse it, 
# comment out Option A and uncomment this line instead:
# tmux new-session -d -s xapp_monitor "stdbuf -oL ${FLEXRIC_DIR}/build/examples/xApp/c/monitor/xapp_kpm_moni | awk '/DRB|RRU/ { print strftime(\"%s000000\"), \"0\", \"0\", \$1, \$3 }' > ${SCRIPT_DIR}/kpm_results.csv"

echo "      -> xApp running in tmux session 'xapp_monitor'"

# 3. Start the Python Web Server
echo "[T5] Starting Python Web Server (server.py)..."
export KPM_CSV="${SCRIPT_DIR}/kpm_results.csv"
tmux kill-session -t web_server 2>/dev/null
tmux new-session -d -s web_server "python3 ${SCRIPT_DIR}/server.py"

echo "      -> Web server running in tmux session 'web_server'"
echo ""
echo "=================================================================="
echo " Monitor Interface is LIVE! "
echo " Open your web browser and navigate to: http://127.0.0.1:8000"
echo "=================================================================="