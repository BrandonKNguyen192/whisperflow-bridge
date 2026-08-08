#!/usr/bin/env python3
"""Windows clipboard and focused-field input backend.

All input is injected in-process through Win32 (ctypes -> user32): text is
typed with SendInput KEYEVENTF_UNICODE, keys with virtual-key SendInput,
mouse with SendInput mouse events, and the clipboard via the Win32 clipboard
API. No powershell.exe subprocesses — spawning one per keystroke used to
flash console windows on screen and steal focus from the target app.
"""

import ctypes
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

# 64-bit handles must keep their width — ctypes defaults to 32-bit ints.
user32.OpenClipboard.restype = wintypes.BOOL
user32.EmptyClipboard.restype = wintypes.BOOL
user32.CloseClipboard.restype = wintypes.BOOL
user32.SetClipboardData.restype = wintypes.HANDLE
user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
user32.GetClipboardData.restype = wintypes.HANDLE
user32.GetClipboardData.argtypes = [wintypes.UINT]
kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
kernel32.GlobalLock.restype = wintypes.LPVOID
kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]

# ---- SendInput structs ---------------------------------------------------

INPUT_KEYBOARD = 1
INPUT_MOUSE = 0

KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_EXTENDEDKEY = 0x0001

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800

VK_RETURN = 0x0D
VK_CONTROL = 0x11
VK_SHIFT = 0x10
VK_MENU = 0x12
VK_LBUTTON = 0x01


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
user32.SendInput.restype = wintypes.UINT


def _send_key(vk: int = 0, scan: int = 0, flags: int = 0) -> None:
    inp = INPUT(type=INPUT_KEYBOARD, union=INPUT_UNION(
        ki=KEYBDINPUT(wVk=vk, wScan=scan, dwFlags=flags)
    ))
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def _send_mouse(flags: int, dx: int = 0, dy: int = 0, data: int = 0) -> None:
    inp = INPUT(type=INPUT_MOUSE, union=INPUT_UNION(
        mi=MOUSEINPUT(dx=dx, dy=dy, mouseData=data, dwFlags=flags)
    ))
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def _press_vk(vk: int) -> None:
    _send_key(vk=vk)
    _send_key(vk=vk, flags=KEYEVENTF_KEYUP)


def _type_unicode(text: str) -> None:
    """Type arbitrary text via KEYEVENTF_UNICODE — handles every codepoint
    including emoji and non-Latin scripts, no clipboard or app shortcuts."""
    encoded = text.encode("utf-16-le")
    for i in range(0, len(encoded), 2):
        unit = encoded[i] | (encoded[i + 1] << 8)
        _send_key(scan=unit, flags=KEYEVENTF_UNICODE)
        _send_key(scan=unit, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)


# ---- Clipboard -----------------------------------------------------------

CF_UNICODETEXT = 13
GMEM_MOVEABLE = 0x0002
GMEM_ZEROINIT = 0x0040


def _clipboard_write(text: str) -> bool:
    if not user32.OpenClipboard(None):
        return False
    try:
        user32.EmptyClipboard()
        data = (text + "\0").encode("utf-16-le")
        handle = kernel32.GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, len(data))
        if not handle:
            return False
        pointer = kernel32.GlobalLock(handle)
        try:
            ctypes.memmove(pointer, data, len(data))
        finally:
            kernel32.GlobalUnlock(handle)
        # Ownership of the memory moves to the clipboard; do not free.
        user32.SetClipboardData(CF_UNICODETEXT, handle)
        return True
    finally:
        user32.CloseClipboard()


def _clipboard_read() -> str:
    if not user32.OpenClipboard(None):
        return ""
    try:
        handle = user32.GetClipboardData(CF_UNICODETEXT)
        if not handle:
            return ""
        pointer = kernel32.GlobalLock(handle)
        if not pointer:
            return ""
        try:
            return ctypes.c_wchar_p(pointer).value or ""
        finally:
            kernel32.GlobalUnlock(handle)
    finally:
        user32.CloseClipboard()


