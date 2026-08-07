#!/usr/bin/env python3
"""
Whisperflow Bridge — Floating Status Pill
Always-visible floating indicator showing bridge connectivity and live
dictation feedback. Sits in the bottom-right corner of the screen.

No Accessibility permissions needed. Just run it.
"""

import json
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
import urllib.request

# ── Config ──────────────────────────────────────────────────────────────────

SERVER_PORT = int(os.environ.get("WHISPERFLOW_PORT", "9877"))
POLL_INTERVAL = 1.0
OVERLAY_WIDTH = 248
OVERLAY_HEIGHT = 44
MARGIN = 20

# ── Komodos palette ─────────────────────────────────────────────────────────

GREEN     = "#2E7D46"
GREEN_SOFT = "#E6F0E8"
INK       = "#1C1B19"
T2        = "#6E6C66"
T3        = "#9A988F"
NEUTRAL   = "#8A887F"
RED       = "#D14343"
AMBER     = "#F2C14E"
BORDER    = "#DCDBD4"
CARD_BG   = "#FFFFFF"
SHADOW    = "#E0DFD9"


def get_screen_size():
    """Get the primary screen dimensions."""
    try:
        out = subprocess.run(
            ["osascript", "-e",
             "tell application \"Finder\" to get bounds of window of desktop"],
            capture_output=True, text=True, timeout=2
        ).stdout.strip()
        if out:
            parts = out.split(", ")
            if len(parts) == 4:
                return int(parts[2]), int(parts[3])
    except Exception:
        pass
    return 1800, 1169  # fallback


def poll_server():
    """Returns dict with server status, or None if unreachable."""
    try:
        req = urllib.request.Request(
            f"http://localhost:{SERVER_PORT}/status",
            headers={"User-Agent": "WhisperBridge-Overlay/1.0"}
        )
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            return json.loads(resp.read())
    except Exception:
        return None


