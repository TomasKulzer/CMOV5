#!/bin/bash
# ---------------------------------------------------------------
# Simplified Task 5 – Direct Plotting Wrapper
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEXRIC_DIR="${HOME}/flexric"
KPM_XAPP="${FLEXRIC_DIR}/build/examples/xApp/c/monitor/xapp_kpm_moni"
CSV_OUT="${SCRIPT_DIR}/kpm_results.csv"

# 1. Clear out old logs
rm -f "${CSV_OUT}"

# 2. Fire up the KPM monitor inside a background tmux session
echo "[T5] Starting KPIMON xApp..."
tmux kill-session -t xapp_monitor 2>/dev/null
tmux new-session -d -s xapp_monitor \
    "stdbuf -oL ${KPM_XAPP} | awk '/DRB|RRU/ { print strftime(\"%s000000\"), \"0\", \"0\", \$1, \$3 }' > ${CSV_OUT}"

echo "      -> xApp streaming telemetry into ${CSV_OUT}"
echo "[T5] Launching simplified Matplotlib UI..."

# 3. Run the pure Python visualizer locally
python3 "${SCRIPT_DIR}/task5_simple.py"