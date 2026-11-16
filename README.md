# Cino Matrix — SwiftUI starter

A native iOS/iPadOS SwiftUI Matrix client prototype inspired by the supplied screenshot.

## Included
- Password login against a Matrix homeserver
- Basic `.well-known/matrix/client` discovery when the homeserver field is not a full URL
- Joined-room list
- Live `/sync` loop and basic text-message timeline
- Send `m.room.message` text events
- iPad-friendly split navigation and dark UI

## Not included yet
This is an early prototype, not a production-ready Matrix client. It does **not** implement end-to-end encryption (E2EE), key backup, device verification, SSO/OAuth login, media uploads, replies, reactions, room creation/joining, push notifications, or offline storage. Encrypted rooms will not display their message contents. Do not rely on it for private or sensitive conversations.

## Run in Xcode
1. On a Mac, open Xcode and create **iOS → App** with the SwiftUI interface.
2. Set the deployment target to iOS 17 or newer.
3. Replace the generated app Swift file with `ContentView.swift` from this folder. Keep only one `@main` app entry point.
4. Build and run on an iPhone or iPad.
5. Sign in with your Matrix ID (for example `@name:matrix.org`), password, and homeserver URL (for example `https://matrix.org`).

The prototype keeps the access token in memory only; signing out or terminating the app clears the session. It uses HTTPS if you enter an HTTPS homeserver.

## API
Uses the Matrix Client-Server API login, `/sync`, and room send endpoints. See the [Matrix specification](https://spec.matrix.org/latest/client-server-api/).
