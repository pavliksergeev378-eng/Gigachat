# v13: bind proxy to 0.0.0.0 for remote browser access when page is opened by server IP
# n8n-proxy-8777.py
# Локальный proxy для обхода CORS.
#
# Версия 3:
# - поддерживает Basic Auth для n8n;
# - поддерживает Cookie для n8n /rest/*;
# - поддерживает X-N8N-API-KEY;
# - читает переменные окружения, которые можно задать в n8n-proxy-auth.local.cmd.
#
# Проверка:
#   http://localhost:8777/n8n-healthz

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
import os
import sys
import traceback
import base64

HOST = '0.0.0.0'
PORT = int(os.environ.get("PROXY_PORT", "8777"))
N8N_BASE = os.environ.get("N8N_BASE", "http://130.100.92.170:5678").rstrip("/")
TIMEOUT = int(os.environ.get("N8N_PROXY_TIMEOUT", "120"))

N8N_BASIC_AUTH_USER = os.environ.get("N8N_BASIC_AUTH_USER", "")
N8N_BASIC_AUTH_PASSWORD = os.environ.get("N8N_BASIC_AUTH_PASSWORD", "")
N8N_API_KEY = os.environ.get("N8N_API_KEY", "")
N8N_COOKIE = os.environ.get("N8N_COOKIE", "")

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}

def allowed_path(path):
    return (
        path == "/n8n-healthz"
        or path == "/rest"
        or path.startswith("/rest/")
        or path.startswith("/webhook")
        or path.startswith("/webhook-trigger")
    )

def map_path(path, query):
    if path == "/n8n-healthz":
        target = "/healthz"
    else:
        target = path
    if query:
        target += "?" + query
    return target

def apply_upstream_auth(headers):
    # Basic Auth, если n8n защищён N8N_BASIC_AUTH_USER/PASSWORD.
    if N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD and "Authorization" not in headers:
        raw = f"{N8N_BASIC_AUTH_USER}:{N8N_BASIC_AUTH_PASSWORD}".encode("utf-8")
        headers["Authorization"] = "Basic " + base64.b64encode(raw).decode("ascii")

    # n8n API key. Для /rest/* может не помочь, но не мешает.
    if N8N_API_KEY and "X-N8N-API-KEY" not in headers:
        headers["X-N8N-API-KEY"] = N8N_API_KEY

    # Cookie n8n-сессии. Может понадобиться именно для /rest/workflows.
    if N8N_COOKIE and "Cookie" not in headers:
        headers["Cookie"] = N8N_COOKIE

class Handler(BaseHTTPRequestHandler):
    server_version = "n8n-proxy-8777/3.0"

    def log_message(self, fmt, *args):
        sys.stdout.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))
        sys.stdout.flush()

    def add_cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Auth-Token, Authorization, X-N8N-API-KEY")
        self.send_header("Access-Control-Max-Age", "86400")

    def send_json(self, status, obj):
        import json
        data = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.add_cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204)
        self.add_cors()
        self.end_headers()

    def do_HEAD(self): self.proxy()
    def do_GET(self): self.proxy()
    def do_POST(self): self.proxy()
    def do_PUT(self): self.proxy()
    def do_PATCH(self): self.proxy()
    def do_DELETE(self): self.proxy()

    def proxy(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if not allowed_path(path):
            return self.send_json(404, {
                "error": "Proxy route not found",
                "allowed": ["/n8n-healthz", "/rest/*", "/webhook*", "/webhook-trigger*"],
                "path": path,
            })

        target_url = N8N_BASE + map_path(path, parsed.query)

        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length > 0 else None

        headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_BY_HOP:
                continue
            headers[key] = value

        apply_upstream_auth(headers)

        req = Request(target_url, data=body, headers=headers, method=self.command)

        try:
            with urlopen(req, timeout=TIMEOUT) as upstream:
                data = upstream.read()
                self.send_response(upstream.status)
                self.add_cors()
                for key, value in upstream.headers.items():
                    lower = key.lower()
                    if lower.startswith("access-control-"):
                        continue
                    if lower in HOP_BY_HOP:
                        continue
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)

        except HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.add_cors()
            for key, value in e.headers.items():
                lower = key.lower()
                if lower.startswith("access-control-"):
                    continue
                if lower in HOP_BY_HOP:
                    continue
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)

        except URLError as e:
            self.send_json(502, {
                "error": "n8n proxy error",
                "message": str(e.reason if hasattr(e, "reason") else e),
                "n8nBase": N8N_BASE,
                "target": target_url,
            })

        except Exception as e:
            self.send_json(500, {
                "error": "proxy internal error",
                "message": str(e),
                "traceback": traceback.format_exc(),
            })

def main():
    print("n8n proxy started")
    print(f"Proxy: http://localhost:{PORT}")
    print(f"n8n:   {N8N_BASE}")
    print("")
    print("Auth forwarding:")
    print("  Basic Auth:", "ON" if (N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD) else "OFF")
    print("  API key:   ", "ON" if N8N_API_KEY else "OFF")
    print("  Cookie:    ", "ON" if N8N_COOKIE else "OFF")
    print("")
    print(f"Health check: http://localhost:{PORT}/n8n-healthz")
    print("")
    print("Do not close this window while using the web page.")
    print("")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()

if __name__ == "__main__":
    try:
        main()
    except OSError as e:
        print("")
        print("PROXY FAILED")
        print(str(e))
        if "10048" in str(e) or "Address already in use" in str(e):
            print("")
            print(f"Port {PORT} is already in use.")
            print("Close another proxy window or change PROXY_PORT.")
        input("\nPress Enter to close...")
        raise
