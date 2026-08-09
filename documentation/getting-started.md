# Getting Started

Whisper Bridge lets text dictated on an Android phone land in the currently
focused text field on a Mac, Ubuntu, or Windows computer. It connects the
following three tools:

1. [Wispr Flow](https://wisprflow.ai/) turns speech into text on your Android phone.
2. [Whisper Bridge](../README.md) sends that text to your computer.
3. [Tailscale](https://tailscale.com/download) securely connects your phone and computer from anywhere.

Whisper Bridge is an independent, unofficial companion. It does not include a
Wispr Flow subscription or a Tailscale account.

## What You Need

- An Android phone running Wispr Flow and Whisper Bridge.
- A Mac, Ubuntu, or Windows computer running the Whisper Bridge receiver.
- Tailscale installed and signed in on both devices for remote use. A trusted
  shared Wi-Fi network also works for local-only use.

## 1. Install Wispr Flow On Android

1. Visit [wisprflow.ai](https://wisprflow.ai/) on your Android phone and install Wispr Flow.
2. Sign in to Wispr Flow and finish its onboarding.
3. Dictate a short note to confirm it produces text and exposes Android's Share action.

Whisper Bridge receives text from Wispr Flow's Android share sheet. You can
also paste or type directly into Whisper Bridge.

## 2. Install Tailscale On Both Devices

Tailscale is strongly recommended whenever the phone and computer are not on a
trusted home network. It avoids router port-forwarding and encrypts the network
path between your devices.

1. Install [Tailscale for Android](https://tailscale.com/download/android) on the phone.
2. Install [Tailscale for macOS, Windows, or Linux](https://tailscale.com/download) on the computer.
3. Sign in to the same Tailscale account or tailnet on both devices.
4. Confirm both devices show as connected in Tailscale.

Do not enable Tailscale Funnel for Whisper Bridge. The receiver should remain
private to your tailnet.

## 3. Install Whisper Bridge

1. Download the Android APK and the receiver ZIP for your computer from the
   project's [GitHub Releases](https://github.com/BrandonKNguyen192/whisperflow-bridge/releases).
2. On Android, allow the browser or Files app to install the downloaded APK when
   Android asks, then open Whisper Bridge.
3. On the computer, install the receiver:
   - **macOS:** double-click `mac-server/install.command`.
   - **Ubuntu:** run `./ubuntu-server/install.sh`.
   - **Windows:** install Python 3.12+ (`winget install --id Python.Python.3.12 -e --scope machine`), then run `windows-server\\install.ps1` from PowerShell.
4. Keep the receiver running. On macOS, approve the requested Accessibility
   permission so it can paste into the focused text field. On Windows, the
   receiver injects input in-process — you will not see any console windows
   (if PowerShell windows flash when you type, the installed copy is older
   than v1.3.0; reinstall the latest ZIP).

## 4. Pair The Phone And Computer

1. On the computer, open `http://localhost:9877` in a browser.
2. Choose the **Tailscale** pairing QR in the receiver console.
3. In Whisper Bridge on Android, tap the gear icon, then **Scan**. Scan the QR.
4. Tap **Test**. A successful test confirms the host, token, and connection.
5. Tap **Save**, then return to Compose.

If scanning does not work, select **Paste pairing link** in Settings and paste
the pairing link copied from the receiver console. Do not type a public address
or expose port `9877` to the internet.

## 5. Dictate And Type

1. In Wispr Flow, dictate your message.
2. Use Android's Share action and choose **Whisper Bridge**.
3. Choose the computer profile at the top of Whisper Bridge.
4. Put the cursor in any text field on that computer.
5. Tap **Type** to paste the text, **Enter** to send Return, or **Clipboard** to
   copy the text on the computer without pasting it.

For a second computer, add another profile in Whisper Bridge and pair it with
that computer's QR. Switch profiles from the Compose screen before sending.

## 6. Use The Trackpad

The Mouse card sits below Compose and turns your phone into a remote pointer:

- **Move:** drag one finger across the trackpad surface.
- **Click:** tap the surface for a left click. **Left**, **Right**, and
  **Double** send those button presses directly.
- **Drag:** press and hold on the surface to drag an item, or tap **Drag** to
  keep the button held.
- **Scroll:** move two fingers to scroll, or use **Scroll up** / **Scroll down**.

Tune **Trackpad speed**, **Tap to click**, and **Natural scrolling** in
Settings. The receiver needs mouse permissions on the computer (macOS
Accessibility) before cursor control works.

## 7. Use Air Mouse

1. Scroll to the bottom of the Mouse card.
2. Press and hold **Hold for air mouse**.
3. Tilt the phone to steer the cursor.
4. Release the button to stop gyro control.

If the motion feels too fast or reversed, adjust **Air mouse sensitivity** or
enable **Invert air mouse direction** in Settings.

## Personalize

Settings also controls the look of the app: Light, Earth, Pure OLED Black, and
System themes, plus a preset or custom RGB accent color. The frosted-glass
surfaces and drifting ambient color follow the theme and accent you choose.

## Troubleshooting

- **Test fails:** Verify Tailscale is connected on both devices, the receiver is
  running, and the phone profile uses the Tailscale QR or copied pairing link.
- **The text does not appear:** Click the destination text field first. On macOS,
  enable Accessibility for the receiver or terminal in System Settings.
- **The cursor does not move:** Click a destination field first and confirm the
  receiver has mouse permissions. Keep holding **Hold for air mouse** while
  tilting.
- **Wispr Flow is missing from the flow:** Finish Wispr Flow setup, dictate once,
  then use Android's Share action. Whisper Bridge also accepts direct paste.
- **Share sheet lacks Whisper Bridge:** Reinstall the APK and look under
  Android's **More** menu in the share sheet.

For receiver and security details, return to the [main README](../README.md).
