# Ship as a native macOS app, local-first, with no backend

Pregame ships to the public as the existing native Swift macOS app. All audio work (analysis, stretching, stems, rendering) runs on the user's Mac. There is no server-side processing, and "cloud" means only free static hosting: the download, the update feed and the website. We rejected two alternatives:

- **A cross-platform rewrite (Tauri, Electron, or a Windows port).** It would throw away a fast Swift engine built on Core ML and Accelerate.
- **A web app with a cloud backend.** Stem separation on cloud GPUs isn't free at scale. Worse, storing and processing users' commercial music on our servers creates copyright and DMCA exposure that a free project can't carry.

## Consequences

- **Windows is out of scope** until this is revisited.
- **Apple Silicon only, macOS 15 or later.** Intel Macs are out: they have no Neural Engine, so stems would be slow, and the bundled ONNX Runtime and TagLib builds are arm64 only. Features specific to macOS 26 must be gated with `#available`.
  - _Amended 2026-11-18:_ the first decision was macOS 14. GitHub retired its macOS 14 runners in November 2026. We only support versions we can test, so the minimum is the oldest macOS that CI runs on.
- **Builds are not notarized for now:** no Apple Developer Program ($99 a year), by choice. The first time users open the app, they must allow it in System Settings › Privacy & Security › "Open Anyway". On macOS 15 and later, right-click › Open no longer bypasses Gatekeeper. The download page has to walk users through this.
- **Every build is signed with one self-signed code-signing certificate, not ad hoc.** Ad-hoc signing ties the app's identity to each build's hash, so macOS would drop folder permissions after every update. The certificate's private key must be backed up: losing it changes the identity for every user.
- **No backend of our own, but two opt-in services.** _Amended 2026-11-23 (#12):_ if the Mix Host agrees on first launch, crash reports go to Sentry and a few anonymous usage events to TelemetryDeck, both hosted services with free tiers. Nothing is sent without consent, never audio, titles, file names or paths; [docs/privacy.md](../privacy.md) lists every field. The app gains the outgoing-network entitlement for this.
- **Updates come through Sparkle 2,** using an EdDSA-signed appcast and DMGs on GitHub Releases. Sparkle removes the quarantine flag from updates it installs, so users approve "Open Anyway" only once.
