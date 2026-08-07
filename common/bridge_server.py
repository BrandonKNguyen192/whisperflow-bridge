#!/usr/bin/env python3
"""
Whisper Flow Bridge — Shared Desktop Receiver
Receives text from the Android app and sends it to a platform input backend.
Zero dependencies — uses only Python standard library.

Usage:
    python3 server.py [--port 9877] [--clipboard-only]
"""

import argparse
import json
import os
import re
import socket
import subprocess
import threading
import sys
import time
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import hmac
import secrets
import stat

DEFAULT_PORT = 9877
VERSION = "1.1.0"
TARGET_NAME = "Mac"
PASTE_SHORTCUT = "⌘V"
AUTH_TOKEN = None  # set in main(); when set, /send + console require it

# Live activity (read by the menu-bar app and /status)
STATUS = {"count": 0, "last_preview": "", "last_source": "", "last_mode": "", "last_ts": ""}

TOKEN_DIR = os.path.expanduser("~/.config/whisperbridge")
TOKEN_FILE = os.path.join(TOKEN_DIR, "token")
MAX_BODY = 1_000_000
LOG_CONTENT = False
ALLOWED_HOSTS: set[str] = set()


def persist_token(token: str) -> None:
    """Persist the shared secret with owner-only permissions."""
    if not token:
        raise ValueError("token must not be empty")
    os.makedirs(TOKEN_DIR, exist_ok=True)
    os.chmod(TOKEN_DIR, stat.S_IRWXU)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token + "\n")
    os.chmod(TOKEN_FILE, stat.S_IRUSR | stat.S_IWUSR)


def resolve_token(cli_token: str | None) -> str:
    """Resolve the shared secret. Precedence: CLI > env > stored file > generate.

    The token is always non-empty — the bridge injects keystrokes, so it must
    never run unauthenticated. A generated token is persisted at 0600 so the
    secret never has to appear in argv, shell history, or a LaunchAgent plist.
    """
    token = cli_token or os.environ.get("WHISPERFLOW_TOKEN")
    if token:
        return token
    try:
        with open(TOKEN_FILE, encoding="utf-8") as fh:
            stored = fh.read().strip()
        if stored:
            return stored
    except OSError:
        pass
    token = secrets.token_urlsafe(24)
    persist_token(token)
    return token

def get_lan_ip():
    """Best-effort LAN/egress IPv4 via a UDP connect (no packets sent)."""
    if sys.platform == "darwin":
        for interface in ("en0", "en1"):
            try:
                out = subprocess.run(
                    ["ipconfig", "getifaddr", interface],
                    capture_output=True, text=True, timeout=1,
                ).stdout.strip()
                if out:
                    return out
            except Exception:
                pass
    for target in ("8.8.8.8", "1.1.1.1"):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0.3)
            s.connect((target, 80))
            ip = s.getsockname()[0]
            s.close()
            if ip and ip != "127.0.0.1":
                return ip
        except Exception:
            pass
    return "127.0.0.1"

_tail_cache = {"ip": None, "ts": 0.0}
def get_tail_ip(force=False):
    """Cached Tailscale IPv4 (None if Tailscale is absent/offline). Cached 15s."""
    now = time.time()
    if not force and (now - _tail_cache["ts"]) < 15:
        return _tail_cache["ip"]
    ip = None
    try:
        out = subprocess.run(["tailscale", "ip", "-4"],
                             capture_output=True, text=True, timeout=1.5).stdout.strip()
        if out:
            ip = out.splitlines()[0].strip() or None
    except Exception:
        ip = None
    _tail_cache["ip"] = ip
    _tail_cache["ts"] = now
    return ip


def configure_allowed_hosts(extra_hosts: list[str] | None = None) -> None:
    """Populate Host-header destinations accepted by every server entry point."""
    hostname = socket.gethostname().lower()
    local_hostname = hostname if hostname.endswith(".local") else f"{hostname}.local"
    hosts = {
        hostname,
        local_hostname,
        "localhost",
        "127.0.0.1",
        "::1",
        "0.0.0.0",
        get_lan_ip(),
        get_tail_ip(),
    }
    hosts.update(extra_hosts or [])
    ALLOWED_HOSTS.clear()
    ALLOWED_HOSTS.update(str(host).lower() for host in hosts if host)


def start_allowed_hosts_refresher() -> threading.Thread:
    """Keep dynamic LAN and Tailscale addresses valid after network changes."""
    def refresh():
        while True:
            time.sleep(15)
            for host in (get_tail_ip(force=True), get_lan_ip()):
                if host:
                    ALLOWED_HOSTS.add(host.lower())

    thread = threading.Thread(target=refresh, daemon=True)
    thread.start()
    return thread

# Vendored QR generator (Kazuhiko Arase, MIT) — kept in its own file so the console
# renders pairing QR codes client-side with zero Python deps and no network calls.
try:
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "qrcode.js"),
              encoding="utf-8") as _fh:
        QR_LIB_JS = _fh.read()
except Exception:
    QR_LIB_JS = ""


