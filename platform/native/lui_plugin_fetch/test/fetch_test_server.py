#!/usr/bin/env python3
"""Minimal loopback HTTP server for the lui_plugin_fetch test.

Endpoints:
  /echo            echoes method, path, headers and body back as JSON
  /get             fixed plain-text body
  /redirect        302 -> /get
  /redirect_chain  302 -> /redirect
  /status/<n>      empty body with status <n>
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _echo(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        payload = json.dumps(
            {
                "method": self.command,
                "path": self.path,
                "headers": [[k, v] for k, v in self.headers.items()],
                "body": body.decode("latin-1"),
            }
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Test-Server", "lui-fetch-test")
        self.end_headers()
        self.wfile.write(payload)

    def _fixed(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Test-Server", "lui-fetch-test")
        self.end_headers()
        self.wfile.write(body)

    def _route(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/get")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/redirect_chain":
            self.send_response(302)
            self.send_header("Location", "/redirect")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/get":
            self._fixed(b"lui fetch test body\n")
        elif self.path.startswith("/status/"):
            code = int(self.path.rsplit("/", 1)[1])
            self.send_response(code)
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self._echo()

    do_GET = _route
    do_POST = _route
    do_PUT = _route
    do_DELETE = _route

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
