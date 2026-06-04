#!/usr/bin/env python3
# Spec 037 — hermetic mock model endpoint for the native smoke harness.
#
# Serves the minimal Ollama API surface the app touches (contract B):
#   GET  /api/tags     -> model listing reporting gemma3:4b present
#                         (app reaches the ready state, wizard skipped)
#   POST /api/generate -> one canned Swedish response, done:true
#                         (client sends stream:false and parses one object)
#   anything else      -> 404 (the suite fails loudly on unmocked routes)
#
# stdlib only — no dependencies. Binds an ephemeral port by default and
# prints "PORT <n>" on stdout so the runner can capture it; --port pins it.

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CANNED_RESPONSE = "NATIV-SMOKE: sammanfattning klar."


class MockOllamaHandler(BaseHTTPRequestHandler):
    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler API)
        if self.path == "/api/tags":
            self._send_json({"models": [{"name": "gemma3:4b"}]})
        else:
            self._send_json({"error": f"unmocked route {self.path}"}, 404)

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        _ = self.rfile.read(length)  # drain; content is irrelevant to the mock
        if self.path == "/api/generate":
            self._send_json(
                {"model": "gemma3:4b", "response": CANNED_RESPONSE, "done": True}
            )
        else:
            self._send_json({"error": f"unmocked route {self.path}"}, 404)

    def log_message(self, fmt, *args):  # quiet: the runner owns the narrative
        print(f"[mock-ollama] {fmt % args}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description="JuraDrop native-smoke mock endpoint")
    parser.add_argument("--port", type=int, default=0, help="0 = ephemeral")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), MockOllamaHandler)
    print(f"PORT {server.server_address[1]}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
