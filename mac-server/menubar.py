#!/usr/bin/env python3
"""
Whisper Flow Bridge — menu-bar companion (macOS).

Runs the bridge server in the background and shows a status item in the menu
bar with live LAN / Tailscale addresses, the last dictation, and quick actions
(open console, copy pairing link). Optionally installs itself as a login item.

The server engine (server.py) stays dependency-free; this wrapper needs `rumps`
for the menu bar (pip3 install rumps). If rumps is missing it falls back to
running the server headless so a login launch still works — just without the icon.

Usage:
    python3 menubar.py                       # menu bar + server (needs rumps)
    python3 menubar.py --token SECRET        # require a shared secret (remote-safe)
    python3 menubar.py --install-login       # launch at login (RunAtLoad)
    python3 menubar.py --uninstall-login     # remove the login item
    python3 menubar.py --print-plist         # print the LaunchAgent plist (no side effects)
"""

import argparse
import os
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from xml.sax.saxutils import escape as xml_escape

# Import the zero-dependency server engine that lives next to this file.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server  # noqa: E402

def status_dot(bound: bool, tail_ip) -> str:
    """Menu-bar glyph: 🟢 ready incl. Tailscale · 🟡 LAN only · 🔴 not listening."""
    if not bound:
        return "🔴"
    return "🟢" if tail_ip else "🟡"

LABEL = "com.whisperbridge.menubar"
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
LOG_PATH = os.path.expanduser("~/Library/Logs/whisperbridge-menubar.log")


# ── Login item (LaunchAgent) ────────────────────────────────────────────────

def build_plist(port: int, token: str | None,
                no_sound: bool = False, sound_name: str | None = None,
                log_content: bool = False, allow_hosts: list[str] | None = None) -> str:
    args = [sys.executable, os.path.abspath(__file__), "--port", str(port)]
    # Token is resolved from TOKEN_FILE at startup, never in ProgramArguments
    if no_sound:
        args += ["--no-sound"]
    if sound_name:
        args += ["--sound", sound_name]
    if log_content:
        args += ["--log-content"]
    if allow_hosts:
        for h in allow_hosts:
            args += ["--allow-host", h]
    items = "".join(f"    <string>{xml_escape(a)}</string>\n" for a in args)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>\n'
        f'  <key>Label</key><string>{LABEL}</string>\n'
        '  <key>ProgramArguments</key><array>\n'
        f'{items}'
        '  </array>\n'
        '  <key>RunAtLoad</key><true/>\n'
        '  <key>KeepAlive</key><true/>\n'
        '  <key>ProcessType</key><string>Interactive</string>\n'
        f'  <key>StandardOutPath</key><string>{LOG_PATH}</string>\n'
        f'  <key>StandardErrorPath</key><string>{LOG_PATH}</string>\n'
        '</dict></plist>\n'
    )


