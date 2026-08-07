#!/usr/bin/env python3
"""
Whisperflow Bridge — One-command launcher.

Starts the bridge HTTP server and the floating overlay.
The overlay polls the server for status and appears near text fields.

Usage:
    python3 launch.py                            # server + overlay
    python3 launch.py --port 9877                # custom port
    python3 launch.py --token SECRET             # shared secret for remote (Tailscale)
    python3 launch.py --no-overlay               # server only
    python3 launch.py --no-sound                 # disable chime
    python3 launch.py --install-login            # install as login item (runs at boot)
    python3 launch.py --uninstall-login          # remove the login item
    python3 launch.py --print-plist              # print the LaunchAgent plist
"""

import argparse
import os
import plistlib
import signal
import subprocess
import sys
import threading
import time
from xml.sax.saxutils import escape as xml_escape

# Prepend our directory so we can import server
MAC_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, MAC_DIR)
import server  # noqa: E402

OVERLAY_PY = os.path.join(MAC_DIR, "overlay.py")
SYSTEM_PYTHON = "/usr/bin/python3"

LABEL = "com.whisperbridge.launcher"
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
LOG_PATH = os.path.expanduser("~/Library/Logs/whisperbridge.log")


# ── Login item (LaunchAgent) ────────────────────────────────────────────────

def migrate_legacy_login_token() -> bool:
    """Move a token from an older plist into the protected token file."""
    try:
        with open(PLIST_PATH, "rb") as fh:
            args = plistlib.load(fh).get("ProgramArguments", [])
        index = args.index("--token")
        token = args[index + 1].strip()
    except (OSError, ValueError, IndexError, AttributeError, plistlib.InvalidFileException):
        return False
    if not token:
        return False
    server.persist_token(token)
    return True


def build_plist(port: int, token: str | None,
                no_sound: bool = False, sound_name: str | None = None,
                no_overlay: bool = False, log_content: bool = False,
                allow_hosts: list[str] | None = None) -> str:
    """Build a LaunchAgent plist that keeps the bridge alive across reboots."""
    args = [sys.executable, os.path.abspath(__file__), "--port", str(port)]
    # Token is resolved from TOKEN_FILE at startup, never in ProgramArguments
    if no_sound:
        args += ["--no-sound"]
    if sound_name:
        args += ["--sound", sound_name]
    if no_overlay:
        args += ["--no-overlay"]
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
        '  <key>ThrottleInterval</key><integer>5</integer>\n'
        f'  <key>StandardOutPath</key><string>{LOG_PATH}</string>\n'
        f'  <key>StandardErrorPath</key><string>{LOG_PATH}</string>\n'
        # Environment: ensure PATH includes brew so accessibility works
        '  <key>EnvironmentVariables</key><dict>\n'
        '    <key>PATH</key>'
        f'<string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>\n'
        '  </dict>\n'
        '</dict></plist>\n'
    )


