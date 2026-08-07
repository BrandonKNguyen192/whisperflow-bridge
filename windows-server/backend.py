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


_MOUSE_HEADER = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseNative {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
'''


def control_mouse(action: str = "move", dx: int = 0, dy: int = 0,
                  button: str = "left", x: int | None = None,
                  y: int | None = None) -> tuple[bool, str]:
    """Mouse control via user32 mouse_event (Windows)."""
    down = {"left": 0x0002, "right": 0x0008, "middle": 0x0020}
    up = {"left": 0x0004, "right": 0x0010, "middle": 0x0040}
    if action not in ("move", "scroll", "click", "double_click", "drag", "down", "up"):
        return False, f"unsupported action {action}"
    if button not in down:
        return False, f"unsupported button {button}"

    steps = []
    if x is not None and y is not None:
        steps.append(f"[MouseNative]::SetCursorPos({int(x)}, {int(y)})")
    if action == "move":
        steps.append(f"[MouseNative]::mouse_event(0x0001, {int(dx)}, {int(dy)}, 0, [UIntPtr]::Zero)")
    elif action == "scroll":
        delta = int(dy or 0) * 4
        if delta == 0:
            delta = 1
        steps.append(f"[MouseNative]::mouse_event(0x0800, 0, 0, {delta}, [UIntPtr]::Zero)")
    elif action in ("click", "double_click"):
        count = 2 if action == "double_click" else 1
        for _ in range(count):
            steps.append(f"[MouseNative]::mouse_event({down[button]}, 0, 0, 0, [UIntPtr]::Zero)")
            steps.append(f"[MouseNative]::mouse_event({up[button]}, 0, 0, 0, [UIntPtr]::Zero)")
            if count == 2:
                steps.append("Start-Sleep -Milliseconds 40")
    elif action == "drag":
        steps.append(f"[MouseNative]::mouse_event({down[button]}, 0, 0, 0, [UIntPtr]::Zero)")
        steps.append(f"[MouseNative]::mouse_event(0x0001, {int(dx)}, {int(dy)}, 0, [UIntPtr]::Zero)")
        steps.append(f"[MouseNative]::mouse_event({up[button]}, 0, 0, 0, [UIntPtr]::Zero)")
    elif action in ("down", "up"):
        flag = down[button] if action == "down" else up[button]
        steps.append(f"[MouseNative]::mouse_event({flag}, 0, 0, 0, [UIntPtr]::Zero)")

    try:
        _powershell(_MOUSE_HEADER + "\n" + "\n".join(steps))
        return True, ""
    except (OSError, subprocess.CalledProcessError) as exc:
        return False, str(exc)


def notify(title: str, message: str) -> None:
    del title, message


def chime() -> None:
    try:
        _powershell("[System.Media.SystemSounds]::Asterisk.Play()")
    except (OSError, subprocess.CalledProcessError):
        pass
