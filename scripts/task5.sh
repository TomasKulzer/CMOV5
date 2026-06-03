#!/bin/bash
# ---------------------------------------------------------------
# Task 5 – Script/Web Interface to monitor and plot metrics
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEXRIC_DIR="${HOME}/flexric"

# 1. Start nearRT-RIC (The Core Controller)
echo "[T5] Starting nearRT-RIC..."
tmux kill-session -t ric_daemon 2>/dev/null
tmux new-session -d -s ric_daemon "cd ${FLEXRIC_DIR} && ./build/examples/ric/nearRT-RIC"
sleep 3

# 2. Start the KPM Monitor xApp (NOT the RC xApp)
# We navigate into its native directory so it can write its hardcoded CSV safely
echo "[T5] Starting KPIMON xApp..."
tmux kill-session -t xapp_monitor 2>/dev/null
tmux new-session -d -s xapp_monitor "cd ${FLEXRIC_DIR}/build/examples/xApp/c/monitor && ./xapp_kpm_moni"

echo "      -> KPIMON xApp running in tmux session 'xapp_monitor'"

# 3. Start the Python Web Server
# Explicitly tell Python where the xApp is hiding the CSV file
export KPM_CSV="${FLEXRIC_DIR}/build/examples/xApp/c/monitor/kpm_results.csv"

echo "[T5] Starting Python Web Server (server.py)..."
tmux kill-session -t web_server 2>/dev/null
tmux new-session -d -s web_server "python3 ${SCRIPT_DIR}/server.py"

echo "      -> Web server running in tmux session 'web_server'"
echo ""
echo "=================================================================="
echo " Monitor Interface is LIVE! "
echo " Open your web browser and navigate to: http://127.0.0.1:8000"
echo " Note: The graph will remain flat until task4.sh triggers iperf!"
echo " To stop the server and xApp, run:"
echo "   tmux kill-session -t xapp_monitor && tmux kill-session -t web_server"
echo "=================================================================="