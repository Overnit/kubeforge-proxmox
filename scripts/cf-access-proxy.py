#!/usr/bin/env python3
"""Local HTTPS reverse proxy that injects Cloudflare Access headers."""

import http.server
import ssl
import urllib.request
import os
import sys
import tempfile

UPSTREAM = os.environ.get("UPSTREAM_URL", "https://proxmox.overnit.com")
CF_CLIENT_ID = os.environ["CF_ACCESS_CLIENT_ID"]
CF_CLIENT_SECRET = os.environ["CF_ACCESS_CLIENT_SECRET"]
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "18006"))


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_request(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else None

        url = f"{UPSTREAM}{self.path}"
        req = urllib.request.Request(url, data=body, method=self.command)

        # Forward original headers
        for key, value in self.headers.items():
            if key.lower() not in ("host", "connection"):
                req.add_header(key, value)

        # Inject CF Access headers
        req.add_header("CF-Access-Client-Id", CF_CLIENT_ID)
        req.add_header("CF-Access-Client-Secret", CF_CLIENT_SECRET)

        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            with urllib.request.urlopen(req, context=ctx, timeout=300) as resp:
                self.send_response(resp.status)
                for key, value in resp.getheaders():
                    if key.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(key, value)
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for key, value in e.headers.items():
                if key.lower() not in ("transfer-encoding", "connection"):
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

    do_GET = do_request
    do_POST = do_request
    do_PUT = do_request
    do_DELETE = do_request

    def log_message(self, format, *args):
        sys.stderr.write(f"[proxy] {args[0]}\n")


def generate_self_signed_cert():
    """Generate a temporary self-signed cert for the local proxy."""
    import subprocess
    cert_file = os.path.join(tempfile.gettempdir(), "proxy-cert.pem")
    key_file = os.path.join(tempfile.gettempdir(), "proxy-key.pem")
    if not os.path.exists(cert_file):
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", key_file, "-out", cert_file,
            "-days", "365", "-nodes",
            "-subj", "/CN=localhost"
        ], check=True, capture_output=True)
    return cert_file, key_file


if __name__ == "__main__":
    cert_file, key_file = generate_self_signed_cert()

    server = http.server.HTTPServer(("127.0.0.1", LISTEN_PORT), ProxyHandler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert_file, key_file)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)

    print(f"CF Access proxy listening on https://localhost:{LISTEN_PORT} → {UPSTREAM}")
    server.serve_forever()
