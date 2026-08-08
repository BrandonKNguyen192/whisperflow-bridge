# Whisper Bridge for Windows

The Windows receiver injects input fully in-process through the Win32 API
(ctypes → user32/kernel32): typed text is written to the clipboard and pasted
with a synthesized Ctrl+V, Enter is a synthesized VK_RETURN, and mouse
actions are `SendInput` events. No PowerShell or console windows are spawned
at runtime — the old backend flashed a visible PowerShell window per keystroke,
which stole focus and blocked pasting. Requires Python 3.12+ with no Python
packages.

## Install

Extract the Windows release ZIP, open PowerShell in that folder, and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-server\install.ps1
```

The installer copies the receiver to `%LOCALAPPDATA%\WhisperBridge`, registers
start-at-sign-in (registry Run key, or a `WhisperBridge` scheduled task), and
opens the pairing console. If Windows Firewall prompts for Python access, allow
it only on Private networks.

Python 3.12+ must be installed first — `winget install --id Python.Python.3.12 -e
--scope machine` works. The installer uses `python.exe`/`pythonw.exe` from PATH;
if you have multiple Python installs (e.g. a broken `uv` shim shadowing the
real one), point PATH at the real installation before running the installer.

## Behavior

- **Typing** — clipboard + Ctrl+V (atomic, verbatim; unicode-safe). A
  per-character `SendInput KEYEVENTF_UNICODE` fallback exists in
  `backend._type_unicode` but is not the default because some apps mangle
  rapid unicode key events.
- **Clipboard / Append** — clipboard-only modes via the Win32 clipboard API.
- **Enter** — `VK_RETURN` press.
- **Mouse** — `SendInput` move/scroll/click/drag events, same deltas as the
  macOS and Ubuntu backends.
- **No windows, ever.** The server process holds no console; input goes
  straight to whatever window is focused on the interactive desktop.

## Tests

`test_backend.py` (10 tests) runs on the Windows machine:

```powershell
python -m unittest test_backend -v
```

It covers clipboard round-trip, Ctrl+V construction, Enter, append, unicode
surrogate handling, and mouse event sequences.

Install Tailscale on Windows and Android for encrypted remote use. Do not
expose TCP port `9877` with public port forwarding or Tailscale Funnel.
