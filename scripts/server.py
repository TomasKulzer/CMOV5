import os, re, csv, time, json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# Set paths to the script directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = SCRIPT_DIR

STREAM_INTERVAL = 1.0   # seconds between pushes on /api/stream
ACTIVE_WINDOW   = 3.0   # a file modified within this many seconds is "live"

INTERVAL_RE = re.compile(r'^\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*$')
TIME_RE     = re.compile(r'time[=<]\s*([0-9.]+)\s*ms', re.IGNORECASE)
SUMMARY_RE  = re.compile(r'min/avg/max/mdev\s*=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+)')

KPM_KNOWN = {
    'DRB.UEThpDl', 'DRB.UEThpUl',
    'RRU.PrbTotDl', 'RRU.PrbTotUl',
    'DRB.PdcpSduVolumeDL', 'DRB.PdcpSduVolumeUL',
    'DRB.RlcSduDelayDl',
}

def kpm_csv_path():
    env = os.environ.get('KPM_CSV')
    if env:
        return os.path.expanduser(env)
    candidates = [os.path.join(SCRIPT_DIR, 'kpm_results.csv'),
                  os.path.join(os.getcwd(), 'kpm_results.csv')]
    for c in candidates:
        if os.path.exists(c):
            return c
    return candidates[0]

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=APP_DIR, **kwargs)

    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/api/metrics':
            self._send_json(collect_metrics())
            return
        if path == '/api/stream':
            self._stream()
            return
        return super().do_GET()

    def _send_json(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def _stream(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()
        try:
            self.wfile.write(b'retry: 2000\n\n')
            self.wfile.flush()
            while True:
                payload = json.dumps(collect_metrics())
                self.wfile.write(f'data: {payload}\n\n'.encode())
                self.wfile.flush()
                time.sleep(STREAM_INTERVAL)
        except (BrokenPipeError, ConnectionResetError):
            return

def parse_kpm_csv(path):
    metrics, other = {}, {}
    first_ts = None
    if not os.path.exists(path):
        return {'present': False, 'metrics': metrics, 'other_metrics': other, 'path': path}

    with open(path, 'r', errors='ignore') as f:
        for line in f:
            parts = line.rstrip('\n').split(',')
            if len(parts) < 5:
                continue
            try:
                ts = float(parts[0])
                val = float(parts[4])
            except ValueError:
                continue
            
            metric = parts[3].strip()
            if first_ts is None:
                first_ts = ts
            
            point = {'t': (ts - first_ts) / 1e6, 'y': val}
            bucket = metrics if metric in KPM_KNOWN else other
            bucket.setdefault(metric, []).append(point)

    return {'present': bool(metrics or other), 'metrics': metrics, 'first_ts_us': first_ts, 'path': path}

def collect_metrics():
    out = {'server_time': time.time()}
    kpm_path = kpm_csv_path()
    out['kpm'] = parse_kpm_csv(kpm_path)
    return out

if __name__ == '__main__':
    port = 8000
    print(f'Serving on http://127.0.0.1:{port}')
    print(f'Reading KPM from: {kpm_csv_path()}')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()