# Whisper Bridge for Windows

The Windows receiver uses the built-in PowerShell clipboard API and Windows Forms `SendKeys` to paste into the focused field. It requires Python 3 but no Python packages.

## Install

Extract the Windows release ZIP, open PowerShell in that folder, and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-server\install.ps1
```

The installer copies the receiver to `%LOCALAPPDATA%\WhisperBridge`, registers current-user login startup, and opens the pairing console. If Windows Firewall prompts for Python access, allow it only on Private networks.

Install Tailscale on Windows and Android for encrypted remote use. Do not expose TCP port `9877` with public port forwarding or Tailscale Funnel.
