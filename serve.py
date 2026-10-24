import http.server
import mimetypes
import os
import sys
import threading
import webbrowser

PORT = 8060
ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)  # раздаём папку, в которой лежит serve.py

# На Windows типы берутся из реестра - подстрахуемся
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):
        pass  # тихий лог


class Server(http.server.ThreadingHTTPServer):
    # На Windows SO_REUSEADDR позволяет занять уже занятый порт - отключаем
    allow_reuse_address = False
    daemon_threads = True


def main():
    if not os.path.exists(os.path.join(ROOT, "index.html")):
        print("ОШИБКА: рядом с serve.py нет index.html.")
        print("Положите serve.py и start_web.bat в папку с веб-билдом (build/web).")
        input("Нажмите Enter для выхода...")
        sys.exit(1)

    try:
        httpd = Server(("", PORT), Handler)
    except OSError as e:
        print(f"ОШИБКА: не удалось занять порт {PORT}: {e}")
        print("Скорее всего, сервер уже запущен в другом окне. Закройте его и повторите.")
        input("Нажмите Enter для выхода...")
        sys.exit(1)

    url = f"http://localhost:{PORT}"
    print(f"Сервер запущен: {url}")
    print("Чтобы остановить, закройте это окно (или Ctrl+C).")
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")


if __name__ == "__main__":
    main()
