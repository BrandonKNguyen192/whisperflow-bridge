#!/usr/bin/env python3
"""
Whisperflow Bridge — One-command launcher.

Starts the bridge HTTP server and the floating overlay.
The overlay polls the server for status and appears near text fields.

Usage:
    python3 launch.py                            # server + overlay
    python3 launch.py --port 9877                # custom port
    python3 launch.py --token SECRET             # shared secret for remote
    python3 launch.py --no-overlay               # server only
    python3 launch.py --no-sound                 # disable chime
"""

import argparse
import os
import signal
import subprocess
import sys
import threading
import time

# Prepend our directory so we can import server
MAC_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, MAC_DIR)
import server  # noqa: E402

OVERLAY_PY = os.path.join(MAC_DIR, "overlay.py")
SYSTEM_PYTHON = "/usr/bin/python3"


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


def main():
    ap = argparse.ArgumentParser(description="Whisperflow Bridge — Launcher")
    ap.add_argument("--port", type=int, default=server.DEFAULT_PORT)
    ap.add_argument("--token", default=None)
    ap.add_argument("--clipboard-only", action="store_true")
    ap.add_argument("--sound", default=None)
    ap.add_argument("--no-sound", action="store_true")
    ap.add_argument("--no-overlay", action="store_true")
    a = ap.parse_args()

    token = a.token or os.environ.get("WHISPERFLOW_TOKEN") or None
    no_sound = a.no_sound or os.environ.get("WHISPERFLOW_NO_SOUND") == "1"
    sound_name = a.sound or os.environ.get("WHISPERFLOW_SOUND")
    server.SOUND_ENABLED = not no_sound
    if sound_name:
        server.SOUND_NAME = sound_name
    if a.clipboard_only:
        server.BridgeHandler.default_mode = "clipboard"

    server.AUTH_TOKEN = token

    # Start HTTP server
    try:
        httpd = server.HTTPServer(("0.0.0.0", a.port), server.BridgeHandler)
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
  ║  Auth     : {"token (remote-safe)" if token else "none (LAN ok)":<35}║
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
