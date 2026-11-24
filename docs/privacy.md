# What Pregame sends

Pregame works entirely on your Mac. Your music, its analysis and your Mixes never leave it.

On first launch, Pregame asks once whether to share **anonymous crash reports** and **usage data**: tick what you're happy to share, then "No thanks" or "Share selected", which carry equal weight. You can change either one at any time in **Settings › Privacy**. Until you say yes, Pregame doesn't start the crash reporter and sends nothing. Builds without the keys described under [For maintainers](#for-maintainers), such as `swift run`, never ask and never send.

Usage data never contains Track titles, artists, file names, folder names, paths, Mix names or your Mac's name: every field is listed below. Crash reports are scrubbed of paths and file names before they're sent; see their limits below.

## Crash reports (Sentry)

If Pregame crashes or hangs, the next launch sends a report to [Sentry](https://sentry.io). A report contains:

- the stack trace: function names, and the name of each binary, such as `Pregame` or `AppKit`
- the error's type and message, with any path replaced by `<path>` and any audio, Mix or playlist file name replaced by `<file>`
- the app version, and the technical details Sentry collects about macOS and the Mac: its model (such as `Mac16,10`), memory, free disk space, time zone and language

Before a report leaves your Mac, Pregame removes your Mac's name, the folder the app runs from, and any user ID. The scrubber recognises paths, and file names by their extension (audio files, Mixes, playlists, CSV and cue sheets). It can't recognise a bare title with no extension in an error message, so Pregame's own error messages don't include titles. Sentry's other features are switched off: breadcrumbs, performance tracing, network and file tracking, session tracking and logs. The code is in [`CrashScrubber.swift`](../Sources/PregameApp/Telemetry/CrashScrubber.swift) and [`CrashReports.swift`](../Sources/PregameApp/Telemetry/CrashReports.swift).

## Usage data (TelemetryDeck)

Pregame sends the events below to [TelemetryDeck](https://telemetrydeck.com), each as soon as it happens. Pregame builds each request itself, in [`Telemetry.swift`](../Sources/PregameApp/Telemetry/Telemetry.swift). It doesn't use TelemetryDeck's SDK, so the fields listed here are everything that's sent.

### Events

| Event | When | Its own fields |
|---|---|---|
| `App.launched` | Pregame starts | none |
| `Mix.created` | An empty Mix gets its first Tracks, added or imported from a Harmonize run | none |
| `Tracks.added` | Tracks are added to a Mix | `count`: how many |
| `AutoPick.used` | Auto-pick chooses the Tracks for a Mix (sent once Auto-pick ships) | none |
| `Harmonize.run` | A Harmonize result is applied to a Mix (a run that's closed without applying isn't counted) | none |
| `Export.finished` | A Mix finishes exporting | `format`: `wav`, `mp3` or `wav+mp3`; `mixMinutes`: the Mix's length, in whole minutes; `exportSeconds`: how long the export took, in whole seconds |
| `Track.analysed` | Pregame finishes analysing a Track for the first time | `analysisSeconds`: how long it took, to 0.1 s; `trackMinutes`: the Track's length, in whole minutes |

### Fields on every event

| Field | Example | What it is |
|---|---|---|
| `appVersion` | `1.0` | Pregame's version |
| `buildNumber` | `12` | Pregame's build |
| `chip` | `M4 Pro` | The Mac's chip |
| `memoryGB` | `24` | The Mac's memory, in whole gigabytes |

### How each event is sent

Each event is one signal in TelemetryDeck's format. Besides the event's name (`type`) and the fields above (`payload`), a signal has:

| Field | What it is |
|---|---|
| `appID` | Which TelemetryDeck app the signal belongs to: Pregame's, the same for everyone |
| `clientUser` | A random ID created for this install the first time an event is sent, kept in Pregame's settings and only ever sent as a SHA-256 hash. TelemetryDeck hashes it again with a salt before storing it. It lets the dashboard count installs without knowing who anyone is |
| `sessionID` | A random ID, new each time Pregame starts |
| `floatValue` | The event's main number, if it has one: `count`, `exportSeconds` or `analysisSeconds` |
| `receivedAt` | When the event happened, to the second |
| `isTestMode` | `true` for development builds, so their events stay out of the real numbers |

TelemetryDeck also sees the IP address the request comes from, like any web server. It says it doesn't store IP addresses.

## For maintainers

- The Sentry DSN and the TelemetryDeck app ID go in `scripts/Info.plist`, as `PregameSentryDSN` and `PregameTelemetryDeckAppID`. Neither is secret: either one only lets someone submit events. Leave a key empty and that half is off: its toggle in Settings is disabled, and if both are empty there's no prompt.
- In the Sentry project's settings, turn on "Prevent storing of IP addresses". Sentry sees the IP a report comes from, like any web server.
- To add an event: add a case to `TelemetryEvent`, add it to `TelemetryEvent.examples`, and list it here. `PrivacyDocsTests` fails until every event and field appears in this document.
- `TelemetryTests` checks that nothing is started or sent without consent, and checks the exact fields of each signal. `CrashScrubberTests` checks what's removed from a crash report.
