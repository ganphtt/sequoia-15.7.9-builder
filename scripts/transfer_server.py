"""Loopback-only, single-file, authenticated download server. Never logs headers."""
import hmac
import http.server
import os
import re
import stat
import sys

ROOT = os.path.realpath(sys.argv[1])
TOKEN = os.environ.pop('TRANSFER_TOKEN').encode('ascii')
if len(TOKEN) < 64:
    raise SystemExit('Token must have at least 256 bits of entropy')

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def empty(self, status):
        self.send_response(status)
        self.send_header('Content-Length', '0')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()

    def do_GET(self):
        self.transfer()

    def do_HEAD(self):
        self.transfer()

    def do_POST(self):
        self.empty(405)

    do_PUT = do_DELETE = do_OPTIONS = do_PATCH = do_POST

    def transfer(self):
        supplied = self.headers.get('Authorization', '').encode('utf-8')
        if not hmac.compare_digest(supplied, b'Bearer ' + TOKEN):
            return self.empty(401)
        # Exact allowlist: no decoding, directories, query strings or traversal.
        if self.path != '/fixture.bin':
            return self.empty(404)
        try:
            fd = os.open(os.path.join(ROOT, 'fixture.bin'), os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            return self.empty(404)
        with os.fdopen(fd, 'rb') as f:
            st = os.fstat(f.fileno())
            if not stat.S_ISREG(st.st_mode):
                return self.empty(404)
            size = st.st_size
            start, end, status = 0, size - 1, 200
            rang = self.headers.get('Range')
            if rang:
                m = re.fullmatch(r'bytes=(\d+)-(\d*)', rang)
                if not m:
                    return self.empty(416)
                start = int(m[1]); end = min(int(m[2]), size - 1) if m[2] else size - 1
                if start > end or start >= size:
                    return self.empty(416)
                status = 206
            self.send_response(status)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            if status == 206:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            if self.command == 'HEAD':
                return
            f.seek(start)
            remaining = end - start + 1
            try:
                while remaining:
                    chunk = f.read(min(1024 * 1024, remaining))
                    if not chunk: break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[2])), Handler).serve_forever()
