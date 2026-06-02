from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json, os, re, csv, time
from urllib.parse import urlparse

BASE = os.path.expanduser('~')
# APP_DIR is where index.html is served from. Keep it equal to BASE so the
# dashboard sits in the same folder the data files are written to (~).
APP_DIR = BASE

STREAM_INTERVAL = 1.0   # seconds between pushes on /api/stream
ACTIVE_WINDOW   = 3.0   # a file modified within this many seconds is "live"

INTERVAL_RE = re.compile(r'^\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*$')
TIME_RE     = re.compile(r'time[=<]\s*([0-9.]+)\s*ms', re.IGNORECASE)
SUMMARY_RE  = re.compile(r'min/avg/max/mdev\s*=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+)')


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=APP_DIR, **kwargs)

    def log_message(self, *args):
        pass  # keep the console quiet during a run

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
        # Server-Sent Events: keep the connection open and push a fresh
        # snapshot every STREAM_INTERVAL seconds. ThreadingHTTPServer gives
        # each connection its own thread, so this loop is safe.
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()
        try:
            self.wfile.write(b'retry: 2000\n\n')   # client reconnect delay (ms)
            self.wfile.flush()
            while True:
                payload = json.dumps(collect_metrics())
                self.wfile.write(f'data: {payload}\n\n'.encode())
                self.wfile.flush()
                time.sleep(STREAM_INTERVAL)
        except (BrokenPipeError, ConnectionResetError):
            return  # browser tab closed / navigated away


def parse_ping_file(path):
    """Extract per-packet RTTs and a summary from a ping log."""
    samples, summary = [], {}
    if not os.path.exists(path):
        return {'samples': samples, 'summary': summary}
    with open(path, 'r', errors='ignore') as f:
        for line in f:
            m = TIME_RE.search(line)
            if m:
                samples.append(float(m.group(1)))
            s = SUMMARY_RE.search(line)
            if s:
                summary = {'min': float(s.group(1)), 'avg': float(s.group(2)),
                           'max': float(s.group(3)), 'mdev': float(s.group(4))}
    # If the test is still running there's no final summary line yet,
    # so report a live running summary instead.
    if not summary and samples:
        summary = {'min': min(samples), 'avg': sum(samples) / len(samples),
                   'max': max(samples), 'mdev': 0.0, 'live': True}
    return {'samples': samples, 'summary': summary}


def parse_iperf_csv(path):
    """
    Parse iPerf CSV output (-y C). Column layout:
        ts, srcip, srcport, dstip, dstport, id, interval, transfer_bytes, bandwidth_bps, ...
    Column 8 is bandwidth in BITS/sec -> Mbps = value / 1e6.
    Rows whose interval is wider than a normal tick (e.g. the 0.0-60.0
    cumulative line) are flagged as summary so the UI can skip them.
    """
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, 'r', errors='ignore') as f:
        for r in csv.reader(f):
            if len(r) < 9:
                continue
            m = INTERVAL_RE.match(r[6].strip())
            if not m:
                continue
            try:
                start = float(m.group(1))
                end = float(m.group(2))
                bps = float(r[8])
            except ValueError:
                continue
            rows.append({
                'interval': r[6].strip(),
                't_start': start,
                't_end': end,
                'kbps': bps / 1e3,
                'mbps': bps / 1e6,
                'summary': (end - start) > 1.5,
            })
    return rows


def collect_metrics():
    now = time.time()
    out = {'throughput': {}, 'rtt': {}, 'present_files': [],
           'active_files': [], 'server_time': now}

    for name in sorted(os.listdir(BASE)):
        if re.match(r'(throughput|rtt)_.*\.(csv|txt)$', name):
            out['present_files'].append(name)
            try:
                if now - os.path.getmtime(os.path.join(BASE, name)) <= ACTIVE_WINDOW:
                    out['active_files'].append(name)
            except OSError:
                pass

    for bw in ['20', '100']:
        out['throughput'][bw] = {}
        out['rtt'][bw] = {}
        for ns in ['ue1', 'ue2']:
            for kind in ['udp_dl', 'udp_ul', 'tcp_dl', 'tcp_ul']:
                fn = os.path.join(BASE, f'throughput_{kind}_{ns}_{bw}.csv')
                out['throughput'][bw][f'{kind}_{ns}'] = parse_iperf_csv(fn)
            for kind in ['ul', 'dl']:
                fn = os.path.join(BASE, f'rtt_{kind}_{ns}_{bw}.txt')
                out['rtt'][bw][f'{kind}_{ns}'] = parse_ping_file(fn)
    return out


if __name__ == '__main__':
    port = 8000
    print(f'Serving on http://127.0.0.1:{port}  (live stream at /api/stream)')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
