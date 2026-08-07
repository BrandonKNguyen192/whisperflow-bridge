# Security Policy

## Supported version

Security fixes are provided for the latest GitHub release.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting or Security Advisory flow for this repository. Do not open a public issue containing authentication tokens, dictated text, private network addresses, or exploit details.

## Security model

The desktop receiver can paste text and press Return in whichever application has focus. Treat access to the receiver as keyboard access to that computer.

- Every send and status request requires a randomly generated bearer token.
- Tokens are stored locally with owner-only permissions where the platform supports POSIX modes.
- The server validates `Host`, requires JSON, limits request sizes, and does not enable CORS.
- Android share intents require a confirmation tap, and browser pairing links require explicit confirmation.
- Dictation text is redacted from logs by default.

## Safe deployment

Use Tailscale for encrypted remote use. A trusted private LAN is supported, but HTTP traffic on that LAN is not encrypted. Never use public port forwarding, Tailscale Funnel, or a public reverse proxy for the receiver.

Keep the authentication token secret. If it may have been exposed, stop the receiver, replace the token file with a new random value, update paired Android profiles, and restart the receiver.
