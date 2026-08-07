#!/usr/bin/env python3
"""Shared runtime used by the Ubuntu and Windows receiver launchers."""

import signal
import threading

from common import bridge_server


def run_receiver(
    backend,
    target_name: str,
    port: int,
    allow_hosts: list[str] | None = None,
    clipboard_only: bool = False,
    log_content: bool = False,
    sound_enabled: bool = True,
) -> None:
    bridge_server.TARGET_NAME = target_name
    bridge_server.PASTE_SHORTCUT = "Ctrl+V"
    bridge_server.AUTH_TOKEN = bridge_server.resolve_token(None)
    bridge_server.LOG_CONTENT = log_content
    bridge_server.SOUND_ENABLED = sound_enabled
    bridge_server.BridgeHandler.default_mode = "clipboard" if clipboard_only else "type"
    bridge_server.type_text = backend.type_text
    bridge_server.notify = backend.notify
    bridge_server.chime = backend.chime
    bridge_server.configure_allowed_hosts(allow_hosts or [])
    bridge_server.start_allowed_hosts_refresher()

    backend.ensure_ready(clipboard_only=clipboard_only)
    httpd = bridge_server.BridgeServer(("0.0.0.0", port), bridge_server.BridgeHandler)

    lan = bridge_server.get_lan_ip()
    tail = bridge_server.get_tail_ip()
    print(
        f"\nWhisper Bridge {bridge_server.VERSION} - {target_name}\n"
        f"  Backend:   {backend.describe()}\n"
        f"  LAN:       http://{lan}:{port}\n"
        f"  Tailscale: {f'http://{tail}:{port}' if tail else 'not connected'}\n"
        f"  Console:   http://localhost:{port}\n"
        f"  Token:     {bridge_server.TOKEN_FILE} (protected)\n"
    )

    def stop(*_args):
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
