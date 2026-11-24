# Updates

Pregame updates itself with [Sparkle 2](https://sparkle-project.org). **Pregame › Check for Updates…** checks on demand. The app also checks about once a day on its own, unless the Mix Host turns that off in **Settings › Updates**. That tab also offers to download and install updates automatically.

## How the app finds and trusts an update

The settings live in `scripts/Info.plist`:

| Key | Value | Why |
|---|---|---|
| `SUFeedURL` | `https://github.com/Praful-Joshi/pregame/releases/latest/download/appcast.xml` | Each GitHub Release carries the appcast for its version, so "latest" always answers with the newest one |
| `SUPublicEDKey` | the update key's public half | Sparkle installs only a DMG signed with the private half |
| `SURequireSignedFeed` | `true` | The appcast itself must be signed too, so a tampered appcast can't point anywhere else |
| `SUVerifyUpdateBeforeExtraction` | `true` | Sparkle checks the DMG's signature before opening it. It won't start with a signed feed without this |
| `SUEnableAutomaticChecks` | `true` | Checks run without asking first |
| `SUEnableInstallerLauncherService`, `SUEnableDownloaderService` | `true` | The App Sandbox needs these; see below |

Sparkle also checks that the new app's code signature satisfies the installed app's designated requirement. Every build is signed with the same self-signed certificate ([signing.md](signing.md)), so it does.

## Sandbox

The app is sandboxed ([ADR-0003](adr/0003-app-sandbox-from-v1.md)), so Sparkle works through its XPC services, embedded in `Sparkle.framework`:

- **Downloader** fetches the appcast and the DMG. It's sandboxed with its own network access. (The app's own outgoing-network entitlement is only for opt-in crash reports and usage data: [privacy.md](privacy.md).)
- **Installer** launches Sparkle's installer outside the sandbox. The app reaches it through two Mach service names, `com.prafuljoshi.pregame-spks` and `-spki`, listed as a temporary exception in `scripts/Pregame.entitlements`. They must match the bundle ID.

`scripts/build-app.sh` copies the framework from the pinned package and signs it inside out with the app's certificate and the hardened runtime: the XPC services, `Autoupdate`, `Updater.app`, then the framework. The Downloader gets Sparkle's own entitlements file, because its packaged copy carries none. The CI job `signed-app` checks all of this on a real build.

## No "Open Anyway", no new permission prompts

Gatekeeper only stops apps with a quarantine flag. A browser sets that flag on the first DMG, which is why the first launch needs "Open Anyway" once. Sparkle checks the update's EdDSA signature, then removes the flag from every file in the new app before installing it. It can only remove it from files it can write, so `build-app.sh` makes every file in the bundle user-writable before signing.

Folder access granted with macOS's privacy permissions, and the app's container with its bookmarks, are tied to the bundle ID and the designated requirement. An update keeps both, so nothing is asked again.

## The update key

The update key is an EdDSA (Ed25519) key pair, separate from the code-signing certificate. Its private half is in the maintainer's login keychain as "Private key for signing Sparkle updates". Sparkle's tools come with the Swift package, in `.build/artifacts/sparkle/Sparkle/bin` after `swift build` or `swift package resolve`.

**Back it up once**, then delete the file after moving it to a password manager or other safe place. **Never commit it.**

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Documents/pregame-update-key.txt
```

On a new Mac, restore it instead of making a new one:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -f ~/Documents/pregame-update-key.txt
```

`generate_keys -p` prints the public key. It must equal `SUPublicEDKey`. Don't generate a new key: installed copies only trust this one, so a new key would cut them off from updates. The release workflow takes the same key as a secret of the `release` environment ([releasing.md](releasing.md)), which also covers backing up and rotating it.

## Publishing an update by hand

Normally the release workflow does this when you push a version tag ([releasing.md](releasing.md)). To do it locally:

1. Raise `CFBundleShortVersionString` (shown, e.g. `0.2`) and `CFBundleVersion` (compared, e.g. `2`) in `scripts/Info.plist`, then build: `scripts/build-app.sh`.
2. Package the DMG: `hdiutil create -volname Pregame -srcfolder build/Pregame.app -format UDZO build/Pregame-0.2.dmg`.
3. Optionally, write release notes next to it as `build/Pregame-0.2.md` (or `.html`). They're embedded in the appcast.
4. Generate and sign the appcast:

   ```sh
   scripts/make-appcast.sh build/Pregame-0.2.dmg     # → build/appcast/appcast.xml
   ```

   It signs with the key in your keychain (macOS may ask to allow access to it). Set `PREGAME_SPARKLE_KEY_FILE` to sign with a key file instead, or to `-` to read the key from standard input.
5. Create the GitHub Release tagged `v0.2` and attach both `Pregame-0.2.dmg` and `appcast.xml`. The appcast points at the DMG in that release.

Don't edit the appcast after it's generated: the edit breaks its signature, and the app then rejects it.

Each appcast lists only its own release, and the app asks GitHub for the release marked **latest**. So the release marked latest must always be the newest stable version, with its `appcast.xml` attached. A latest release without one stops updates for everyone. Pre-releases are never marked latest; betas will get their own appcast ([#26](https://github.com/Praful-Joshi/pregame/issues/26)).

## Testing an update end to end

To test without touching the real app's container, use a copy with a throwaway bundle ID (as in the sandbox tests):

1. Make two copies of `build/Pregame.app` (0.1 and 0.2) with bundle ID `com.prafuljoshi.pregame.sbtest`, `SUFeedURL` set to `http://127.0.0.1:8765/appcast.xml`, and `SUPublicEDKey` set to a throwaway key. Re-sign each with the entitlements' Mach service names changed to that bundle ID.
2. Put 0.2 in a DMG and run `make-appcast.sh` with `PREGAME_SPARKLE_KEY_FILE` set to the throwaway key. Point the enclosure URL at the local server, and re-sign the appcast with `sign_update --ed-key-file`.
3. Serve the folder (`python3 -m http.server 8765 --bind 127.0.0.1`), open 0.1, and choose **Check for Updates…**, then **Install Update** and **Install and Relaunch**.

0.2 should relaunch in place with no Gatekeeper or permission prompt, with no quarantine flag (`xattr -rl` lists no `com.apple.quarantine`), and satisfying 0.1's designated requirement.