def type_text(text: str, mode: str = "type", enter_after: bool = False) -> bool:
    """Inject text into the active application.

    mode="type"      → copy to clipboard, then simulate ⌘V
    mode="clipboard" → copy to clipboard only
    mode="append"    → append to clipboard (with newline separator)

    enter_after      → simulate Return/Enter after paste (for "type" mode)
    """
    try:
        if mode == "append":
            existing = subprocess.run(
                ["pbpaste"], capture_output=True, text=True, check=True
            ).stdout
            combined = existing + "\n" + text if existing else text
            subprocess.run(["pbcopy"], input=combined.encode(), check=True)
            return True

        # Mode 'enter': just fire a Return keystroke, no text
        if mode == "enter":
            time.sleep(0.05)
            subprocess.run(
                [
                    "osascript", "-e",
                    'tell application "System Events" to keystroke return',
                ],
                check=True,
            )
            return True

        subprocess.run(["pbcopy"], input=text.encode(), check=True)

        if mode == "clipboard":
            return True

        # Simulate ⌘V to paste into the focused field
        time.sleep(0.05)
        subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to keystroke "v" using command down',
            ],
            check=True,
        )

        # Simulate Enter if requested
        if enter_after:
            time.sleep(0.08)
            subprocess.run(
                [
                    "osascript", "-e",
                    'tell application "System Events" to keystroke return',
                ],
                check=True,
            )

        return True
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"  ✗ Failed to inject text: {exc}")
        return False

def notify(title: str, message: str):
    """Show a macOS notification (best-effort).

    Arguments are passed via `on run argv` rather than interpolated, so text
    containing quotes can never terminate the string literal and inject script.
    """
    script = 'on run argv\n display notification (item 1 of argv) with title (item 2 of argv)\nend run'
    try:
        subprocess.run(["osascript", "-e", script, message, title], capture_output=True)
    except Exception:
        pass

# Audible chime on each successful dictation. Uses macOS `afplay` on a system
# sound — non-blocking (Popen) and best-effort, so a missing binary never stalls
# the HTTP handler. Works whether you run server.py directly or via the menu bar.
SOUND_ENABLED = True
SOUND_NAME = "Tink"