def install_login(port: int, token: str | None,
                  no_sound: bool = False, sound_name: str | None = None,
                  log_content: bool = False, allow_hosts: list[str] | None = None) -> None:
    os.makedirs(os.path.dirname(PLIST_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(PLIST_PATH, "w", encoding="utf-8") as fh:
        fh.write(build_plist(port, token, no_sound, sound_name, log_content, allow_hosts))
    os.chmod(PLIST_PATH, 0o600)
    # Pre-create log at 0600 so launchd inherits restrictive permissions
    fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.close(fd)
    subprocess.run(["plutil", "-lint", PLIST_PATH], check=False)
    subprocess.run(["launchctl", "unload", PLIST_PATH],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    res = subprocess.run(["launchctl", "load", "-w", PLIST_PATH],
                         capture_output=True, text=True)
    if res.returncode != 0:
        print("  ✗ launchctl load failed:", res.stderr.strip())
    print(f"  ✓ Installed login item → {PLIST_PATH}")



def uninstall_login() -> None:
    subprocess.run(["launchctl", "unload", PLIST_PATH],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.remove(PLIST_PATH)
        print(f"  ✓ Removed login item → {PLIST_PATH}")
    except FileNotFoundError:
        print("  (no login item installed)")


# ── Server start (shared by GUI + headless) ─────────────────────────────────

def start_server(port: int, token: str | None, clipboard_only: bool):
    """Bind the HTTP server. Returns the HTTPServer or None if the port is busy."""
    server.AUTH_TOKEN = token
    if clipboard_only:
        server.BridgeHandler.default_mode = "clipboard"
    try:
        httpd = server.BridgeServer(("0.0.0.0", port), server.BridgeHandler)
    except OSError as exc:
        print(f"  ✗ Could not bind :{port} ({exc}). Is the bridge already running?")
        return None
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


# ── Menu bar (rumps) ────────────────────────────────────────────────────────

def run_gui(port: int, httpd) -> None:
    try:
        import rumps
    except ImportError:
        print("  rumps not installed — running headless (no menu bar).")
        print("  For the menu bar: pip3 install rumps")
        run_headless(port, httpd)
        return

    # Menu-bar only: no Dock icon, no Cmd-Tab entry.
    try:
        from AppKit import NSApplication
        NSApplication.sharedApplication().setActivationPolicy_(2)  # accessory
    except Exception:
        pass

    def copy(text: str):
        try:
            subprocess.run(["pbcopy"], input=text.encode(), check=True)
            return True
        except Exception:
            return False

    def pair_link():
        host = server.get_tail_ip() or server.get_lan_ip()
        p = f"whisperbridge://pair?host={urllib.parse.quote(host)}&port={port}"
        if server.AUTH_TOKEN:
            p += f"&token={urllib.parse.quote(server.AUTH_TOKEN)}"
        return p, host

    class BridgeApp(rumps.App):
        def __init__(self):
            super().__init__("🎙", quit_button=None)
            self.title = status_dot(bool(httpd), server.get_tail_ip()) + "🎙"
            self.header = rumps.MenuItem(
                "Whisper Bridge — running" if httpd else "Whisper Bridge — port busy",
                callback=None)
            self.lan = rumps.MenuItem("LAN: …", callback=self.on_lan)
            self.tail = rumps.MenuItem("Tailscale: …", callback=self.on_tail)
            self.tok = rumps.MenuItem("Token: …", callback=None)
            self.last = rumps.MenuItem("Last: —", callback=None)
            self.menu = [
                self.header, self.lan, self.tail, self.tok, rumps.separator,
                self.last, rumps.separator,
                rumps.MenuItem("Open console", callback=self.on_open),
                rumps.MenuItem("Copy pairing link", callback=self.on_pair),
                rumps.separator,
                rumps.MenuItem("Quit Whisper Bridge", callback=self.on_quit),
            ]

        def on_lan(self, _):
            if copy(f"{server.get_lan_ip()}:{port}"):
                rumps.notification("Whisper Bridge", "LAN address copied", "")

        def on_tail(self, _):
            t = server.get_tail_ip()
            if t and copy(f"{t}:{port}"):
                rumps.notification("Whisper Bridge", "Tailscale address copied", "")

        def on_open(self, _):
            tok = server.AUTH_TOKEN
            url = f"http://localhost:{port}"
            if tok:
                url += f"/?token={urllib.parse.quote(tok)}"
            webbrowser.open(url)

        def on_pair(self, _):
            p, host = pair_link()
            if copy(p):
                rumps.notification("Whisper Bridge", "Pairing link copied", host)

        def on_quit(self, _):
            rumps.quit_application()

        @rumps.timer(3)
        def refresh(self, _):
            try:
                lan = server.get_lan_ip()
                tail = server.get_tail_ip()
                self.lan.title = f"LAN: {lan}:{port}  ⧉"
                self.tail.title = (f"Tailscale: {tail}:{port}  ⧉" if tail
                                   else "Tailscale: not connected")
                self.tok.title = "Token: set · remote-safe"
                st = server.STATUS
                if st["count"]:
                    self.last.title = f"Last ({st['count']}): {st['last_preview'] or '—'}"
                else:
                    self.last.title = "Last: —"
                self.title = status_dot(bool(httpd), tail) + "🎙"
                self.header.title = (
                    "Whisper Bridge — ready (LAN + Tailscale)" if (httpd and tail)
                    else "Whisper Bridge — ready (LAN only)" if httpd
                    else "Whisper Bridge — port busy")
            except Exception:
                pass

    app = BridgeApp()
    rumps.notification("Whisper Bridge", "Running in the menu bar",
                       f":{port}" + (" · token on" if server.AUTH_TOKEN else ""))
    app.run()


def run_headless(port: int, httpd) -> None:
    if httpd is None:
        sys.exit(1)
    print(f"  Whisper Bridge headless on 0.0.0.0:{port} "
          f"(token {'set' if server.AUTH_TOKEN else 'none'})")
    print("  Waiting for text from Android… (Ctrl-C to stop)\n")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("\n  Stopped.")


# ── Entry point ─────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="Whisper Flow Bridge — menu bar")
    ap.add_argument("--port", type=int, default=server.DEFAULT_PORT)
    ap.add_argument("--token", default=None,
                    help="Override the shared secret (falls back to env, ~/.config/whisperbridge/token, or auto-generate).")
    ap.add_argument("--clipboard-only", action="store_true")
    ap.add_argument("--log-content", action="store_true", help="Log dictation text to stdout (off by default).")
    ap.add_argument("--allow-host", action="append", default=[], help="Additional hostname for Host header validation.")
    ap.add_argument("--sound", default=None, help="Dictation chime sound name (default: Tink).")
    ap.add_argument("--no-sound", action="store_true", help="Disable the dictation chime.")
    ap.add_argument("--install-login", action="store_true",
                    help="Install a LaunchAgent that runs this at login.")
    ap.add_argument("--uninstall-login", action="store_true")
    ap.add_argument("--print-plist", action="store_true",
                    help="Print the LaunchAgent plist to stdout (no side effects).")
    a = ap.parse_args()

    token = server.resolve_token(a.token)
    no_sound = a.no_sound or os.environ.get("WHISPERFLOW_NO_SOUND") == "1"
    sound_name = a.sound or os.environ.get("WHISPERFLOW_SOUND")
    server.SOUND_ENABLED = not no_sound
    if sound_name:
        server.SOUND_NAME = sound_name
    server.LOG_CONTENT = a.log_content
    for h in a.allow_hosts:
        if h:
            server.ALLOWED_HOSTS.add(h.lower())

    if a.print_plist:
        sys.stdout.write(build_plist(a.port, token, no_sound, sound_name, a.log_content, a.allow_hosts))
        return
    if a.install_login:
        install_login(a.port, token, no_sound, sound_name, a.log_content, a.allow_hosts)
        return
    if a.uninstall_login:
        uninstall_login()
        return

    httpd = start_server(a.port, token, a.clipboard_only)
    run_gui(a.port, httpd)


if __name__ == "__main__":
    main()
