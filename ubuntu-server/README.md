# Whisper Bridge for Ubuntu

The Ubuntu receiver accepts authenticated text from the Whisper Bridge Android app and sends it to the currently focused field.

## Install

Extract the Ubuntu release ZIP, then run:

```bash
./ubuntu-server/install.sh
```

The installer adds the required clipboard/input tools, copies the receiver to `~/.local/share/whisperbridge`, and enables a user-level `systemd` service.

Ubuntu Wayland uses `wl-clipboard` and prefers `ydotool`; X11 uses `xclip` and `xdotool`. Some Wayland configurations require the packaged `ydotool` system service to be enabled before simulated keypresses are permitted.

Pair at `http://localhost:9877`. For remote use, install Tailscale on Ubuntu and Android, then choose the Tailscale QR in the console.

## Commands

```bash
systemctl --user status whisperbridge
journalctl --user -u whisperbridge -f
systemctl --user restart whisperbridge
python3 ~/.local/share/whisperbridge/ubuntu-server/launch.py --uninstall-login
```

If Ubuntu's firewall blocks the phone, allow TCP port `9877` only on your trusted LAN or Tailscale interface. Do not expose this receiver through a public port forward or Tailscale Funnel.
