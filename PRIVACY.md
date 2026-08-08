# Privacy Policy

Last updated: August 7, 2026

Whisper Bridge is an open-source, peer-to-peer utility. The project does not operate a cloud service, user account system, analytics service, advertising network, or telemetry endpoint.

## Data handled

- Dictated or pasted text is sent directly from your phone or tablet (Android or iOS) to the computer address selected by the user.
- Connection profiles contain a computer name, host address, port, and authentication token. They are stored locally in the app's private storage (Android private storage; iOS Keychain for tokens).
- The desktop receiver stores its authentication token locally in the current user's protected configuration directory.
- The receiver keeps a short in-memory status preview for the local console. Dictation content is not written to logs unless the user explicitly starts the receiver with `--log-content`.

## Network transport

Whisper Bridge uses HTTP between devices. Use Tailscale for encrypted remote transport or a trusted private LAN. Do not expose the receiver to the public internet.

## Third parties

Whisper Bridge does not send data to the project maintainer. The Android app may be used alongside Wispr Flow and Tailscale, which have their own privacy practices and policies.

## Deletion

Uninstalling the mobile app removes its private profile data. Desktop tokens can be removed by deleting the platform-specific Whisper Bridge configuration directory after stopping the receiver.

Questions can be opened in the repository's GitHub Discussions or Issues without including dictated text, tokens, or private network addresses.
