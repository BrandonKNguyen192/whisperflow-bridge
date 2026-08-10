#!/usr/bin/env python3
"""
Whisper Flow Bridge — menu-bar companion (macOS).

Runs the bridge server in the background and shows a status item in the menu
bar with live LAN / Tailscale addresses, the last dictation, and quick actions
(open console, copy pairing link), plus one-click Start / Stop for the bridge
and a Launch-at-login toggle. Optionally installs itself as a login item or as
a double-clickable app in ~/Applications.

The server engine (server.py) stays dependency-free; this wrapper needs `rumps`
for the menu bar (pip3 install rumps). If rumps is missing it falls back to
running the server headless so a login launch still works — just without the icon.

Usage:
    python3 menubar.py                       # menu bar + server (needs rumps)
    python3 menubar.py --token SECRET        # require a shared secret (remote-safe)
    python3 menubar.py --install-login       # launch at login (RunAtLoad)
    python3 menubar.py --uninstall-login     # remove the login item
    python3 menubar.py --install-app         # build ~/Applications/Whisper Bridge.app
    python3 menubar.py --remove-app          # remove the menu-bar app
    python3 menubar.py --print-plist         # print the LaunchAgent plist (no side effects)
"""

import argparse
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from xml.sax.saxutils import escape as xml_escape

# Import the zero-dependency shared receiver protocol.
MAC_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(MAC_DIR)
sys.path.insert(0, ROOT_DIR)
from common import bridge_server as server  # noqa: E402

LABEL = "com.whisperbridge.menubar"
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
LOG_PATH = os.path.expanduser("~/Library/Logs/whisperbridge-menubar.log")
LEGACY_LABEL = "com.whisperbridge.launcher"
LEGACY_PLIST = os.path.expanduser(f"~/Library/LaunchAgents/{LEGACY_LABEL}.plist")
INSTALL_DIR = os.path.expanduser("~/Library/Application Support/WhisperBridge")
APP_DIR = os.path.expanduser("~/Applications/Whisper Bridge.app")
APP_EXEC = "whisper-bridge-menubar"
GUI_LOG_PATH = os.path.expanduser("~/Library/Logs/whisperbridge-menubar.log")
LOCK_PATH = os.path.join(INSTALL_DIR, "menubar.lock")

_LOCK_HANDLE = None


def _redirect_to_log() -> None:
    """Finder-launched apps have no console; keep a log so failures are visible."""
    if sys.stdout.isatty():
        return
    os.makedirs(os.path.dirname(GUI_LOG_PATH), exist_ok=True)
    fh = open(GUI_LOG_PATH, "a", encoding="utf-8")
    sys.stdout = fh
    sys.stderr = fh


# ── Login item (LaunchAgent) ────────────────────────────────────────────────

def build_plist(port: int, token: str | None,
                no_sound: bool = False, sound_name: str | None = None,
                log_content: bool = False, allow_hosts: list[str] | None = None,
                python_bin: str | None = None, script_path: str | None = None) -> str:
    py = python_bin or sys.executable
    script = script_path or os.path.abspath(__file__)
    args = [py, script, "--port", str(port)]
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
        '  <key>EnvironmentVariables</key><dict>\n'
        '    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>\n'
        '  </dict>\n'
        f'  <key>StandardOutPath</key><string>{LOG_PATH}</string>\n'
        f'  <key>StandardErrorPath</key><string>{LOG_PATH}</string>\n'
        '</dict></plist>\n'
    )


