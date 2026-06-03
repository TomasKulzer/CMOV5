#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "[Task 5] Terminating any dangling dashboard deployments..."
tmux kill-session -t telemetry_dashboard 2>/dev/null

echo "[Task 5] Spawning the streaming pipeline and dashboard web server..."
tmux new-session -d -s telemetry_dashboard "cd ${SCRIPT_DIR} && python3 server.py"

echo "--------------------------------------------------------"
echo " Dashboard successfully deployed!"
echo " URL: http://127.0.0.1:8080"
echo " Keep task4.sh running to feed traffic metrics into the charts."
echo "--------------------------------------------------------"