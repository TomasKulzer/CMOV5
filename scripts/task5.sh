#!/bin/bash
# ---------------------------------------------------------------
# Task 5 – Script/Web Interface to monitor and plot metrics
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh" 2>/dev/null || echo "Warning: config.sh not found"

FLEXRIC_DIR="${HOME}/flexric"
KPM_XAPP="${FLEXRIC_DIR}/build/examples/xApp/c/monitor/xapp_kpm_moni"
CSV_OUT="${SCRIPT_DIR}/kpm_results.csv"

# 1. Start the KPM Monitor xApp in a tmux session
echo "[T5] Starting KPIMON xApp and routing output to ${CSV_OUT}"
# Note: If your xApp writes natively to a file, adjust this line. 
# Here we pipe standard output to the CSV file the Python server expects.
tmux kill-session -t xapp_monitor 2>/dev/null
tmux new-session -d -s xapp_monitor \
    "stdbuf -oL ${KPM_XAPP} | awk '/DRB|RRU/ { print strftime(\"%s000000\"), \"0\", \"0\", \$1, \$3 }' > ${CSV_OUT}"

echo "      -> xApp running in tmux session 'xapp_monitor'"

# 2. Start the Python Web Server
echo "[T5] Starting Python Web Server (server.py)..."
export KPM_CSV="${CSV_OUT}"
tmux kill-session -t web_server 2>/dev/null
tmux new-session -d -s web_server "python3 ${SCRIPT_DIR}/server.py"

echo "      -> Web server running in tmux session 'web_server'"
echo ""
echo "=================================================================="
echo " Monitor Interface is LIVE! "
echo " Open your web browser and navigate to: http://127.0.0.1:8000"
echo " To stop the server and xApp, run:"
echo "   tmux kill-session -t xapp_monitor && tmux kill-session -t web_server"
echo "=================================================================="