def chime():
    if not SOUND_ENABLED:
        return
    name = re.sub(r"[^A-Za-z0-9_]", "", SOUND_NAME or "Tink") or "Tink"
    try:
        subprocess.Popen(
            ["afplay", f"/System/Library/Sounds/{name}.aiff"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


# ── HTTP Server ─────────────────────────────────────────────────────────────

# NOTE: rendered with str.replace (not str.format) so CSS/JS braces stay literal.
STATUS_PAGE = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Whisper Bridge</title>
<link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAzMiAzMic+PHJlY3Qgd2lkdGg9JzMyJyBoZWlnaHQ9JzMyJyByeD0nOCcgZmlsbD0nIzJFN0Q0NicvPjxwYXRoIGQ9J00xNiA4YTMgMyAwIDAgMC0zIDN2NWEzIDMgMCAwIDAgNiAwdi01YTMgMyAwIDAgMC0zLTN6bTUgOGE1IDUgMCAwIDEtMTAgMEg5YTcgNyAwIDAgMCA2IDYuOVYyNWgydi0yLjFBNyA3IDAgMCAwIDIzIDE2eicgZmlsbD0nI2ZmZicvPjwvc3ZnPg==">
<style>
:root{
 --canvas:#FBFBF9; --surface:#F6F6F3; --card:#fff; --border:#E9E8E3; --border2:#DCDBD4;
 --ink:#1C1B19; --t2:#6E6C66; --t3:#9A988F;
 --green:#2E7D46; --green-soft:#E6F0E8; --chip:#F1F0EB; --neutral:#8A887F; --err:#D14343;
 --blue:#4C8DFF; --g2:#34C77B; --amber:#F2C14E;
 --grad:linear-gradient(90deg,var(--blue),var(--g2),var(--amber));
 --r-card:16px; --r-in:12px; --r-pill:999px;
 --shadow:0 1px 2px rgba(28,27,25,.04),0 12px 32px rgba(28,27,25,.05);
}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{
 font-family:"Inter",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
 background:var(--canvas); color:var(--ink); display:flex; min-height:100vh;
 -webkit-font-smoothing:antialiased; font-size:14px; line-height:1.5;
}
svg{display:block}
.micro{font-size:11px; letter-spacing:.08em; text-transform:uppercase; color:var(--t3); font-weight:700}
.clamp1,.clamp2{display:-webkit-box; -webkit-box-orient:vertical; overflow:hidden}
.clamp1{-webkit-line-clamp:1} .clamp2{-webkit-line-clamp:2}

/* ── sidebar ───────────────────────────────────────────── */
.side{width:250px; flex:0 0 250px; background:var(--surface); border-right:1px solid var(--border);
 padding:16px 12px; display:flex; flex-direction:column; position:sticky; top:0; height:100vh}
.brand{display:flex; align-items:center; gap:10px; padding:6px 8px 16px}
.brand b{font-size:16px; letter-spacing:-.01em}
.btile{width:30px; height:30px; border-radius:9px; background:var(--green-soft); color:var(--green);
 display:flex; align-items:center; justify-content:center; flex:0 0 30px}
.btile svg{width:16px; height:16px}
.chev{margin-left:auto; color:var(--t3)} .chev svg{width:18px; height:18px}
.nav{display:flex; flex-direction:column; gap:2px}
.ni{display:flex; align-items:center; justify-content:space-between; gap:8px; padding:8px 12px;
 border-radius:var(--r-pill); color:var(--ink); text-decoration:none; cursor:pointer; user-select:none}
.ni:hover{background:var(--chip)}
.ni.active{background:var(--green-soft); color:var(--green); font-weight:600}
.ni.active:hover{background:var(--green-soft)}
.ni.cat{color:var(--t2)}
.cnt{color:var(--t3); font-size:12px; font-variant-numeric:tabular-nums}
.ni.active .cnt{color:var(--green); opacity:.75}
.micro.pad{padding:18px 12px 6px}
.spacer{flex:1}
.foot{border-top:1px solid var(--border); padding:12px 8px 2px}
.frow{display:flex; align-items:center; gap:8px; font-size:13px}
.dot{width:8px; height:8px; border-radius:50%; background:var(--green); flex:0 0 8px;
 box-shadow:0 0 0 0 rgba(46,125,70,.5); animation:pulse 2s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(46,125,70,.45)}70%{box-shadow:0 0 0 7px rgba(46,125,70,0)}100%{box-shadow:0 0 0 0 rgba(46,125,70,0)}}
.chip{background:var(--chip); color:var(--t2); border-radius:var(--r-pill); padding:4px 9px; font-size:12px}
.chip.sm{padding:2px 8px; font-size:11px; margin-left:auto}
.fsub{color:var(--t3); font-size:12px; margin-top:5px}

/* ── main ──────────────────────────────────────────────── */
.main{flex:1; padding:26px 32px 60px; max-width:1120px}
.ccard{background:var(--card); border:1px solid var(--border); border-radius:var(--r-card);
 padding:20px 22px; box-shadow:var(--shadow)}
.cc-head{display:flex; align-items:center; justify-content:space-between; gap:12px}
.seg{display:inline-flex; gap:4px}
.segbtn{border:none; background:transparent; color:var(--t2); font:inherit; font-size:13px; font-weight:600;
 padding:6px 12px; border-radius:var(--r-pill); cursor:pointer}
.segbtn:hover{background:var(--chip)}
.segbtn.active{background:var(--green-soft); color:var(--green)}
textarea{width:100%; margin-top:14px; min-height:96px; border:1px solid var(--border); border-radius:var(--r-in);
 padding:14px; font:inherit; font-size:15px; line-height:1.5; color:var(--ink); background:var(--card);
 resize:vertical; outline:none}
textarea::placeholder{color:var(--t3)}
textarea:focus{border-color:var(--green); box-shadow:0 0 0 3px var(--green-soft)}
.cc-foot{margin-top:12px; display:flex; align-items:center; justify-content:space-between; gap:12px}
.hint{color:var(--t3); font-size:13px}
.send{border:none; border-radius:var(--r-pill); padding:10px 18px; font:inherit; font-size:14px; font-weight:600;
 color:#fff; background:var(--neutral); display:inline-flex; align-items:center; gap:8px; cursor:default}
.send:not(:disabled){background:var(--green); cursor:pointer}
.send:not(:disabled):hover{filter:brightness(1.06)}
.send svg{width:15px; height:15px}
.err{color:var(--err); font-size:12px; margin-top:8px; min-height:0}

.toolbar{margin-top:18px; display:flex; gap:12px; align-items:center}
.searchbox{position:relative; flex:1}
.si{position:absolute; left:14px; top:50%; transform:translateY(-50%); color:var(--t3); display:flex}
.si svg{width:16px; height:16px}
.searchbox input{width:100%; border:1px solid var(--border); border-radius:var(--r-pill); padding:10px 16px 10px 40px;
 font:inherit; font-size:14px; background:var(--card); color:var(--ink); outline:none}
.searchbox input:focus{border-color:var(--green); box-shadow:0 0 0 3px var(--green-soft)}
select{border:1px solid var(--border); border-radius:var(--r-pill); padding:10px 14px; background:var(--card);
 color:var(--ink); font:inherit; font-size:14px; cursor:pointer; outline:none}

.grid{margin-top:16px; display:grid; grid-template-columns:repeat(auto-fill,minmax(262px,1fr)); gap:14px}
.empty{margin-top:42px; text-align:center; color:var(--t3); font-size:14px}

/* ── recent card ───────────────────────────────────────── */
.rcard{background:var(--card); border:1px solid var(--border); border-radius:var(--r-card); overflow:hidden;
 display:flex; flex-direction:column; transition:box-shadow .15s,border-color .15s}
.rcard:hover{box-shadow:var(--shadow); border-color:var(--border2)}
.rc-top{padding:16px}
.rc-head{display:flex; align-items:flex-start; justify-content:space-between; gap:10px}
.rc-title{font-size:15px; font-weight:700; letter-spacing:-.01em}
.rc-thumb{width:36px; height:36px; border-radius:10px; background:var(--green-soft); color:var(--green);
 display:flex; align-items:center; justify-content:center; flex:0 0 36px}
.rc-thumb svg{width:18px; height:18px}
.rc-body{margin-top:6px; color:var(--t2); font-size:13px}
.rc-stats{margin-top:12px; display:flex; align-items:center; gap:14px; color:var(--t3); font-size:11px}
.rc-stats span{display:inline-flex; align-items:center; gap:4px}
.rc-stats svg{width:13px; height:13px}
.rc-mark{margin-left:auto} .rc-mark svg{width:14px; height:14px}
.rc-grad{height:3px; margin:0 -1px; background:var(--grad)}
.rc-low{padding:14px 16px 16px}
.pillrow{display:flex; align-items:center; justify-content:space-between}
.pill{background:var(--chip); color:var(--t2); border-radius:var(--r-pill); padding:4px 10px; font-size:12px; font-weight:600}
.rc-link{display:inline-block; margin-top:10px; color:var(--green); font-size:13px; font-weight:600; cursor:pointer; text-decoration:none}
.rc-link:hover{text-decoration:underline}
.rc-tags{display:flex; flex-wrap:wrap; gap:6px; margin-top:10px}
.rc-foot{margin-top:12px; display:flex; align-items:center; justify-content:space-between; color:var(--t3); font-size:12px}
.rc-foot>span{display:inline-flex; align-items:center; gap:6px}
.rc-foot svg{width:13px; height:13px}
.icbtn{border:none; background:transparent; color:var(--t3); padding:5px; border-radius:8px; cursor:pointer; display:inline-flex}
.icbtn:hover{background:var(--chip); color:var(--ink)}
.icbtn svg{width:15px; height:15px}

.toast{position:fixed; left:50%; bottom:26px; transform:translateX(-50%) translateY(20px); background:var(--ink);
 color:#fff; padding:10px 16px; border-radius:var(--r-pill); font-size:13px; opacity:0; pointer-events:none;
 transition:opacity .2s,transform .2s; box-shadow:var(--shadow); z-index:50}
.toast.show{opacity:1; transform:translateX(-50%) translateY(0)}
.toast.ok{background:var(--green)}

@media (max-width:820px){
 .side{display:none}
 .main{padding:18px 16px 48px}
}

@media (prefers-color-scheme:dark){
 :root{
  --canvas:#000; --surface:#000; --card:#0D0D0D; --border:#2A2A2A; --border2:#333;
  --ink:#E8E8E8; --t2:#9E9E9E; --t3:#6E6E6E;
  --green:#4ADE80; --green-soft:#0F2A1A; --chip:#1A1A1A; --neutral:#6E6E6E; --err:#EF4444;
  --blue:#4C8DFF; --g2:#34C77B; --amber:#F2C14E;
  --grad:linear-gradient(90deg,var(--blue),var(--g2),var(--amber));
 }
 .send:not(:disabled){background:var(--green);color:#000}
 .ni.active{color:var(--green)}
 .rcard:hover{border-color:var(--border2)}
 .toast{background:var(--ink);color:#000}
 .toast.ok{background:var(--green);color:#000}
}

</style></head><body>

<aside class="side">
  <div class="brand"><span class="btile" id="btile"></span><b>Whisper Bridge</b><span class="chev" id="chev"></span></div>
  <nav class="nav">
    <a class="ni active" data-go="compose">Compose</a>
    <a class="ni" data-go="activity">Activity <span class="cnt" id="cAll">0</span></a>
  </nav>
  <div class="micro pad">Modes</div>
  <nav class="nav">
    <a class="ni cat">Type <span class="cnt" id="cType">0</span></a>
    <a class="ni cat">Clipboard <span class="cnt" id="cClip">0</span></a>
    <a class="ni cat">Append <span class="cnt" id="cApp">0</span></a>
  </nav>
  <div class="spacer"></div>
  <div class="foot">
    <div class="frow"><span class="dot"></span><span>Server listening</span><span class="chip sm">:@@PORT@@</span></div>
    <div class="fsub">v@@VERSION@@ · LAN + Tailscale</div>
  </div>
</aside>

<main class="main">
  @@AUTH_BANNER@@
  <section class="ccard" id="compose">
    <div class="cc-head">
      <span class="micro">Compose</span>
      <div class="seg" id="seg">
        <button class="segbtn active" data-mode="type">Type</button>
        <button class="segbtn" data-mode="clipboard">Clipboard</button>
        <button class="segbtn" data-mode="append">Append</button>
      </div>
    </div>
    <textarea id="txt" placeholder="Speak into Whisper Flow, or type / paste here…  ⌘ / Ctrl-Enter to send"></textarea>
    <div class="cc-foot">
      <span class="hint">Sent to your Mac and pasted into the focused field.</span>
      <button class="send" id="send" disabled><span class="si2" id="sendic"></span> Send ⌘V</button>
    </div>
    <div class="err" id="err"></div>
  </section>

  <section class="ccard" id="pair">
    <div class="cc-head">
      <span class="micro">Pair phone</span>
      <div class="seg" id="pairseg">
        <button class="segbtn active" data-net="lan">LAN</button>
        <button class="segbtn" data-net="tail">Tailscale</button>
      </div>
    </div>
    <div style="display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;margin-top:12px">
      <div id="qrbox" style="background:#fff;border:1px solid var(--border);border-radius:14px;padding:12px;line-height:0"></div>
      <div style="flex:1;min-width:210px">
        <div class="micro" style="margin-bottom:6px">Scan with the Whisper Bridge app</div>
        <div id="pairurl" style="font-family:ui-monospace,Menlo,monospace;font-size:12px;color:var(--t2);word-break:break-all;background:var(--chip);border-radius:10px;padding:9px 11px"></div>
        <div style="display:flex;gap:10px;margin-top:10px;align-items:center;flex-wrap:wrap">
          <button id="paircopy" style="border:1px solid var(--border);background:#fff;border-radius:999px;padding:7px 14px;font-size:12px;font-weight:600;color:var(--ink);cursor:pointer">Copy link</button>
          <span id="pairnote" style="font-size:12px;color:var(--t3)"></span>
        </div>
      </div>
    </div>
  </section>

  <div class="toolbar">
    <div class="searchbox"><span class="si" id="searchic"></span><input id="q" placeholder="Search recent sends…"></div>
    <select id="sort"><option value="new">Newest</option><option value="old">Oldest</option></select>
  </div>

  <div class="grid" id="grid"></div>
  <div class="empty" id="empty">Nothing yet — send something from the box above, or share from Whisper Flow on your phone.</div>
</main>

<div class="toast" id="toast"></div>

<script>
@@QR_LIB@@
var WB = @@WB_JSON@@;
var TOK = WB.token || new URLSearchParams(location.search).get('token') || '';
if (location.search.indexOf('token=') >= 0) {
  history.replaceState(null, '', location.pathname);
}
var pairNet = 'lan';
function pairHost(net){ return (net==='tail' && WB.tail) ? WB.tail : WB.lan; }
function pairPayload(net){
  var p = 'whisperbridge://pair?host='+encodeURIComponent(pairHost(net))+'&port='+encodeURIComponent(WB.port);
  if(WB.token) p += '&token='+encodeURIComponent(WB.token);
  if(WB.name) p += '&name='+encodeURIComponent(WB.name);
  return p;
}
function drawQR(){
  var net = (pairNet==='tail' && WB.tail) ? 'tail' : 'lan';
  var payload = pairPayload(net);
  var box = document.getElementById('qrbox');
  try {
    var qr = qrcode(0, 'M'); qr.addData(payload); qr.make();
    box.innerHTML = qr.createSvgTag(4, 0);
    if(box.firstChild){ box.firstChild.style.display='block'; }
  } catch(e){ box.innerHTML = '<div style="color:var(--t3);font-size:12px">QR unavailable</div>'; }
  document.getElementById('pairurl').textContent = payload;
  var tb = document.querySelector('#pairseg .segbtn[data-net="tail"]');
  if(tb) tb.style.opacity = WB.tail ? '1' : '.45';
  document.getElementById('pairnote').textContent =
    net==='tail' ? (WB.tail ? 'Reachable anywhere on your tailnet.' : 'Tailscale offline — showing LAN.')
                 : 'Same Wi‑Fi as your Mac.';
}
document.getElementById('pairseg').addEventListener('click', function(e){
  var b = e.target.closest('.segbtn'); if(!b) return;
  pairNet = b.getAttribute('data-net');
  Array.prototype.forEach.call(this.querySelectorAll('.segbtn'), function(x){ x.classList.toggle('active', x===b); });
  drawQR();
});
document.getElementById('paircopy').addEventListener('click', function(){
  var net = (pairNet==='tail' && WB.tail) ? 'tail' : 'lan';
  copyText(pairPayload(net)); toast('Pairing link copied', true);
});
var ICONS = {
 mic:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 14a3 3 0 0 0 3-3V6a3 3 0 1 0-6 0v5a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2z"/></svg>',
 chevron:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>',
 search:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>',
 send:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>',
 copy:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4a2 2 0 0 0-2 2v14h2V3h12V1zm3 4H8a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2zm0 16H8V7h11v14z"/></svg>',
 trash:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>',
 link:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z"/></svg>',
 lines:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h10"/></svg>',
 tag:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M21.41 11.58l-9-9A2 2 0 0 0 11 2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 .59 1.42l9 9A2 2 0 0 0 13 22a2 2 0 0 0 1.41-.59l7-7A2 2 0 0 0 22 13a2 2 0 0 0-.59-1.42zM7 9a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>'
};
document.getElementById('btile').innerHTML = ICONS.mic;
document.getElementById('chev').innerHTML = ICONS.chevron;
document.getElementById('searchic').innerHTML = ICONS.search;
document.getElementById('sendic').innerHTML = ICONS.send;

var recents = [], counts = {type:0, clipboard:0, append:0}, seq = 0, selectedMode = 'type';
var grid = document.getElementById('grid'), empty = document.getElementById('empty');
var txt = document.getElementById('txt'), sendBtn = document.getElementById('send'), err = document.getElementById('err');
var q = document.getElementById('q'), sort = document.getElementById('sort');

function esc(s){return String(s).replace(/[&<>"]/g, function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function cap(s){return s.charAt(0).toUpperCase()+s.slice(1);}
function now(){return new Date().toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'});}

function cardHTML(r){
  var flat = r.text.replace(/\\s+/g, ' ');
  var title = esc(flat.slice(0, 52));
  var body = flat.length > 52 ? esc(flat.slice(52, 200)) : '';
  return '<div class="rcard" data-id="'+r.id+'">'
    + '<div class="rc-top">'
      + '<div class="rc-head"><div class="rc-title clamp1">'+title+'</div><div class="rc-thumb">'+ICONS.mic+'</div></div>'
      + (body ? '<div class="rc-body clamp2">'+body+'</div>' : '')
      + '<div class="rc-stats"><span>'+ICONS.lines+r.text.length+' chars</span><span>'+ICONS.tag+cap(r.mode)+'</span><span class="rc-mark">'+ICONS.mic+'</span></div>'
    + '</div>'
    + '<div class="rc-grad"></div>'
    + '<div class="rc-low">'
      + '<div class="pillrow"><span class="pill">'+cap(r.mode)+'</span><button class="icbtn" data-act="copy" title="Copy text">'+ICONS.copy+'</button></div>'
      + '<a class="rc-link" data-act="resend">Resend →</a>'
      + '<div class="rc-tags"><span class="chip">#'+r.mode+'</span><span class="chip">#'+esc(r.source)+'</span></div>'
      + '<div class="rc-foot"><span>'+ICONS.link+esc(r.source)+' · '+r.time+'</span><button class="icbtn" data-act="trash" title="Remove">'+ICONS.trash+'</button></div>'
    + '</div>'
  + '</div>';
}

function render(){
  var list = recents.slice();
  var term = q.value.trim().toLowerCase();
  if(term){ list = list.filter(function(r){ return (r.text+' '+r.source+' '+r.mode).toLowerCase().indexOf(term) >= 0; }); }
  list.sort(function(a,b){ return sort.value === 'old' ? a.ts - b.ts : b.ts - a.ts; });
  grid.innerHTML = list.map(cardHTML).join('');
  empty.style.display = recents.length ? 'none' : 'block';
  document.getElementById('cAll').textContent = recents.length;
  document.getElementById('cType').textContent = counts.type;
  document.getElementById('cClip').textContent = counts.clipboard;
  document.getElementById('cApp').textContent = counts.append;
}

function syncSend(){ sendBtn.disabled = txt.value.trim().length === 0; }

var toastT;
function toast(msg, ok){
  var t = document.getElementById('toast');
  t.textContent = msg; t.className = 'toast show' + (ok ? ' ok' : '');
  clearTimeout(toastT); toastT = setTimeout(function(){ t.className = 'toast'; }, 1600);
}

function fallbackCopy(t){
  var a = document.createElement('textarea'); a.value = t;
  a.style.position = 'fixed'; a.style.opacity = '0'; document.body.appendChild(a);
  a.select(); try { document.execCommand('copy'); } catch(e){} document.body.removeChild(a);
}
function copyText(t){
  if(navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(t).catch(function(){ fallbackCopy(t); });
  } else { fallbackCopy(t); }
}

function postText(text, mode, addRecent){
  err.textContent = '';
  return fetch('/send', {
    method:'POST', headers:Object.assign({'Content-Type':'application/json'}, TOK?{'Authorization':'Bearer '+TOK}:{}),
    body: JSON.stringify({ text:text, mode:mode, source:'web-console' })
  }).then(function(r){ return r.json(); }).then(function(d){
    if(d.ok){
      if(addRecent){
        counts[mode] = (counts[mode] || 0) + 1;
        recents.unshift({ id:++seq, text:text, mode:mode, source:'web-console', time:now(), ts:Date.now() });
        render();
      }
      return true;
    }
    err.textContent = 'Server error: ' + (d.error || 'failed');
    return false;
  }).catch(function(e){ err.textContent = 'Network error: ' + e.message; return false; });
}

sendBtn.addEventListener('click', function(){
  var t = txt.value.trim(); if(!t) return;
  postText(t, selectedMode, true).then(function(ok){ if(ok){ txt.value = ''; syncSend(); } });
});
txt.addEventListener('input', syncSend);
txt.addEventListener('keydown', function(e){
  if((e.metaKey || e.ctrlKey) && e.key === 'Enter'){ e.preventDefault(); if(!sendBtn.disabled) sendBtn.click(); }
});

document.getElementById('seg').addEventListener('click', function(e){
  var b = e.target.closest('.segbtn'); if(!b) return;
  selectedMode = b.getAttribute('data-mode');
  Array.prototype.forEach.call(this.querySelectorAll('.segbtn'), function(x){ x.classList.toggle('active', x === b); });
});

grid.addEventListener('click', function(e){
  var actEl = e.target.closest('[data-act]'); if(!actEl) return;
  var card = e.target.closest('.rcard'); if(!card) return;
  var r = recents.filter(function(x){ return x.id == card.getAttribute('data-id'); })[0]; if(!r) return;
  var act = actEl.getAttribute('data-act');
  if(act === 'copy'){ copyText(r.text); toast('Copied to clipboard', true); }
  else if(act === 'resend'){ postText(r.text, r.mode, false).then(function(ok){ toast(ok ? 'Resent to Mac' : 'Resend failed', ok); }); }
  else if(act === 'trash'){ recents = recents.filter(function(x){ return x.id != r.id; }); render(); }
});

document.querySelector('.side').addEventListener('click', function(e){
  var go = e.target.closest('[data-go]'); if(!go) return;
  var id = go.getAttribute('data-go');
  var el = id === 'activity' ? grid : document.getElementById(id);
  if(el) el.scrollIntoView({ behavior:'smooth', block:'start' });
});

q.addEventListener('input', render);
sort.addEventListener('change', render);

syncSend(); render(); drawQR();
</script></body></html>"""


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = f"WhisperBridge/{VERSION}"
    default_mode = "type"

    def log_message(self, fmt, *args):
        # Quieter logging — we print our own
        pass

    def _json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _token_ok(self) -> bool:
        """Header-only auth — used by /send and /status."""
        if not AUTH_TOKEN:
            return True
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer ") and hmac.compare_digest(auth[7:].strip(), AUTH_TOKEN):
            return True
        return hmac.compare_digest(self.headers.get("X-WF-Token", ""), AUTH_TOKEN)

    def _console_token_ok(self) -> bool:
        """Console bootstrap only. A browser cannot set headers on a navigation,
        so GET / additionally accepts ?token=; the page strips it from the URL
        immediately via history.replaceState."""
        if self._token_ok():
            return True
        qs = parse_qs(urlparse(self.path).query).get("token", [""])[0]
        return hmac.compare_digest(qs, AUTH_TOKEN)

    def _host_ok(self) -> bool:
        raw = self.headers.get("Host", "")
        host = raw.rsplit(":", 1)[0].strip("[]").lower() if raw else ""
        return host in ALLOWED_HOSTS

    def do_GET(self):
        if not self._host_ok():
            self._json({"ok": False, "error": "bad host"}, 403)
            return
        path = urlparse(self.path).path
        if path == "/health":
            self._json({"ok": True})
        elif path == "/status":
            if not self._token_ok():
                self._json({"ok": False, "error": "unauthorized"}, 401)
                return
            self._json({
                "ok": True, "version": VERSION,
                "target_name": TARGET_NAME,
                "port": self.server.server_address[1],
                "token_set": bool(AUTH_TOKEN),
                "lan_ip": get_lan_ip(),
                "tail_ip": get_tail_ip(),
                "status": STATUS,
            })
        elif path == "/":
            if not self._console_token_ok():
                port = self.server.server_address[1]
                body = (
                    b'<!doctype html><meta charset="utf-8">'
                    b'<body style="font-family:system-ui;padding:40px;color:#1C1B19">'
                    b'<h2 style="margin:0 0 8px">401 &middot; Token required</h2>'
                    b'<p style="color:#6E6C66">Open the console with your token: '
                    b'<code>http://&lt;mac&gt;:' + str(port).encode() + b'/?token=YOUR_TOKEN</code></p>'
                )
                self.send_response(401)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            port = self.server.server_address[1]
            banner = (
                '<div style="margin:18px 24px 0;padding:11px 14px;border:1px solid var(--border);'
                'border-radius:12px;background:var(--green-soft);color:var(--green);font-size:13px;'
                'display:flex;gap:8px;align-items:center;flex-wrap:wrap">'
                '<b style="font-weight:700">Token required</b>'
                '<span style="color:var(--t2)">Safe for Tailscale / remote &middot; reachable on every interface at :'
                + str(port) + '.</span></div>'
            )
            lan = get_lan_ip()
            tail = get_tail_ip() or ""
            wb_json = json.dumps({
                "lan": lan, "tail": tail, "port": str(port),
                "token": AUTH_TOKEN or "", "name": TARGET_NAME,
            })
            html = (
                STATUS_PAGE
                .replace("Mac", TARGET_NAME)
                .replace("⌘V", PASTE_SHORTCUT)
                .replace("@@PORT@@", str(port))
                .replace("@@VERSION@@", VERSION)
                .replace("@@AUTH_BANNER@@", banner)
                .replace("@@WB_JSON@@", wb_json)
                .replace("@@QR_LIB@@", QR_LIB_JS)
                .encode()
            )
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
        else:
            self._json({"ok": False, "error": "not found"}, 404)

    def do_POST(self):
        if not self._host_ok():
            self._json({"ok": False, "error": "bad host"}, 403)
            return
        path = urlparse(self.path).path
        if path != "/send":
            self._json({"ok": False, "error": "not found"}, 404)
            return

        ctype = self.headers.get("Content-Type", "").split(";")[0].strip().lower()
        if ctype != "application/json":
            self._json({"ok": False, "error": "unsupported media type"}, 415)
            return

        if not self._token_ok():
            self._json({"ok": False, "error": "unauthorized"}, 401)
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            self._json({"ok": False, "error": "bad content-length"}, 400)
            return
        if length < 0 or length > MAX_BODY:
            self._json({"ok": False, "error": "payload too large"}, 413)
            return
        raw = self.rfile.read(length)

        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json({"ok": False, "error": "invalid JSON"}, 400)
            return

        if not isinstance(data, dict):
            self._json({"ok": False, "error": "JSON body must be an object"}, 400)
            return

        raw_text = data.get("text", "")
        if not isinstance(raw_text, str):
            self._json({"ok": False, "error": "text must be a string"}, 400)
            return
        text = raw_text.strip()

        mode = data.get("mode", self.default_mode)
        if not isinstance(mode, str):
            self._json({"ok": False, "error": "mode must be a string"}, 400)
            return
        if mode not in ("type", "clipboard", "append", "enter"):
            self._json({"ok": False, "error": "unsupported mode"}, 400)
            return

        if mode != "enter" and not text:
            self._json({"ok": False, "error": "empty text"}, 400)
            return

        source = data.get("source", "unknown")
        if not isinstance(source, str):
            self._json({"ok": False, "error": "source must be a string"}, 400)
            return
        source = source[:80]
        ts = time.strftime("%H:%M:%S")
        preview = text[:80] + ("…" if len(text) > 80 else "") if text else "(enter)"
        if LOG_CONTENT:
            print(f"  ← [{ts}] ({source}/{mode}) {preview}")
        else:
            print(f"  ← [{ts}] ({source}/{mode}) {len(text)} chars")

        enter_after = data.get("enter_after", False)
        if not isinstance(enter_after, bool):
            self._json({"ok": False, "error": "enter_after must be a boolean"}, 400)
            return
        ok = type_text(text, mode, enter_after=enter_after)
        if ok:
            notify("Whisper Bridge", f"Received {len(text)} chars" if text else "Return key pressed")
            chime()
            STATUS["count"] += 1
            STATUS["last_preview"] = text[:60] + ("…" if len(text) > 60 else "") if text else "(enter)"
            STATUS["last_source"] = source
            STATUS["last_mode"] = mode
            STATUS["last_ts"] = ts
        self._json({"ok": ok, "chars": len(text), "mode": mode})


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description=f"Whisper Flow Bridge — {TARGET_NAME} Receiver")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Listen port")
    parser.add_argument(
        "--clipboard-only", action="store_true",
        help="Only copy to clipboard, never auto-paste",
    )
    parser.add_argument(
        "--token", default=None,
        help="Override the shared secret (falls back to env, ~/.config/whisperbridge/token, or auto-generate).",
    )
    parser.add_argument(
        "--allow-host", action="append", default=[],
        help="Additional hostname to accept in Host header (repeatable).",
    )
    parser.add_argument("--log-content", action="store_true", help="Log dictation text to stdout (off by default).")
    parser.add_argument("--sound", default=None,
                        help="macOS system sound for the dictation chime (e.g. Tink, Pop, Glass). Default: Tink.")
    parser.add_argument("--no-sound", action="store_true", help="Disable the dictation chime.")
    args = parser.parse_args()

    global AUTH_TOKEN, SOUND_ENABLED, SOUND_NAME, LOG_CONTENT
    AUTH_TOKEN = resolve_token(args.token)
    LOG_CONTENT = args.log_content
    if args.no_sound or os.environ.get("WHISPERFLOW_NO_SOUND") == "1":
        SOUND_ENABLED = False
    _snd = args.sound or os.environ.get("WHISPERFLOW_SOUND")
    if _snd:
        SOUND_NAME = _snd

    if args.clipboard_only:
        BridgeHandler.default_mode = "clipboard"

    configure_allowed_hosts(args.allow_host)
    lan = get_lan_ip()
    tail = get_tail_ip()

    server = BridgeServer(("0.0.0.0", args.port), BridgeHandler)

    # Check if token was freshly generated (file didn't exist before)
    generated = not os.path.exists(TOKEN_FILE) or os.path.getsize(TOKEN_FILE) == 0
    if generated and AUTH_TOKEN:
        print(f"\n  ╔══════════════════════════════════════════════╗")
        print(f"  ║  Token generated & saved to:                 ║")
        print(f"  ║  {TOKEN_FILE:<44}║")
        print(f"  ║  Token: {AUTH_TOKEN[:32]:<42}║")
        print(f"  ╚══════════════════════════════════════════════╝\n")

    print(f"""
  ╔══════════════════════════════════════════════╗
  ║       Whisper Flow Bridge — Receiver         ║
  ╠══════════════════════════════════════════════╣
  ║  Listening on 0.0.0.0:{args.port:<23}║
  ║  Mode: {"clipboard-only" if args.clipboard_only else "type (⌘V paste)":<37}║
  ║  Auth: token (remote-safe){'':<20}║
  ║  LAN : http://{lan}:{args.port:<19}║
  ║  Tail: {f"http://{tail}:{args.port}" if tail else "not connected":<35}║
  ╚══════════════════════════════════════════════╝
""")
    print("  Waiting for text from Android…\n")

    start_allowed_hosts_refresher()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