def install_login(port: int, token: str | None,
                  no_sound: bool = False, sound_name: str | None = None,
                  no_overlay: bool = False, log_content: bool = False,
                  allow_hosts: list[str] | None = None) -> None:
    """Install a LaunchAgent that starts the bridge at login."""
    os.makedirs(os.path.dirname(PLIST_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(PLIST_PATH, "w", encoding="utf-8") as fh:
        fh.write(build_plist(port, token, no_sound, sound_name, no_overlay, log_content, allow_hosts))
    os.chmod(PLIST_PATH, 0o600)
    # Pre-create log at 0600 so launchd inherits restrictive permissions
    fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.close(fd)
    # Validate plist syntax
    subprocess.run(["plutil", "-lint", PLIST_PATH], check=False)
    # Unload old instance, then load new
    subprocess.run(["launchctl", "unload", PLIST_PATH],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    res = subprocess.run(["launchctl", "load", "-w", PLIST_PATH],
                         capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  ✗ launchctl load failed: {res.stderr.strip()}")
        sys.exit(1)
    print(f"  ✓ Login item installed: {PLIST_PATH}")
    print(f"    Python: {sys.executable}")
    print(f"    Port:   {port}")
    print(f"    Token:  {'set' if token else 'none'}")
    print(f"    Logs:   {LOG_PATH}")
    print(f"    The bridge will start automatically on next login.")


def uninstall_login() -> None:
    """Remove the LaunchAgent."""
    subprocess.run(["launchctl", "unload", PLIST_PATH],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.remove(PLIST_PATH)
        print(f"  ✓ Login item removed: {PLIST_PATH}")
    except FileNotFoundError:
        print("  (no login item installed)")


# ── Overlay ─────────────────────────────────────────────────────────────────

def start_overlay(port: int) -> subprocess.Popen | None:
    """Launch the overlay as a subprocess using system Python (has tkinter)."""
    if not os.path.exists(OVERLAY_PY):
        print("  ⚠ overlay.py not found — skipping overlay")
        return None
    if not os.path.exists(SYSTEM_PYTHON):
        print("  ⚠ /usr/bin/python3 not available — skipping overlay")
        return None

    try:
        proc = subprocess.Popen(
            [SYSTEM_PYTHON, OVERLAY_PY, "--port", str(port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(f"  ✓ Overlay started (pid {proc.pid})")
        return proc
    except Exception as exc:
        print(f"  ✗ Overlay failed: {exc}")
        return None


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Whisperflow Bridge — Launcher")
    ap.add_argument("--port", type=int, default=server.DEFAULT_PORT)
    ap.add_argument("--token", default=None)
    ap.add_argument("--clipboard-only", action="store_true")
    ap.add_argument("--log-content", action="store_true", help="Log dictation text to stdout (off by default).")
    ap.add_argument("--allow-host", action="append", default=[], help="Additional hostname for Host header validation.")
    ap.add_argument("--sound", default=None)
    ap.add_argument("--no-sound", action="store_true")
    ap.add_argument("--no-overlay", action="store_true")
    ap.add_argument("--install-login", action="store_true",
                    help="Install a LaunchAgent that starts the bridge at login")
    ap.add_argument("--uninstall-login", action="store_true",
                    help="Remove the login item")
    ap.add_argument("--print-plist", action="store_true",
                    help="Print the LaunchAgent plist to stdout (no side effects)")
    a = ap.parse_args()

    if a.install_login and a.token is None and migrate_legacy_login_token():
        print("  ✓ Migrated legacy login token to the protected token file")
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
    if a.clipboard_only:
        server.BridgeHandler.default_mode = "clipboard"

    # Handle login-item commands
    if a.print_plist:
        sys.stdout.write(build_plist(a.port, token, no_sound, sound_name, a.no_overlay, a.log_content, a.allow_host))
        return
    if a.install_login:
        install_login(a.port, token, no_sound, sound_name, a.no_overlay, a.log_content, a.allow_host)
        return
    if a.uninstall_login:
        uninstall_login()
        return

    server.AUTH_TOKEN = server.resolve_token(a.token)
    server.configure_allowed_hosts(a.allow_host)
    server.start_allowed_hosts_refresher()

    # Start HTTP server
    try:
        httpd = server.BridgeServer(("0.0.0.0", a.port), server.BridgeHandler)
    except OSError as exc:
        print(f"  ✗ Cannot bind :{a.port} — {exc}")
        sys.exit(1)

    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()

    lan = server.get_lan_ip()
    tail = server.get_tail_ip()

    print(f"""
  ╔══════════════════════════════════════════════╗
  ║       Whisper Flow Bridge — Running          ║
  ╠══════════════════════════════════════════════╣
  ║  Port     :{a.port:<32}║
  ║  Auth     : token (remote-safe)                       ║
  ║  LAN      : http://{lan}:{a.port:<24}║
  ║  Tailscale: {f"http://{tail}:{a.port}" if tail else "not connected":<35}║
  ║  Console  : http://localhost:{a.port:<24}║
  ╚══════════════════════════════════════════════╝
""")

    # Start overlay
    overlay_proc = None
    if not a.no_overlay:
        overlay_proc = start_overlay(a.port)

    print("  Waiting for text from Android… (Ctrl-C to stop)\n")

    def cleanup(*_):
        print("\n  Stopping…")
        if overlay_proc and overlay_proc.poll() is None:
            overlay_proc.terminate()
            overlay_proc.wait(timeout=2)
        httpd.shutdown()
        httpd.server_close()
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        cleanup()


if __name__ == "__main__":
    main()
