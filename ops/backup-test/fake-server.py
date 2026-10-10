# เซิร์ฟเวอร์ปลอมสำหรับ e2e.sh: Healthchecks (/hc, /hc/start, /hc/fail) และ Data API (/rest/v1/rpc/ping)
# บันทึกทุกคำขอเป็นบรรทัด "METHOD path body" ลงไฟล์ใน argv[2]
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(size).decode('utf-8', 'replace').replace('\n', ' ')
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(f'POST {self.path} {body}\n')
        if self.path == '/rest/v1/rpc/ping':
            ok = self.headers.get('apikey') == 'test-ping-key'
            self.send_response(200 if ok else 401)
            self.end_headers()
            self.wfile.write(b'"pong"' if ok else b'{"message":"Invalid API key"}')
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

    def log_message(self, *args):
        pass


HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
