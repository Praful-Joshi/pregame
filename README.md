# Pregame

**Party-ready Mixes from your own music, on your own Mac. Free and open source.**

Pregame is for the **Mix Host**: someone throwing a house party who wants the music to flow — no dead air, no jarring jumps — without learning to DJ. Add a folder of music you own, press **Harmonize**, and Pregame orders the Tracks for key and tempo, then joins each to the next with a beat-matched Transition. Listen, tweak any Transition by ear, and export the whole Mix as one file to play from a phone, a USB stick or a speaker.

- **Local and private:** no account, no backend, no streaming service. Your music never leaves your Mac. Crash reports and a few anonymous usage events are sent only if you say yes on first launch, and never include song titles, file names or paths: see [what's sent](docs/privacy.md).
- **Free:** GPL-3.0, with no paid export or subscription.
- **Native:** a SwiftUI app for macOS.

> **Status:** early. The engine (analysis, Harmonize, the Transition editor, stems and export) is working; v1 work is tracked in [issue #2](https://github.com/Praful-Joshi/pregame/issues/2). Pregame used to be called Harmonizer, and its data folders keep that name for now (`~/Library/Application Support/Harmonizer`, `~/Library/Caches/Harmonizer`).

## System requirements

- A Mac with **Apple Silicon** (M1 or later). Intel Macs are not supported.
- **macOS 15 Sequoia or later.**
- Music files you own: MP3, M4A/AAC, FLAC, WAV or AIFF. Streaming services can't be used.

## Building from source

You need Xcode 26 or later (Swift 6) and [Homebrew](https://brew.sh).

```sh
brew install taglib rubberband libsamplerate lame mpg123
scripts/fetch-vendor.sh          # downloads ONNX Runtime and verifies its checksum
swift build                      # debug build
swift test                       # the test suite: a few minutes, no external tools needed
scripts/make-signing-identity.sh ~/Documents/pregame-signing.p12   # once: the signing certificate and a backup
scripts/build-app.sh --install   # release build of Pregame.app into /Applications
```

`build-app.sh` signs the app with one self-signed certificate, so macOS keeps the folder access you grant it across rebuilds. Create the certificate once, and keep its backup out of the repo; see [docs/signing.md](docs/signing.md).

The app updates itself with Sparkle from an EdDSA-signed appcast on GitHub Releases. Pushing a version tag builds, signs and publishes a release once the maintainer approves it; see [docs/releasing.md](docs/releasing.md) and [docs/updates.md](docs/updates.md).

`build-app.sh` also bundles the Demucs stem model (`Models/htdemucs.onnx.data`, 161 MB), which is too big for the repo. `scripts/fetch-vendor.sh --model` downloads it and checks its checksum (or rebuild it as described in [`scripts/stems/README.md`](scripts/stems/README.md)); everything except stem separation works without it.

Every pull request and every push to `main` is built and tested by [GitHub Actions](.github/workflows/ci.yml). More developer detail is under [Developing](#developing).

## Licence

Pregame is free software under the [GNU General Public License v3.0](LICENSE). It builds on Rubber Band (GPL), Queen Mary DSP (GPL), TagLib (LGPL), ONNX Runtime (MIT), Demucs (MIT) and others; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

# How it works

## Transitions, timeline and export

**Window layout**

- **Sidebar (left, ⌃⌘S to hide):** the playlist.
- **Toolbar:** the one transport (⏮ ▶ ⏭, clock, Loop, Follow, Lead) plus Harmonize, Compare and Export.
- **Top right:** the whole-mix timeline. Drag the divider under it to resize.
- **Bottom right:** the transition editor.

**Playback (one transport for everything)**

- **Output:** use **Playback › Output Device** (or Settings › Audio) to pick where sound goes.
  - **System Default** follows macOS: plug in headphones or connect speakers and playback moves over by itself, without stopping.
  - A device you choose is remembered. When it isn't connected, the default is used until it comes back.

- **Space** plays and pauses the mix. The timeline and the editor share one playhead.
- **⏮ / ⏭ (⌘← / ⌘→)** jump to the previous or next transition's lead-in.
- **Follow** (on by default): while playing, the editor slides to the next transition once the current one, plus its echo tail, has passed. The next one is prepared in the background, so the switch is instant, and playback isn't interrupted.
- **Pin:** only the pin button (in place of the Follow button) pins the editor to one transition.
- **Clicking:** clicking a transition (timeline, playlist pill, or **⌥← / ⌥→**) jumps the playhead to its lead-in, and Follow carries on from there.
- **Clicking a song** in the playlist moves the playhead to where that song starts in the mix, playing or paused, and centres its card on the timeline.
- **The song at the playhead** stays highlighted in the playlist, which scrolls to keep it in view.
- **Loop (L)** loops the current transition and its lead bars on the shared playhead.

**Transition editor**

- **Smart bar, line 1:** the two songs with their keys, the harmonic label, and **Fix key**, **Reset** and the **lock**.
- **Smart bar, line 2:**
  - The presets: Long Blend, Smooth Blend, Filter Blend, Echo Out and Quick Cut (**⌥1–⌥5**). Each transition starts on an automatic preset chosen from its harmonic label and BPM gap.
  - Value chips: length, sync, Mix on, incoming delay and loops. Click a chip for its menu; scroll over a chip to step its value. **+** adds a loop or a delay.
- **Moving the transition:**
  - Drag the box's left or right edge to change the length.
  - Drag inside the box to move the transition along the outgoing track.
  - Drag the incoming waveform sideways to change where that track enters.
  - **Incoming delay:** drag the incoming box's left edge to the right to start the incoming song later, shown as a hatched gap.
    - With sync, it moves in whole beats, so the songs stay on the beat.
    - With Echo Out or Quick Cut, it's a real gap: the echo tail, then silence. **⌘** places it freely.
- **Lanes:** Volume, Bass, Mid, High, Filter (up = high-pass, down = low-pass, adjustable resonance) and Echo (delay, feedback). Each lane shows the outgoing track as a solid orange line and the incoming track as a dashed blue line.
  - The lane's shape menu appears when you hover its name.
  - Drag points to move them, click a line to add a point, and double-click a point to delete it.
  - **⌥-drag** bends a segment. Points snap to ¼ beat; hold **⌘** to place freely. **?** lists the gestures.
- **Lock (🔒):** freezes a hand-finished transition.
  - Its exact positions are saved, so re-analysis, section edits, Mix on changes and Harmonize can't move it. It warns ⚠️ if it no longer fits.
  - Its two songs stay together: dragging either one moves the pair or chain, and Harmonize keeps the chain intact.
  - The canvas is read-only until you unlock it.
- Curve edits are heard immediately while playing. Changing the length, mix points or tempo re-stretches the window in well under a second.
- Every edit can be undone (⌘Z).

**Timeline**

- The whole mix is shown as track blocks on two alternating rows, with transitions between them.
- The playing song is highlighted, and hovering a block shows its title, key and BPM.
- A ring counts down to the next transition.
- Click a transition to edit it. Click anywhere else to play from there. Drag a track block sideways to move the transition into it (in bars).
- **Zoom:** pinch or **⌘-scroll**. It opens at about 12 minutes per screen; the corner button fits the whole mix.
- **While playing**, the timeline scrolls to keep the playhead in view. After you scroll by hand, it waits a few seconds before following again.

**Export (⌘E)**

- Formats: 24-bit/48 kHz WAV and/or 320 kbps MP3.
- What to export: the full set, a range of tracks, or transitions only (each with lead bars either side).
- Output: a folder containing `mix.wav`, `mix.mp3`, `tracklist.txt`, `mix.cue` and `transitions.json`.
- The size is estimated against free disk space before starting.
- A 105-minute, 46-track set exports in about 4 minutes.

**How the audio works**

- One engine plays the transition preview, the timeline and the export, so the preview sounds the same as the export.
- **Sample rate:** tracks are decoded at 48 kHz.
- **Tempo:** synced windows glide beat by beat with Rubber Band, keeping the pitch. Both tracks stay within ~5 ms of each other.
- **Effects:** each track runs through one continuous 3-band EQ (Linkwitz-Riley 4th-order crossovers at 200 Hz / 2.5 kHz), resonant filter and echo chain, followed by a look-ahead limiter. Joins between stretched and untouched audio are crossfaded over 10 ms.
- **Loudness:** level matching uses each track's measured loudness (BS.1770-style), plus optional per-track trims.

## Song structure, cues, loops and key shift

**Sections:** each track is split into Intro, Build, Drop, Break and Outro, shown as coloured strips under the waveforms on the timeline and in the editor.

- Detected from per-bar levels (bass, full band, highs): changes are found on the phrase grid, and labelled by energy and position. A confidence score goes with it.
- **Bar 1** is the earliest downbeat. Its phase comes from where the low end comes in (drops land on downbeats).

**Correcting:** in **Get Info (⌘I)**:

- drag a section boundary
- right-click to relabel, split, merge or set a hot cue
- **Bar 1 ◀ ▶** moves the downbeat by a beat
- **Play from marker** checks it by ear

Corrections, bar 1 and cues are stored with the file's analysis, so every project sees them. They survive re-analysis, and every change can be undone.

**Mix on** (editor; project **Default** menu, or per transition):

| Mode | Outgoing track | Incoming track |
|---|---|---|
| **Bars** | Leaves on the last 8-bar step | Enters at bar 1 |
| **Phrase** | Same, on the detected phrase grid | Enters at its first phrase |
| **Intro / Outro** | Leaves at its outro (or last break) | Enters at the start of its intro |
| **Song Structure** (default) | Leaves at its outro (or last break) | Its first drop lands as the transition ends |

When a track's structure confidence is under 0.5, the structure modes fall back to Phrase and show a warning.

**Hot cues:** 8 per track. Set them in Get Info; they show as yellow flags everywhere.

**Loops:** in the editor, **Outro loop** (outgoing track) and **Intro loop** (incoming track) are 1–16 bars played 2–9×. The outro loop repeats the start of the outro, and the intro loop the first bars. The mix gets longer to fit.

**Key shift:**

- ±6 semitones per track, via Rubber Band pitch shifting. It takes about 4 s per track the first time it plays.
- Set it in Get Info or with right-click › Key Shift. The shifted key is used everywhere: the Key column (with a `↕ +2` suffix), labels, Harmonize and exports.
- On 🟦/🟥 transitions, **Fix key** in the editor header applies the smallest shift that turns the transition 🟩/🟨 without making the shifted track's other transition worse.
- Harmonize never shifts keys itself.

## Stems, effects and presets

**Stems:** add **Drums**, **Bassline**, **Melody** or **Vocals** lanes (**+ Lane › Stems**), or pick the **Stem Swap** preset.

- Each stem lane is a level curve per song. For example, swap the basslines, or fade the outgoing vocals early.
- **Separation:** songs in transitions that use stem lanes are separated in the background, about 20 s each on an M4. The one being edited goes first.
  - The chip in the editor shows ✓ Stems, progress, or a retry.
  - Until a song's stems are ready, its stem lanes play the whole track.
  - **Mix › Separate Stems for All Songs** does the whole set.
- **Model:** Demucs v4 (`htdemucs`) running in ONNX Runtime with Core ML. The first separation after install compiles the model once (~40 s).
  - The output matches PyTorch Demucs (verified 80–95 dB agreement); see `scripts/stems/`.
- **Storage:** drums, bass and vocals are kept as AAC, about 15 MB per song. Melody is the track minus those three, so the four stems at full level are exactly the track.

**Effects lanes (+ Lane › Effects):**

- **Noise:** a white-noise riser that gets louder and brighter. It sounds only inside the transition.
- **Side Chain:** ducks the track on every beat of the transition, recovering over ~60% of the beat.
- **Reverb:** a reverb send, with its tail running on after the transition.
- These add to **Echo**.

**STEM files for Mixxx 2.6+ and Traktor:**

- **Mix › Export STEM Files for Mixxx…**, or **Export STEM File…** in a song's menu, writes `Artist - Title.stem.mp4` into a folder you choose.
- Each file holds five AAC tracks (the full mix, then Drums, Bass, Melody and Vocals) and the manifest naming and colouring them.
- Songs are separated first if needed.
- Matching keyboard controls for Mixxx are in `scripts/mixxx-keys/`.

**My presets (★ next to the presets):** save a transition's lanes, length and sync as a preset for every project, then apply or delete it. Applying keeps the transition's own placement.

**Settings › Storage (⌘,):**

- stem cache size against its cap (2–50 GB, default 10 GB), with the least recently used songs removed first
- per-song removal and Clear All
- separation progress
- the analysis and Core ML caches

## Using it

**Open the app**

1. Open **Pregame** from Applications. If you had installed it under its old name, delete `Harmonizer.app` so Mix files open in Pregame; your settings, analysis and stems carry over. Each mix is a `.hmix` project with autosave and full undo.

**Add tracks**

2. Use **File › Add Folder…** (⇧⌘O), *Add Folder Including Subfolders…* or *Add Files…*. Key, BPM and beat grid are analysed in the background. Results are cached in `~/Library/Application Support/Harmonizer/Analysis/`, keyed by file content, so a track is only analysed once across all projects.
3. **Playlist (sidebar):**
   - **Rows:** each row shows the title, artist, key and BPM.
   - **Pills:** the key pill has a Camelot-wheel colour edge. A pill turns orange when overridden and red when missing; a key shift adds a `↕ +2` suffix. Click a pill to override the value (any notation), key-shift the song or revert.
   - **Transitions** sit between the songs: their label and length. Click one to edit it; its lock appears on hover.
   - **Reordering:** drag rows by the handle that replaces the number on hover. Locked pairs and chains move together.
   - **Leaving songs out:** press **⌫**, or drag the song into **Not in mix** at the bottom. **⌘⌫** removes it from the project.
   - **Menus:** the hover **⋯** menu or a right-click gives Get Info, Key Shift, Revert, Show in Finder, Leave Out and Remove. Double-click opens Get Info.
   - First/last locks for Harmonize are set in the Harmonize panel.

**Harmonize and compare**

4. **Mix › Harmonize…** (⇧⌘H): every setting has an ⓘ that opens a short explanation. It offers Fuzzy/Mood, Key↔BPM priority, BPM tolerance, tempo direction, half/double tempo, locks, time budget and seed. Press **Preview** to see the new order's score, then **Apply** (it can be undone).
5. **Mix › Compare with Another Order…** (⇧⌘K): paste a track order from anywhere (another app, a friend's tracklist) to score it with the same settings. **Use This Order** adopts it.

**Export and import**

6. **File › Export Track List (CSV) / Playlist (M3U)**.
7. **File › Import Harmonize Run…** turns a run folder from the old web app (`<set>/harmonized/<run>/`) into a project. It brings over the order, overrides, settings and transition tweaks.
8. **Mix › Write Overrides to File Tags** writes overridden keys/BPMs into the audio files.

## How analysis works

- **Key and tempo:** Queen Mary DSP (`qm-keydetector`, `qm-tempotracker`) with Mixxx 2.5's exact settings and post-processing. On 121 tracks it matches Mixxx's stored keys 121/121 and BPMs 121/121 (±0.1).
- **Beat positions:** measured from kick onsets, so bar 1 lines up with the music.
- **Ordering:** Held-Karp exact solver for ≤15 tracks, otherwise iterated local search (2-opt + or-opt with segment reversal). The same seed gives the same order.

## Developing

```sh
swift build                     # debug build
swift test                      # the suite: synthetic audio generated in Swift, no external tools, a few minutes in debug
swift test --filter HarmonizeTests             # one suite while you work
scripts/test-real-music.sh ~/Music/party       # the private real-music suites (release build; see below)
swift scripts/icon/make-icon.swift icon.png   # regenerate the app icon artwork (then scripts/AppIcon.icns)
scripts/build-app.sh --install  # release .app → /Applications, signed (docs/signing.md)
```

**Requirements:**

- Xcode 26 or later / Swift 6 (CI uses the `macos-26` runner's default Xcode)
- Homebrew `taglib` (bundled into the .app), `rubberband`, `libsamplerate`, `lame`, `mpg123` (linked statically)
- ONNX Runtime 1.31.0 in `Vendor/onnxruntime/lib`, fetched and checksum-verified by `scripts/fetch-vendor.sh`

The deployment target is macOS 15, the oldest macOS that GitHub Actions still offers. Pull requests are tested on macOS 26. Every push to `main`, and a weekly run, also tests on macOS 15, so every supported version is tested. Anything newer than 15 must sit behind `#available` with a fallback. Homebrew builds its libraries for the macOS it runs on, so a local build only runs on that version of macOS or later. Releases are therefore built on macOS 15 by the release workflow, with TagLib built from pinned source, and `scripts/check-min-macos.sh` checks every Mach-O in the app ([docs/releasing.md](docs/releasing.md)). CI rehearses the release on every pull request.

**Tests** drive public behaviour (mostly through `MixProject`, plus the playback engine) and assert on what a Mix Host would notice: which Tracks play and in what order, Transition labels, lengths, and the audio frames produced. They are deterministic (seeded, with a fixed amount of solver work) and run offline. The test audio is generated in Swift, so no real music is committed.

**Real-music suites** stay out of the default run because they need your own music files. `scripts/test-real-music.sh <folder> [output folder]` runs them in a release build:

- analysis parity with the keys and BPMs Mixxx stored (`AnalysisParityTests`, the files listed in `Tests/PregameCoreTests/Fixtures/mixxx_analysis.json`)
- a full export of the folder with a click check at every join (`RealExportTests`)
- detected song structure, printed for eyeballing (`RealStructureTests`)
- optional, when their variables are set: stems against the reference (`PREGAME_STEM_REF`), real stems in a Transition (`PREGAME_STEM_PAIR`), separation and key-shift timing (`PREGAME_STEM_FILE`, `PREGAME_SHIFT_FILE`)

**Layout:**

| Path | What |
|---|---|
| `Sources/PregameCore` | Engine: keys, cost model, solver, analysis, cache, project, exports |
| `Sources/PregameCore/Resources/config.json` | Transition labels, Fuzzy/Mood costs, BPM model, defaults: **tune here** |
| `Sources/PregameCore/Resources/transitions.json` | Transition presets, automatic rules, defaults: **tune here** |
| `Sources/PregameCore/MixEngine.swift` | Mix layout, real-time/offline renderer |
| `Sources/PregameCore/Structure.swift` | Downbeat, phrases, sections, structure edits |
| `Sources/PregameCore/TrackTiming.swift` | Per-track edits, loops/key-shift audio variants, mix info |
| `Sources/PregameCore/MixPlan.swift` | Mix-on modes and transition placement |
| `Sources/PregameCore/KeyShift.swift` | Fix-key suggestion |
| `Sources/PregameCore/Stems.swift`, `StemCache.swift` | Demucs separation (STFT, segments, ONNX), AAC stem cache |
| `Sources/COnnx`, `Vendor/onnxruntime`, `Models/` | ONNX Runtime 1.31 (MIT) C shim + headers (the library comes from `scripts/fetch-vendor.sh`), exported Demucs model (MIT) |
| `scripts/stems/` | How the model was exported, reference implementation, benchmarks |
| `Sources/PregameCore/Transitions.swift` | Curves, specs, presets, tempo glide |
| `Sources/PregameCore/Export.swift` | WAV/MP3 export (the writer also does FLAC), tracklist, cue sheet |
| `Sources/CRubberBand`, `Sources/CLame` | Rubber Band (GPL) and LAME (LGPL), linked statically |
| `Sources/PregameApp` | SwiftUI app |
| `Sources/QMDSP` | Queen Mary DSP from Mixxx 2.5 (GPL) + C shim |
| `Sources/CTagLib` | TagLib bridge |
| `Tests/PregameCoreTests/Fixtures` | Keys and BPMs Mixxx stored for the real-music parity suite |
| `Tests/PregameCoreTests/Support/SyntheticAudio.swift` | Test audio generator: click tracks, chords in a key, energy ramps, section changes, silence; writes WAV/MP3/FLAC (plus M4A, AIFF) with tags |

**Licences:** the app is GPL-3.0 ([LICENSE](LICENSE)). QM DSP and Rubber Band are GPL-2.0+, TagLib, LAME and mpg123 are LGPL, ONNX Runtime and Demucs are MIT; [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) lists them all.
