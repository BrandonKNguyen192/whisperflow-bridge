#!/usr/bin/env python3
"""Whisper Bridge receiver launcher for Ubuntu."""

import argparse
import os
import shlex
import subprocess
import sys

UBUNTU_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(UBUNTU_DIR)
sys.path.insert(0, UBUNTU_DIR)
sys.path.insert(0, ROOT_DIR)

from common import bridge_server  # noqa: E402
from common.receiver_runtime import run_receiver  # noqa: E402
import backend  # noqa: E402

SERVICE_NAME = "whisperbridge.service"
SERVICE_DIR = os.path.expanduser("~/.config/systemd/user")
SERVICE_PATH = os.path.join(SERVICE_DIR, SERVICE_NAME)


def _service_text(port: int, allow_hosts: list[str], clipboard_only: bool, no_sound: bool) -> str:
    args = [sys.executable, os.path.abspath(__file__), "--port", str(port)]
    for host in allow_hosts:
        args.extend(["--allow-host", host])
    if clipboard_only:
        args.append("--clipboard-only")
    if no_sound:
        args.append("--no-sound")
    command = " ".join(shlex.quote(arg) for arg in args)
    return f"""[Unit]
Description=Whisper Bridge Ubuntu Receiver
After=graphical-session.target network-online.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart={command}
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
"""


def install_login(port: int, allow_hosts: list[str], clipboard_only: bool, no_sound: bool) -> None:
    os.makedirs(SERVICE_DIR, exist_ok=True)
    with open(SERVICE_PATH, "w", encoding="utf-8") as service_file:
        service_file.write(_service_text(port, allow_hosts, clipboard_only, no_sound))
    os.chmod(SERVICE_PATH, 0o600)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "enable", "--now", SERVICE_NAME], check=True)
    print(f"Installed and started {SERVICE_PATH}")


def uninstall_login() -> None:
    subprocess.run(["systemctl", "--user", "disable", "--now", SERVICE_NAME], check=False)
    try:
        os.remove(SERVICE_PATH)
    except FileNotFoundError:
        pass
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    print("Whisper Bridge login service removed")


def main() -> None:
    parser = argparse.ArgumentParser(description="Whisper Bridge Ubuntu Receiver")
    parser.add_argument("--port", type=int, default=bridge_server.DEFAULT_PORT)
    parser.add_argument("--allow-host", action="append", default=[])
    parser.add_argument("--clipboard-only", action="store_true")
    parser.add_argument("--log-content", action="store_true")
    parser.add_argument("--no-sound", action="store_true")
    parser.add_argument("--install-login", action="store_true")
    parser.add_argument("--uninstall-login", action="store_true")
    args = parser.parse_args()

    if args.install_login:
        install_login(args.port, args.allow_host, args.clipboard_only, args.no_sound)
        return
    if args.uninstall_login:
        uninstall_login()
        return
    run_receiver(
        backend,
        "Ubuntu",
        args.port,
        args.allow_host,
        args.clipboard_only,
        args.log_content,
        not args.no_sound,
    )


if __name__ == "__main__":
    main()