class FloatingPill:
    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()

        self.win = tk.Toplevel(self.root)
        self.win.title("")
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.0)

        sw, sh = get_screen_size()
        start_x = sw - OVERLAY_WIDTH - MARGIN
        start_y = sh - OVERLAY_HEIGHT - MARGIN - 40  # above Dock
        self.win.geometry(f"{OVERLAY_WIDTH}x{OVERLAY_HEIGHT}+{start_x}+{start_y}")

        self.canvas = tk.Canvas(
            self.win,
            width=OVERLAY_WIDTH,
            height=OVERLAY_HEIGHT,
            highlightthickness=0,
            bd=0,
        )
        self.canvas.configure(bg="systemTransparent")
        self.canvas.pack()

        self.server_ok = False
        self.dictation_count = 0
        self.last_preview = ""
        self.last_mode = ""
        self.flash_until = 0.0
        self._running = True
        self._pulse = 0.0
        self._anim_frame = 0

    def _draw(self):
        self.canvas.delete("all")
        w, h = OVERLAY_WIDTH, OVERLAY_HEIGHT
        r = h / 2

        # Shadow
        self.canvas.create_oval(2, 3, w - 2, h + 2, fill=SHADOW, outline="")

        # Pill background
        self.canvas.create_oval(0, 1, 2 * r, h - 1, fill=CARD_BG, outline="")
        self.canvas.create_oval(w - 2 * r, 1, w, h - 1, fill=CARD_BG, outline="")
        self.canvas.create_rectangle(r, 1, w - r, h - 1, fill=CARD_BG, outline="")

        # Pill border
        self.canvas.create_oval(0, 1, 2 * r, h - 1, outline=BORDER, width=1)
        self.canvas.create_oval(w - 2 * r, 1, w, h - 1, outline=BORDER, width=1)
        self.canvas.create_line(r, 1, w - r, 1, fill=BORDER, width=1)
        self.canvas.create_line(r, h - 2, w - r, h - 2, fill=BORDER, width=1)

        # Gradient accent line at top
        steps = 20
        for i in range(steps):
            frac = i / steps
            if frac < 0.4:
                color = self._lerp_color("#4C8DFF", "#34C77B", frac / 0.4)
            else:
                color = self._lerp_color("#34C77B", "#F2C14E", (frac - 0.4) / 0.6)
            x1 = r + i * (w - 2 * r) / steps
            x2 = r + (i + 1) * (w - 2 * r) / steps
            self.canvas.create_line(x1, 0, x2, 0, fill=color, width=2)

        # Status dot with pulse
        dot_x, dot_y = 16, h / 2
        if self.server_ok:
            dot_color = GREEN
            # Pulse ring
            pulse_r = 5 + abs(self._pulse) * 3
            self.canvas.create_oval(
                dot_x - pulse_r, dot_y - pulse_r,
                dot_x + pulse_r, dot_y + pulse_r,
                outline=GREEN, width=1, dash=(3, 2)
            )
        else:
            dot_color = NEUTRAL

        self.canvas.create_oval(
            dot_x - 4, dot_y - 4, dot_x + 4, dot_y + 4,
            fill=dot_color, outline=""
        )

        # Main text
        if self.server_ok:
            if self.last_preview and time.time() < self.flash_until:
                preview = self.last_preview[:24]
                if len(self.last_preview) > 24:
                    preview += "..."
                label = preview
                label_color = INK
            else:
                label = "Ready"
                label_color = T2
        else:
            label = "Server offline"
            label_color = RED

        self.canvas.create_text(
            32, h / 2,
            text=label, anchor="w",
            fill=label_color,
            font=("Helvetica Neue", 13, "normal"),
        )

        # Mode badge
        if self.server_ok and self.last_mode:
            mode_label = self.last_mode[:8]
            badge_x = w - 62
            badge_y = h / 2
            self.canvas.create_oval(
                badge_x - 8, badge_y - 8,
                badge_x + 26, badge_y + 8,
                fill=GREEN_SOFT, outline=""
            )
            self.canvas.create_rectangle(
                badge_x, badge_y - 8,
                badge_x + 26, badge_y + 8,
                fill=GREEN_SOFT, outline=""
            )
            self.canvas.create_oval(
                badge_x + 18, badge_y - 8,
                badge_x + 26, badge_y + 8,
                fill=GREEN_SOFT, outline=""
            )
            self.canvas.create_text(
                badge_x + 9, badge_y,
                text=mode_label,
                fill=GREEN,
                font=("Helvetica Neue", 10, "bold"),
                anchor="w"
            )

        # Count badge
        if self.dictation_count > 0:
            badge_x = w - 26
            badge_y = h / 2
            self.canvas.create_oval(
                badge_x - 10, badge_y - 10,
                badge_x + 10, badge_y + 10,
                fill=GREEN_SOFT, outline=""
            )
            self.canvas.create_text(
                badge_x, badge_y,
                text=str(self.dictation_count),
                fill=GREEN,
                font=("Helvetica Neue", 11, "bold"),
            )

    def _lerp_color(self, c1, c2, t):
        r1, g1, b1 = int(c1[1:3], 16), int(c1[3:5], 16), int(c1[5:7], 16)
        r2, g2, b2 = int(c2[1:3], 16), int(c2[3:5], 16), int(c2[5:7], 16)
        r = int(r1 + (r2 - r1) * t)
        g = int(g1 + (g2 - g1) * t)
        b = int(b1 + (b2 - b1) * t)
        return f"#{r:02x}{g:02x}{b:02x}"

    def animate(self):
        if not self._running:
            return

        self._anim_frame += 1
        self._pulse = (self._anim_frame % 120) / 60.0 - 1.0  # -1 to 1 sine wave

        # Fade in
        alpha = self.win.attributes("-alpha")
        if alpha < 0.92:
            self.win.attributes("-alpha", min(0.92, alpha + 0.05))
            if alpha < 0.01:
                self.win.deiconify()

        self._draw()
        self.root.after(50, self.animate)

    def flash_dictation(self, preview, mode, count):
        self.last_preview = preview
        self.last_mode = mode
        self.dictation_count = count
        self.flash_until = time.time() + 4.0

    def start(self):
        self.root.after(50, self.animate)
        self._start_poll()

    def _start_poll(self):
        def poll():
            last_count = 0
            while self._running:
                data = poll_server()
                if data and data.get("ok"):
                    if not self.server_ok:
                        self.server_ok = True
                    status = data.get("status", {})
                    new_count = status.get("count", 0)
                    new_preview = status.get("last_preview", "")
                    new_mode = status.get("last_mode", "")
                    if new_count > last_count:
                        last_count = new_count
                        self.flash_dictation(new_preview, new_mode, new_count)
                    if time.time() > self.flash_until and self.last_preview:
                        self.last_preview = ""
                        self.last_mode = ""
                    self.dictation_count = last_count
                else:
                    self.server_ok = False
                time.sleep(POLL_INTERVAL)

        t = threading.Thread(target=poll, daemon=True)
        t.start()


def main():
    global SERVER_PORT
    for i, arg in enumerate(sys.argv):
        if arg == "--port" and i + 1 < len(sys.argv):
            SERVER_PORT = int(sys.argv[i + 1])

    print(f"  Pill starting on port :{SERVER_PORT}")

    pill = FloatingPill()
    pill.start()

    try:
        pill.root.mainloop()
    except KeyboardInterrupt:
        pill._running = False
        pill.root.destroy()


if __name__ == "__main__":
    main()