def install_login(port: int, token: str | None,
                  no_sound: bool = False, sound_name: str | None = None,
                  log_content: bool = False, allow_hosts: list[str] | None = None,
                  python_bin: str | None = None, script_path: str | None = None) -> None:
    os.makedirs(os.path.dirname(PLIST_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(PLIST_PATH, "w", encoding="utf-8") as fh:
        fh.write(build_plist(port, token, no_sound, sound_name, log_content,
                             allow_hosts, python_bin, script_path))
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


def login_installed() -> bool:
    return os.path.exists(PLIST_PATH)


def uninstall_legacy_login() -> None:
    """Retire the old launch.py login item so it stops competing for the port."""
    if not os.path.exists(LEGACY_PLIST):
        return
    subprocess.run(["launchctl", "unload", LEGACY_PLIST],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.remove(LEGACY_PLIST)
    except OSError:
        pass
    print(f"  ✓ Retired legacy login item → {LEGACY_PLIST}")


def acquire_lock() -> bool:
    """Single-instance guard: only one menu bar icon at a time."""
    import fcntl
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    try:
        fh = open(LOCK_PATH, "w", encoding="utf-8")
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fh.seek(0)
        fh.truncate()
        fh.write(str(os.getpid()))
        fh.flush()
    except OSError:
        return False
    global _LOCK_HANDLE
    _LOCK_HANDLE = fh
    return True


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


# ── Mutable server state (Start / Stop from the menu) ───────────────────────

class ServerState:
    """Owns the HTTP server so the menu bar can start and stop it repeatedly."""

    def __init__(self, port: int, token: str | None, clipboard_only: bool):
        self.port = port
        self.token = token
        self.clipboard_only = clipboard_only
        self.httpd = None

    def is_running(self) -> bool:
        return self.httpd is not None

    def start(self) -> bool:
        if self.is_running():
            return True
        httpd = start_server(self.port, self.token, self.clipboard_only)
        if httpd is None:
            return False
        self.httpd = httpd
        return True

    def stop(self) -> None:
        httpd = self.httpd
        if httpd is None:
            return
        self.httpd = None
        try:
            httpd.shutdown()
        finally:
            httpd.server_close()


# ── Menu-bar app bundle ─────────────────────────────────────────────────────

def _menubar_icon_path() -> str | None:
    """Template mic glyph shipped with the repo/install; None falls back to text."""
    candidates = [
        os.path.join(ROOT_DIR, "branding", "menubar-icon.png"),
        os.path.join(INSTALL_DIR, "branding", "menubar-icon.png"),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def _build_icon(app_dir: str) -> bool:
    """Render branding/icon-1024.png into AppIcon.icns for the app bundle."""
    src = os.path.join(ROOT_DIR, "branding", "icon-1024.png")
    if not os.path.exists(src):
        return False
    import tempfile
    work = tempfile.mkdtemp(prefix="whisperbridge-icon-")
    iconset = os.path.join(work, "AppIcon.iconset")
    os.makedirs(iconset)
    try:
        for size in (16, 32, 128, 256, 512):
            name = f"icon_{size}x{size}.png"
            subprocess.run(["sips", "-z", str(size), str(size), src, "--out",
                            os.path.join(iconset, name)],
                           check=True, capture_output=True)
            subprocess.run(["sips", "-z", str(size * 2), str(size * 2), src, "--out",
                            os.path.join(iconset, f"icon_{size}x{size}@2x.png")],
                           check=True, capture_output=True)
        resources = os.path.join(app_dir, "Contents", "Resources")
        os.makedirs(resources, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset,
                        "-o", os.path.join(resources, "AppIcon.icns")],
                       check=True, capture_output=True)
        return True
    except Exception as exc:
        print(f"  (icon skipped: {exc})")
        return False
    finally:
        shutil.rmtree(work, ignore_errors=True)


def install_app() -> None:
    """Copy the receiver, provision a rumps venv, build the app, and register login startup."""
    app_version = ""
    try:
        app_version = open(os.path.join(ROOT_DIR, "VERSION"), encoding="utf-8").read().strip()
    except OSError:
        pass
    version = app_version or "1.0"

    os.makedirs(INSTALL_DIR, exist_ok=True)
    if ROOT_DIR != INSTALL_DIR:
        subprocess.run(["ditto", os.path.join(ROOT_DIR, "common"),
                        os.path.join(INSTALL_DIR, "common")], check=True)
        subprocess.run(["ditto", os.path.join(ROOT_DIR, "mac-server"),
                        os.path.join(INSTALL_DIR, "mac-server")], check=True)
        subprocess.run(["ditto", os.path.join(ROOT_DIR, "branding"),
                        os.path.join(INSTALL_DIR, "branding")], check=True)
    else:
        print("  Already installed — refreshing the app bundle only.")

    venv_dir = os.path.join(INSTALL_DIR, "menubar-venv")
    venv_py = os.path.join(venv_dir, "bin", "python3")
    if not os.path.exists(venv_py):
        print("  Creating the menu-bar runtime…")
        subprocess.run([sys.executable, "-m", "venv", venv_dir], check=True)
    try:
        subprocess.run([venv_py, "-c", "import rumps"], check=True, capture_output=True)
    except subprocess.CalledProcessError:
        print("  Installing rumps into the menu-bar runtime…")
        subprocess.run([os.path.join(venv_dir, "bin", "pip"), "install", "-q", "rumps"],
                       check=True)

    macos_dir = os.path.join(APP_DIR, "Contents", "MacOS")
    os.makedirs(macos_dir, exist_ok=True)
    launcher = os.path.join(macos_dir, APP_EXEC)
    menu_script = os.path.join(INSTALL_DIR, "mac-server", "menubar.py")
    installed_script = menu_script
    with open(launcher, "w", encoding="utf-8") as fh:
        fh.write("#!/bin/bash\n")
        fh.write(f'exec "{venv_py}" "{menu_script}" "$@"\n')
    os.chmod(launcher, 0o755)

    has_icon = _build_icon(APP_DIR)
    icon_key = '  <key>CFBundleIconFile</key><string>AppIcon</string>\n' if has_icon else ""
    plist = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>\n'
        '  <key>CFBundleName</key><string>Whisper Bridge</string>\n'
        '  <key>CFBundleDisplayName</key><string>Whisper Bridge</string>\n'
        '  <key>CFBundleIdentifier</key><string>com.whisperbridge.menubar</string>\n'
        f'  <key>CFBundleShortVersionString</key><string>{version}</string>\n'
        f'  <key>CFBundleVersion</key><string>{version}</string>\n'
        f'  <key>CFBundleExecutable</key><string>{APP_EXEC}</string>\n'
        '  <key>CFBundlePackageType</key><string>APPL</string>\n'
        '  <key>LSUIElement</key><true/>\n'
        '  <key>NSHighResolutionCapable</key><true/>\n'
        f'{icon_key}'
        '</dict></plist>\n'
    )
    plist_path = os.path.join(APP_DIR, "Contents", "Info.plist")
    with open(plist_path, "w", encoding="utf-8") as fh:
        fh.write(plist)
    subprocess.run(["plutil", "-lint", plist_path], check=True)

    # Retire the old launch.py service, restart from the installed copy, then
    # register the menu bar app as the login item so it starts fresh.
    uninstall_legacy_login()
    subprocess.run(["pkill", "-f",
                    "Application Support/WhisperBridge/mac-server/menubar.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    token = server.resolve_token(None)
    install_login(server.DEFAULT_PORT, token,
                  python_bin=venv_py, script_path=installed_script)

    print(f"  ✓ Installed menu bar app → {APP_DIR}")
    print("  ✓ Launch at login enabled (menu bar icon appears after every login)")
    print("  The menu bar app is starting now — look for the mic icon top-right.")


def remove_app() -> None:
    if os.path.isdir(APP_DIR):
        shutil.rmtree(APP_DIR)
        print(f"  ✓ Removed menu bar app → {APP_DIR}")
    else:
        print("  (no menu bar app installed)")


# ── Menu bar (rumps) ────────────────────────────────────────────────────────

def run_gui(cfg: dict, state: ServerState) -> None:
    port = cfg["port"]
    print(f"[menubar] starting GUI on :{port} "
          f"(python {sys.version.split()[0]}, rumps import pending)", flush=True)
    try:
        import rumps
    except ImportError:
        print("[menubar] rumps not installed — running headless (no menu bar)", flush=True)
        print("  rumps not installed — running headless (no menu bar).")
        print("  For the menu bar: python3 mac-server/menubar.py --install-app")
        run_headless(port, state)
        return
    print("[menubar] rumps ready — showing status item", flush=True)

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
            icon = _menubar_icon_path()
            print(f"[menubar] menu bar icon: {icon or 'none (emoji fallback)'}",
                  flush=True)
            super().__init__(
                "Whisper Bridge",
                title="" if icon else "🎙",
                icon=icon,
                template=True,
                quit_button=None,
            )
            self.header = rumps.MenuItem("Whisper Bridge", callback=None)
            self.toggle = rumps.MenuItem("Start bridge", callback=self.on_toggle)
            self.lan = rumps.MenuItem("LAN: …", callback=self.on_lan)
            self.tail = rumps.MenuItem("Tailscale: …", callback=self.on_tail)
            self.tok = rumps.MenuItem("Token: …", callback=None)
            self.last = rumps.MenuItem("Last: —", callback=None)
            self.login = rumps.MenuItem("Launch at login", callback=self.on_login)
            self.menu = [
                self.header, self.toggle, rumps.separator,
                self.lan, self.tail, self.tok, rumps.separator,
                self.last, rumps.separator,
                rumps.MenuItem("Open console", callback=self.on_open),
                rumps.MenuItem("Copy pairing link", callback=self.on_pair),
                rumps.MenuItem("Refresh status", callback=self.on_refresh),
                rumps.separator,
                self.login, rumps.separator,
                rumps.MenuItem("Quit Whisper Bridge", callback=self.on_quit),
            ]
            self.refresh_ui()

        def refresh_ui(self):
            running = state.is_running()
            tail = server.get_tail_ip()
            if running:
                self.header.title = (
                    "Whisper Bridge — ready (LAN + Tailscale)" if tail
                    else "Whisper Bridge — ready (LAN only)")
            else:
                self.header.title = "Whisper Bridge — stopped"
            self.toggle.title = "Stop bridge" if running else "Start bridge"
            self.login.title = "Launch at login: " + ("On" if login_installed() else "Off")
            if tail:
                self.tail.title = f"Tailscale: {tail}:{port}  ⧉"
            else:
                self.tail.title = "Tailscale: not connected"

        def on_refresh(self, _):
            self.tail.title = "Tailscale: checking…"
            self.lan.title = "LAN: checking…"
            # Force a fresh probe, bypassing the 15s cache.
            tail = server.get_tail_ip(force=True)
            lan = server.get_lan_ip()
            if tail:
                self.tail.title = f"Tailscale: {tail}:{port}  ⧉"
            else:
                self.tail.title = "Tailscale: not connected"
            self.lan.title = f"LAN: {lan}:{port}  ⧉"
            self.refresh_ui()
            rumps.notification(
                "Whisper Bridge", "Status refreshed",
                f"Tailscale: {tail or 'not connected'}  ·  LAN: {lan}")

        def on_toggle(self, _):
            if state.is_running():
                state.stop()
                rumps.notification(
                    "Whisper Bridge", "Bridge stopped",
                    f":{port} is no longer accepting connections")
            else:
                if state.start():
                    rumps.notification(
                        "Whisper Bridge", "Bridge started",
                        f"Listening on :{port}" + (" · token on" if cfg["token"] else ""))
                else:
                    rumps.notification(
                        "Whisper Bridge", "Could not start",
                        f"Port {port} is busy — is the bridge already running?")
            self.refresh_ui()

        def on_login(self, _):
            if login_installed():
                uninstall_login()
            else:
                install_login(port, cfg["token"], cfg["no_sound"], cfg["sound_name"],
                              cfg["log_content"], cfg["allow_hosts"])
            self.refresh_ui()
            rumps.notification(
                "Whisper Bridge", "Launch at login " +
                ("disabled" if not login_installed() else "enabled"), "")

        def on_lan(self, _):
            if copy(f"{server.get_lan_ip()}:{port}"):
                rumps.notification("Whisper Bridge", "LAN address copied", "")

        def on_tail(self, _):
            t = server.get_tail_ip()
            if t and copy(f"{t}:{port}"):
                rumps.notification("Whisper Bridge", "Tailscale address copied", "")

        def on_open(self, _):
            if not state.is_running():
                rumps.notification("Whisper Bridge", "Bridge is stopped",
                                   "Choose Start bridge first.")
                return
            tok = server.AUTH_TOKEN
            url = f"http://localhost:{port}"
            if tok:
                url += f"/?token={urllib.parse.quote(tok)}"
            webbrowser.open(url)

        def on_pair(self, _):
            if not state.is_running():
                rumps.notification("Whisper Bridge", "Bridge is stopped",
                                   "Choose Start bridge first.")
                return
            p, host = pair_link()
            if copy(p):
                rumps.notification("Whisper Bridge", "Pairing link copied", host)

        def on_quit(self, _):
            rumps.quit_application()

        @rumps.timer(3)
        def refresh(self, _):
            try:
                lan = server.get_lan_ip()
                # Cached probe normally; force a fresh one only when the last
                # result was offline so a transient miss recovers on its own.
                tail = server.get_tail_ip(
                    force=self.tail.title == "Tailscale: not connected")
                self.lan.title = f"LAN: {lan}:{port}  ⧉"
                self.tok.title = "Token: set · remote-safe"
                st = server.STATUS
                if st["count"]:
                    self.last.title = f"Last ({st['count']}): {st['last_preview'] or '—'}"
                else:
                    self.last.title = "Last: —"
                self.refresh_ui()
            except Exception:
                pass

    app = BridgeApp()
    if state.is_running():
        rumps.notification("Whisper Bridge", "Running in the menu bar",
                           f":{port}" + (" · token on" if cfg["token"] else ""))
    else:
        rumps.notification("Whisper Bridge", "Bridge is stopped",
                           "Use the menu item to start it.")
    app.run()


def run_headless(port: int, state: ServerState) -> None:
    if not state.is_running():
        sys.exit(1)
    print(f"  Whisper Bridge headless on 0.0.0.0:{port} "
          f"(token {'set' if state.token else 'none'})")
    print("  Waiting for text from Android… (Ctrl-C to stop)\n")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("\n  Stopped.")


# ── Entry point ─────────────────────────────────────────────────────────────

def main() -> None:
    _redirect_to_log()
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
    ap.add_argument("--install-app", action="store_true",
                    help="Build the double-clickable menu-bar app in ~/Applications.")
    ap.add_argument("--remove-app", action="store_true",
                    help="Remove the menu-bar app from ~/Applications.")
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
    for h in a.allow_host:
        if h:
            server.ALLOWED_HOSTS.add(h.lower())

    if a.print_plist:
        sys.stdout.write(build_plist(a.port, token, no_sound, sound_name, a.log_content, a.allow_host))
        return
    if a.install_app:
        install_app()
        return
    if a.remove_app:
        remove_app()
        return
    if a.install_login:
        install_login(a.port, token, no_sound, sound_name, a.log_content, a.allow_host)
        return
    if a.uninstall_login:
        uninstall_login()
        return

    server.configure_allowed_hosts(a.allow_host)
    server.start_allowed_hosts_refresher()
    cfg = {
        "port": a.port,
        "token": token,
        "no_sound": no_sound,
        "sound_name": sound_name,
        "log_content": a.log_content,
        "allow_hosts": a.allow_host,
    }
    if not acquire_lock():
        print("  Whisper Bridge is already running in the menu bar.")
        return
    state = ServerState(a.port, token, a.clipboard_only)
    if not state.start():
        print(f"  ✗ Could not bind :{a.port} — the menu bar will start in the stopped state.")
    run_gui(cfg, state)


if __name__ == "__main__":
    main()
