#!/usr/bin/env python3
"""Local redirecting release server for deterministic installer tests."""

import argparse
import http.server
import pathlib
import re
import urllib.parse


class ReleaseFixtureHandler(http.server.SimpleHTTPRequestHandler):
    root: pathlib.Path

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        path = urllib.parse.urlsplit(self.path).path
        latest = re.fullmatch(
            r"/(?P<case>good|bad)/releases/latest/download/(?P<asset>[^/]+)",
            path,
        )
        if latest:
            # Only SHA256SUMS may resolve through latest. Any installer request
            # through the mutable alias fails, proving clients reuse the tag.
            if latest.group("asset") != "SHA256SUMS":
                self.send_error(409, "installer must use the resolved release tag")
                return
            host = self.headers.get("Host", "127.0.0.1")
            location = (
                f"http://{host}/{latest.group('case')}"
                f"/releases/download/v1.2.3/SHA256SUMS"
            )
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        pinned = re.fullmatch(
            r"/(?P<case>good|bad)/releases/download/v1\.2\.3/(?P<asset>[^/]+)",
            path,
        )
        if not pinned:
            self.send_error(404)
            return

        target = (self.root / pinned.group("case") / pinned.group("asset")).resolve()
        case_root = (self.root / pinned.group("case")).resolve()
        if target.parent != case_root or not target.is_file():
            self.send_error(404)
            return

        data = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    ReleaseFixtureHandler.root = args.root
    server = http.server.ThreadingHTTPServer(("0.0.0.0", args.port), ReleaseFixtureHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
