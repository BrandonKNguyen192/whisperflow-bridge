# iPhone / iPad Walkthrough

Whisper Bridge for iOS turns your iPhone or iPad into a remote compose pad,
trackpad, and air mouse for a Mac, Ubuntu, or Windows receiver.

The iOS client is currently a signed preview build targeting iOS 26 and later.
It uses the same receiver protocol as Android.

## What You Need

- An iPhone or iPad running iOS/iPadOS 26 or later.
- A signed Whisper Bridge iOS preview build.
- A Mac, Ubuntu, or Windows computer running the Whisper Bridge receiver.
- Tailscale installed and signed in on both devices for remote use.

## 1. Install The Receiver

Install the matching desktop package from [GitHub Releases](https://github.com/BrandonKNguyen192/whisperflow-bridge/releases):

- **macOS:** run `mac-server/install.command` and approve Accessibility.
- **Ubuntu:** run `./ubuntu-server/install.sh`.
- **Windows:** install Python 3.12+, then run `windows-server\\install.ps1` from PowerShell.

Open `http://localhost:9877` on the computer. Keep the receiver running while
you pair and use the phone.

## 2. Connect Tailscale

1. Install Tailscale on the iPhone/iPad and the computer.
2. Sign in to the same tailnet on both devices.
3. Confirm both devices show as connected.

Tailscale is optional on a trusted home Wi-Fi network. Do not expose port
`9877` with public port forwarding or Tailscale Funnel.

## 3. Pair The iPhone

1. Open Whisper Bridge and tap the gear to open **Settings**.
2. Tap **Scan** and scan the Tailscale QR shown by the receiver console.
3. If scanning is unavailable, use **Paste pairing link** instead.
4. Tap **Test**, then **Save** when the receiver reports a connection.

The pairing link carries the private host, port, and token. You do not need to
type those sensitive details by hand.

## 4. Compose And Send

1. Choose a computer profile from the pills at the top of Compose.
2. Type or paste text into the compose field.
3. Tap **Type** to paste into the focused field on the computer.
4. Tap **Enter** to send Return, or enable **Enter after** before typing.
5. Tap **Copy** to update the computer clipboard without pasting.

Click the destination text field on the computer before tapping **Type**.

## 5. Use The Trackpad

- **Drag:** move one finger across the trackpad surface.
- **Tap:** click the focused pointer location.
- **Hold:** press and hold to drag an item.
- **Two fingers:** scroll the computer.
- **Buttons:** use Click, Right, Double, Up, and Down for direct actions.

## 6. Use Air Mouse

1. Scroll to the bottom of the Trackpad card.
2. Press and hold **Hold for air mouse**.
3. Tilt the phone to steer the cursor.
4. Release the button to stop gyro control.

Tune **Air mouse sensitivity** or enable **Invert air mouse direction** in
Settings if the motion feels too fast or reversed.

## Troubleshooting

- **Test fails:** verify Tailscale is connected and re-scan the Tailscale QR.
- **Text does not appear:** click the destination field first and check receiver permissions.
- **Air mouse does not move:** keep holding the button and confirm the receiver has mouse permissions.
- **Pairing is stale:** update the profile by scanning a fresh QR or replacing its token.

For the printable version, see [iPhone walkthrough PDF](../output/pdf/whisper-bridge-iphone-walkthrough.pdf).
