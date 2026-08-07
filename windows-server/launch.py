#!/usr/bin/env python3
"""Whisper Bridge receiver launcher for Windows."""

import argparse
import os
import subprocess
import sys

WINDOWS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(WINDOWS_DIR)
sys.path.insert(0, WINDOWS_DIR)
sys.path.insert(0, ROOT_DIR)

from common import bridge_server  # noqa: E402
from common.receiver_runtime import run_receiver  # noqa: E402
import backend  # noqa: E402

RUN_VALUE = "WhisperBridge"


def _configure_token_path() -> None:
    app_data = os.environ.get("APPDATA") or os.path.expanduser("~")
    bridge_server.TOKEN_DIR = os.path.join(app_data, "WhisperBridge")
    bridge_server.TOKEN_FILE = os.path.join(bridge_server.TOKEN_DIR, "token")


def _startup_command(port: int, allow_hosts: list[str], clipboard_only: bool, no_sound: bool) -> str:
    pythonw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
    executable = pythonw if os.path.exists(pythonw) else sys.executable
    args = [executable, os.path.abspath(__file__), "--port", str(port)]
    for host in allow_hosts:
        args.extend(["--allow-host", host])
    if clipboard_only:
        args.append("--clipboard-only")
    if no_sound:
        args.append("--no-sound")
    return subprocess.list2cmdline(args)


def install_login(port: int, allow_hosts: list[str], clipboard_only: bool, no_sound: bool) -> None:
    import winreg

    key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(
            key,
            RUN_VALUE,
            0,
            winreg.REG_SZ,
            _startup_command(port, allow_hosts, clipboard_only, no_sound),
        )
    print("Whisper Bridge will start automatically when you sign in")


def uninstall_login() -> None:
    import winreg

    key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE) as key:
            winreg.DeleteValue(key, RUN_VALUE)
    except FileNotFoundError:
        pass
    print("Whisper Bridge login startup removed")


def main() -> None:
    _configure_token_path()
    parser = argparse.ArgumentParser(description="Whisper Bridge Windows Receiver")
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
        "Windows",
        args.port,
        args.allow_host,
        args.clipboard_only,
        args.log_content,
        not args.no_sound,
    )


if __name__ == "__main__":
    main()
