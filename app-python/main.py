import http.server
import socketserver


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"hello, hardened (python)\n")


def main():
    with socketserver.TCPServer(("", 8080), H) as s:
        print("listening on :8080")
        s.serve_forever()


if __name__ == "__main__":
    main()
