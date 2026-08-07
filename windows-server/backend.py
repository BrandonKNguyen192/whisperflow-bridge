#!/usr/bin/env python3
"""Windows clipboard and focused-field input backend."""

import shutil
import subprocess
import time


def _powershell(script: str, input_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", script],
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
    )


def describe() -> str:
    return "Windows PowerShell clipboard + SendKeys"


def ensure_ready(clipboard_only: bool = False) -> None:
    del clipboard_only
    if not shutil.which("powershell.exe"):
        raise RuntimeError("powershell.exe is required")


def _clipboard_write(text: str) -> None:
    _powershell("[Console]::In.ReadToEnd() | Set-Clipboard", text)


def _clipboard_read() -> str:
    return _powershell("Get-Clipboard -Raw").stdout.rstrip("\r\n")


def _send_keys(keys: str) -> None:
    scripts = {
        "paste": "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')",
        "enter": "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')",
    }
    _powershell(scripts[keys])


def type_text(text: str, mode: str = "type", enter_after: bool = False) -> bool:
    try:
        if mode == "enter":
            _send_keys("enter")
            return True
        if mode == "append":
            existing = _clipboard_read()
            text = f"{existing}\r\n{text}" if existing else text
        _clipboard_write(text)
        if mode == "clipboard" or mode == "append":
            return True
        time.sleep(0.08)
        _send_keys("paste")
        if enter_after:
            time.sleep(0.08)
            _send_keys("enter")
        return True
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Input failed: {exc}")
        return False


def notify(title: str, message: str) -> None:
    del title, message


def chime() -> None:
    try:
        _powershell("[System.Media.SystemSounds]::Asterisk.Play()")
    except (OSError, subprocess.CalledProcessError):
        pass
