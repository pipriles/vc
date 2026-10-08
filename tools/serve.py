#!/usr/bin/env python3
"""Dev server for build/ with caching disabled, so rebuilds always reload.

Usage: python3 -I tools/serve.py [port]
"""
import functools
import http.server
import os
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
handler = functools.partial(NoCacheHandler, directory=root)
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
