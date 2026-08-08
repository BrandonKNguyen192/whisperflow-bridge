# Test Coverage

## Existing Coverage

| Use case | Rule and expected deny case | Evidence | Status |
|---|---|---|---|
| Enter request | Empty text is accepted only for Enter | `mac-server/test_server.py` | Existing automated |
| Request schema | Non-string text and empty Type are `400` | `mac-server/test_server.py` | Existing automated |
| Host initialization | LAN, Tailscale, local, and explicit hosts are accepted | `mac-server/test_server.py` | Existing automated |
| Login upgrade | Legacy plist token migrates; current plist has none | `mac-server/test_launch.py` | Existing automated |
| Ubuntu input selection | Wayland/X11 paste and Enter commands; missing tools fail | `ubuntu-server/test_backend.py` | Existing automated |
| Windows input selection | Clipboard then in-process Ctrl+V paste; Enter via SendInput; mouse via SendInput | `windows-server/test_backend.py` | Automated + live Notepad round-trip on Beelink (v1.3.0) |
| HTTP security | Auth, no CORS, Host, content type, size, token permissions | `mac-server/verify_security.sh` | Existing guarded live |
| Android quality | Lint and debug assembly | `.github/workflows/ci.yml` | CI-required after merge |
| Release identity | APK metadata and signing certificate checked locally | `build.sh`, `apksigner` verification | Existing manual |

## Proposed Tests

| Use case | Expected behavior | Type |
|---|---|---|
| Ubuntu Wayland install | systemd service starts; `ydotool` pastes into GNOME focused field | Guarded live on Ubuntu |
| Ubuntu X11 install | `xclip`/`xdotool` paste and Return work after login | Guarded live on Ubuntu |
| Windows install | Run entry starts receiver; firewall/private network and SendInput work; no console windows spawn | Verified live on Beelink (v1.3.0) |
| Android profile QR | Mac/Ubuntu/Windows names survive QR parse and switching | Automated Android unit/instrumentation |
| Mac package from clean account | installer survives quarantine/Open flow and Accessibility grant | Guarded live on macOS |
| Signing continuity | CI-signed APK installs as an update over locally signed APK | Guarded device test |

## Gaps

1. **High:** Ubuntu has not yet been exercised on a physical target machine; command construction is tested but OS policy can still block input. Windows was verified live on hardware (v1.3.0).
2. **High:** The Mac ZIP is not Apple-notarized, so first-run Gatekeeper behavior is not automated.
3. **Medium:** No Android instrumentation test covers profile persistence, QR scanning, or responsive layout.
4. **Medium:** CI does not currently boot platform VMs and test login persistence.