# ---- Public backend API (unchanged contract) -----------------------------

def describe() -> str:
    return "Windows in-process SendInput + clipboard"


def ensure_ready(clipboard_only: bool = False) -> None:
    del clipboard_only  # always available; no external tooling required


def _press_ctrl_v() -> None:
    _send_key(vk=VK_CONTROL)
    _send_key(vk=0x56)  # 'V'
    _send_key(vk=0x56, flags=KEYEVENTF_KEYUP)
    _send_key(vk=VK_CONTROL, flags=KEYEVENTF_KEYUP)


def type_text(text: str, mode: str = "type", enter_after: bool = False) -> bool:
    try:
        if mode == "enter":
            _press_vk(VK_RETURN)
            return True
        if mode == "append":
            existing = _clipboard_read()
            text = f"{existing}\r\n{text}" if existing else text
        if mode in ("clipboard", "append"):
            return _clipboard_write(text)
        # Paste-based typing: writing the clipboard and injecting Ctrl+V is
        # atomic and verbatim. Per-character SendInput can get mangled by
        # some apps (repeated/wrong characters), so it is only kept as a
        # fallback in _type_unicode. All in-process — no windows, no focus
        # stealing.
        if not _clipboard_write(text):
            return False
        time.sleep(0.05)
        _press_ctrl_v()
        if enter_after:
            time.sleep(0.08)
            _press_vk(VK_RETURN)
        return True
    except OSError as exc:
        print(f"Input failed: {exc}")
        return False


_MOUSE_DOWN = {"left": MOUSEEVENTF_LEFTDOWN, "right": MOUSEEVENTF_RIGHTDOWN,
               "middle": MOUSEEVENTF_MIDDLEDOWN}
_MOUSE_UP = {"left": MOUSEEVENTF_LEFTUP, "right": MOUSEEVENTF_RIGHTUP,
             "middle": MOUSEEVENTF_MIDDLEUP}


def control_mouse(action: str = "move", dx: int = 0, dy: int = 0,
                  button: str = "left", x: int | None = None,
                  y: int | None = None) -> tuple[bool, str]:
    """Mouse control via in-process SendInput mouse events."""
    if action not in ("move", "scroll", "click", "double_click", "drag", "down", "up"):
        return False, f"unsupported action {action}"
    if button not in _MOUSE_DOWN:
        return False, f"unsupported button {button}"

    try:
        if x is not None and y is not None:
            user32.SetCursorPos(int(x), int(y))
        if action == "move":
            _send_mouse(MOUSEEVENTF_MOVE, dx=int(dx), dy=int(dy))
        elif action == "scroll":
            delta = int(dy or 0) * 4
            if delta == 0:
                delta = 1
            _send_mouse(MOUSEEVENTF_WHEEL, data=delta & 0xFFFFFFFF)
        elif action in ("click", "double_click"):
            count = 2 if action == "double_click" else 1
            for i in range(count):
                _send_mouse(_MOUSE_DOWN[button])
                _send_mouse(_MOUSE_UP[button])
                if count == 2 and i == 0:
                    time.sleep(0.04)
        elif action == "drag":
            _send_mouse(_MOUSE_DOWN[button])
            _send_mouse(MOUSEEVENTF_MOVE, dx=int(dx), dy=int(dy))
            _send_mouse(_MOUSE_UP[button])
        elif action in ("down", "up"):
            _send_mouse(_MOUSE_DOWN[button] if action == "down" else _MOUSE_UP[button])
        return True, ""
    except OSError as exc:
        return False, str(exc)


def notify(title: str, message: str) -> None:
    del title, message  # no notification center hook on Windows


def chime() -> None:
    try:
        user32.MessageBeep(0x40)  # MB_ICONASTERISK
    except OSError:
        pass
