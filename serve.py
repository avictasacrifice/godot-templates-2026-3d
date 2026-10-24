import http.server
import socketserver
import sys

PORT = 8060

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Access-Control-Allow-Origin", "*")
        # Отключаем кешш
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):
        # Тихий лог не спешп
        pass

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Сервер запущенн: http://localhost:{PORT}")
    print("Чтобы остановить  закройте это окно.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")
        sys.exit(0)