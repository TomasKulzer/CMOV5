import os
import re
import csv
import time
import json
import threading
import subprocess
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.expanduser('~')
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))

# Thread-safe in-memory global database for xApp Telemetry
LIVE_METRICS = {
    "DRB.UEThpDl": [],
    "DRB.UEThpUl": [],
    "RRU.PrbTotDl": [],
    "RRU.PrbTotUl": []
}
START_TIME = time.time()
db_lock = threading.Lock()

def xapp_stream_worker():
    """Launches the monitor xApp as a subprocess and streams its stdout live."""
    xapp_path = os.path.join(BASE_DIR, "flexric/build/examples/xApp/c/monitor/xapp_kpm_moni")
    print(f"[Worker] Spawning xApp Subprocess stream from: {xapp_path}")
    
    proc = subprocess.Popen(
        [xapp_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )
    
    # Read the console logs line by line as they are emitted
    for line in iter(proc.stdout.readline, ''):
        if "=" in line:
            try:
                # Standard output format: "DRB.UEThpDl = 12500.50 [kbps]" or "RRU.PrbTotDl = 14 [PRBs]"
                left, right = line.split("=", 1)
                metric_name = left.split()[-1].strip()
                numeric_val = float(right.split("[")[0].strip())
                
                if metric_name in LIVE_METRICS:
                    with db_lock:
                        timestamp = round(time.time() - START_TIME, 1)
                        LIVE_METRICS[metric_name].append({"x": timestamp, "y": numeric_val})
                        # Keep window bound to the last 60 seconds of data
                        if len(LIVE_METRICS[metric_name]) > 120:
                            LIVE_METRICS[metric_name].pop(0)
            except Exception:
                pass
    proc.wait()

# --- Task 4 File Parsers ---
def parse_iperf(path):
    points = []
    if not os.path.exists(path): return points
    with open(path, 'r') as f:
        for row in csv.reader(f):
            if len(row) >= 9:
                try:
                    intervals = row[6].split('-')
                    end_time = float(intervals[1].strip())
                    mbps = float(row[8]) / 1e6
                    if end_time > 1.5: continue # skip summary rows
                    points.append({"x": end_time, "y": round(mbps, 2)})
                except Exception: pass
    return points

def parse_ping(path):
    points = []
    if not os.path.exists(path): return points
    with open(path, 'r') as f:
        idx = 1
        for line in f:
            match = re.search(r'time[=<]\s*([0-9.]+)\s*ms', line, re.I)
            if match:
                points.append({"x": idx, "y": float(match.group(1))})
                idx += 1
    return points

class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SCRIPT_DIR, **kwargs)

    def log_message(self, format, *args): pass # Mute annoying HTTP poll logs

    def do_GET(self):
        if self.path == '/api/data':
            # Collect and package everything into a unified state payload
            with db_lock:
                xapp_snapshot = json.loads(json.dumps(LIVE_METRICS))
            
            payload = {
                "xapp": xapp_snapshot,
                "iperf": {
                    "ue1_20_dl": parse_iperf(os.path.join(BASE_DIR, "throughput_tcp_dl_ue1_20.csv")),
                    "ue1_20_ul": parse_iperf(os.path.join(BASE_DIR, "throughput_tcp_ul_ue1_20.csv")),
                    "ue2_20_dl": parse_iperf(os.path.join(BASE_DIR, "throughput_tcp_dl_ue2_20.csv")),
                    "ue2_20_ul": parse_iperf(os.path.join(BASE_DIR, "throughput_tcp_ul_ue2_20.csv")),
                },
                "ping": {
                    "ue1_20_dl": parse_ping(os.path.join(BASE_DIR, "rtt_dl_ue1_20.txt")),
                    "ue2_20_dl": parse_ping(os.path.join(BASE_DIR, "rtt_dl_ue2_20.txt"))
                }
            }
            body = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

if __name__ == '__main__':
    # Fire up the background xApp output parsing engine
    t = threading.Thread(target=xapp_stream_worker, daemon=True)
    t.start()
    
    print("Serving custom telemetry engine on http://127.0.0.1:8080")
    ThreadingHTTPServer(('0.0.0.0', 8080), DashboardHandler).serve_forever()