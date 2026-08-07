#!/usr/bin/env python3
"""Ubuntu clipboard and focused-field input backend."""

import os
import shutil
import subprocess
import time


def _has(command: str) -> bool:
    return shutil.which(command) is not None


def _wayland() -> bool:
    return os.environ.get("XDG_SESSION_TYPE", "").lower() == "wayland" or bool(
        os.environ.get("WAYLAND_DISPLAY")
    )


def describe() -> str:
    if _wayland():
        key_tool = "ydotool" if _has("ydotool") else "wtype" if _has("wtype") else "missing"
        return f"Wayland (wl-clipboard + {key_tool})"
    return "X11 (xclip + xdotool)"


def ensure_ready(clipboard_only: bool = False) -> None:
    if _wayland():
        missing = []
        if not _has("wl-copy") or not _has("wl-paste"):
            missing.append("wl-clipboard")
        if not clipboard_only and not (_has("ydotool") or _has("wtype")):
            missing.append("ydotool")
    else:
        missing = []
        if not _has("xclip"):
            missing.append("xclip")
        if not clipboard_only and not _has("xdotool"):
            missing.append("xdotool")
    if missing:
        packages = " ".join(sorted(set(missing)))
        raise RuntimeError(f"Missing Ubuntu input tools. Install with: sudo apt install {packages}")


def _clipboard_write(text: str) -> None:
    if _wayland():
        subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=text, text=True, check=True)
    else:
        subprocess.run(["xclip", "-selection", "clipboard"], input=text, text=True, check=True)


def _clipboard_read() -> str:
    command = ["wl-paste", "--no-newline"] if _wayland() else ["xclip", "-selection", "clipboard", "-o"]
    return subprocess.run(command, capture_output=True, text=True, check=True).stdout


def _send_shortcut(shortcut: str) -> None:
    if _wayland() and _has("ydotool"):
        keys = {
            "paste": ["29:1", "47:1", "47:0", "29:0"],
            "enter": ["28:1", "28:0"],
        }
        subprocess.run(["ydotool", "key", *keys[shortcut]], check=True)
    elif _wayland() and _has("wtype"):
        command = ["wtype", "-M", "ctrl", "v", "-m", "ctrl"] if shortcut == "paste" else ["wtype", "-k", "Return"]
        subprocess.run(command, check=True)
    else:
        key = "ctrl+v" if shortcut == "paste" else "Return"
        subprocess.run(["xdotool", "key", "--clearmodifiers", key], check=True)


def type_text(text: str, mode: str = "type", enter_after: bool = False) -> bool:
    try:
        if mode == "enter":
            _send_shortcut("enter")
            return True
        if mode == "append":
            existing = _clipboard_read()
            text = f"{existing}\n{text}" if existing else text
        _clipboard_write(text)
        if mode == "clipboard" or mode == "append":
            return True
        time.sleep(0.08)
        _send_shortcut("paste")
        if enter_after:
            time.sleep(0.08)
            _send_shortcut("enter")
        return True
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Input failed: {exc}")
        return False


def control_mouse(action: str = "move", dx: int = 0, dy: int = 0,
                  button: str = "left", x: int | None = None,
                  y: int | None = None) -> tuple[bool, str]:
    """Mouse control: full support on X11 (xdotool), best-effort on Wayland."""
    try:
        if _wayland():
            if action == "click":
                b = {"left": 0, "right": 1, "middle": 2}.get(button, 0)
                subprocess.run(["ydotool", "mouse", str(b), "1"], check=True)
                subprocess.run(["ydotool", "mouse", str(b), "0"], check=True)
                return True, ""
            if action == "double_click":
                b = {"left": 0, "right": 1, "middle": 2}.get(button, 0)
                for _ in range(2):
                    subprocess.run(["ydotool", "mouse", str(b), "1"], check=True)
                    subprocess.run(["ydotool", "mouse", str(b), "0"], check=True)
                    time.sleep(0.04)
                return True, ""
            return False, "move/scroll/drag need an X11 session (xdotool)"

        b = {"left": 1, "middle": 2, "right": 3}[button]
        if action == "move":
            subprocess.run(["xdotool", "mousemove_relative", "--", str(dx), str(dy)], check=True)
        elif action == "scroll":
            clicks = max(1, abs(dy) // 12) if dy else 1
            button_id = 4 if dy > 0 else 5 if dy < 0 else 7 if dx > 0 else 6
            subprocess.run(["xdotool", "click", "--repeat", str(clicks), str(button_id)], check=True)
        elif action in ("click", "double_click"):
            command = ["xdotool", "click"]
            if action == "double_click":
                command += ["--repeat", "2"]
            command.append(str(b))
            subprocess.run(command, check=True)
        elif action == "drag":
            subprocess.run(["xdotool", "mousedown", str(b)], check=True)
            subprocess.run(["xdotool", "mousemove_relative", "--", str(dx), str(dy)], check=True)
            subprocess.run(["xdotool", "mouseup", str(b)], check=True)
        elif action in ("down", "up"):
            subprocess.run(["xdotool", "mouse" + action, str(b)], check=True)
        else:
            return False, f"unsupported action {action}"
        return True, ""
    except (OSError, subprocess.CalledProcessError) as exc:
        return False, str(exc)


def notify(title: str, message: str) -> None:
    if _has("notify-send"):
        subprocess.run(["notify-send", "--app-name=Whisper Bridge", title, message], check=False)


def chime() -> None:
    sound = "/usr/share/sounds/freedesktop/stereo/message.oga"
    if _has("paplay") and os.path.exists(sound):
        subprocess.Popen(["paplay", sound], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
