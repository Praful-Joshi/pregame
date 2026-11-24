# Releasing

A release is a GitHub Release with two files: `Pregame-<version>.dmg` and `appcast.xml`. Installed copies read the appcast of the release marked **latest** and update from it ([updates.md](updates.md)).

Pushing a version tag starts `.github/workflows/release.yml`. The job waits until the maintainer approves the protected `release` environment. Then, on macOS 15 (the minimum macOS), it:

1. checks that the environment's secrets are set, that the tagged commit is on `main`, and that `CFBundleVersion` is higher than the latest release's
2. checks that the tag is `v` + `CFBundleShortVersionString` from `scripts/Info.plist` (`scripts/release.sh`)
3. checks that the Homebrew static libraries it links (Rubber Band, libsamplerate, LAME, mpg123) were built for macOS 15
4. builds TagLib from its pinned, checksummed source for macOS 15 (`scripts/build-taglib.sh`)
5. fetches ONNX Runtime and the Demucs model, and checks both against pinned SHA-256 checksums (`scripts/fetch-vendor.sh --model`)
6. builds and signs the app with the release certificate (`scripts/build-app.sh`), then checks every Mach-O in it loads on macOS 15 (`scripts/check-min-macos.sh`)
7. packages the DMG, then generates the appcast and signs it with the update key (`scripts/make-appcast.sh`). It stops if that key isn't the one installed copies trust (`SUPublicEDKey`)
8. generates a build-provenance attestation for the DMG and the appcast
9. publishes both to a GitHub Release for the tag, marked latest

Only this job can read the signing certificate and the update key: they're secrets of the `release` environment, which only accepts `v*` tags. No workflow that runs for a pull request can read a secret. CI's `release-rehearsal` job runs steps 2 to 7 on every pull request and push to `main`, with a throwaway certificate and update key, then launches the packaged app on macOS 15. A broken release therefore shows up before anyone tags one.

## One-time setup

You need the backup of the signing certificate ([signing.md](signing.md)) and of the update key ([updates.md](updates.md)). Create the environment once. In **Settings › Environments**, create `release`, then:

- under **Deployment protection rules**, tick **Required reviewers** and add yourself
- under **Deployment branches and tags**, choose **Selected branches and tags** and add the tag rule `v*`

Or do the same from the command line:

```sh
ME="$(gh api user -q .id)"
gh api -X PUT repos/Praful-Joshi/pregame/environments/release --input - <<EOF
{"reviewers": [{"type": "User", "id": $ME}], "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
gh api -X POST repos/Praful-Joshi/pregame/environments/release/deployment-branch-policies -f name='v*' -f type=tag
```

Then add the four secrets **to the environment** (`--env release`), never to the repository:

```sh
base64 -i ~/Documents/pregame-signing.p12 | gh secret set PREGAME_SIGNING_P12 --env release
gh secret set PREGAME_SIGNING_P12_PASSPHRASE --env release        # paste the backup's passphrase
gh secret set PREGAME_SPARKLE_KEY --env release < ~/Documents/pregame-update-key.txt
sentry token create pregame-inc/release-debug-symbols --json --fields token \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"], end="")' \
  | gh secret set SENTRY_AUTH_TOKEN --env release
```

`SENTRY_AUTH_TOKEN` is a Sentry organization token, which can upload debug symbols but can't read anything. The release uploads `build/Pregame.dSYM` (made by `build-app.sh`) so crash reports name Pregame's own functions. A lost token isn't a problem: revoke it in Sentry (**Settings › Auth Tokens**) and make a new one the same way.

`pregame-update-key.txt` is the export from `generate_keys -x` ([updates.md](updates.md)). Delete the exported files again once they're in your password manager.

## Cutting a release

1. On a branch, raise `CFBundleShortVersionString` (e.g. `0.2`) and `CFBundleVersion` (e.g. `2`; Sparkle compares this one, so it must go up every release) in `scripts/Info.plist`. Merge it to `main` and wait for CI to pass, including the release rehearsal.
2. Tag that commit and push the tag:

   ```sh
   git tag v0.2 && git push origin v0.2
   ```

3. In **Actions › Release**, open the run and choose **Review deployments › Approve**.
4. When it finishes, the release `v0.2` has `Pregame-0.2.dmg` and `appcast.xml`, and is marked latest. Installed copies find it on their next check.

GitHub writes the release notes from the merged pull requests; edit them on the release page if you like. To check where a download came from:

```sh
gh attestation verify Pregame-0.2.dmg --repo Praful-Joshi/pregame
```

If the run fails before publishing, fix it on `main`, then move the tag: `git push origin :v0.2`, tag the new commit and push again. If it fails after publishing, delete the release and its tag before trying again. Never edit `appcast.xml` by hand: that breaks its signature.

## Back up the keys

Two keys sign a release. Losing either one cuts installed copies off from updates, so keep each in a password manager, together with its passphrase, and nowhere in the repository:

| Key | Backup | Made by | Secret |
|---|---|---|---|
| Signing certificate "Pregame Self-Signed" | `pregame-signing.p12` and its passphrase | `scripts/make-signing-identity.sh` ([signing.md](signing.md)) | `PREGAME_SIGNING_P12`, `PREGAME_SIGNING_P12_PASSPHRASE` |
| Update key (EdDSA) | `pregame-update-key.txt` | `generate_keys -x` ([updates.md](updates.md)) | `PREGAME_SPARKLE_KEY` |

GitHub secrets can't be read back, so they're not a backup. Check the backups once in a while: `security import` the `.p12` into a throwaway keychain, and compare the update key's public half (`generate_keys -p` after `generate_keys -f`) with `SUPublicEDKey`.

## Rotating the update key

Rotate it only if it may have leaked. Installed copies trust exactly one update key, the `SUPublicEDKey` they were built with, and Sparkle accepts an update only if its DMG is signed with that key.

1. Generate a new key on a Mac that doesn't hold the old one (or with a new `--account`), and back it up (`generate_keys -x`).
2. Release a bridge version whose `SUPublicEDKey` is the **new** public key, but sign it with the **old** key: leave `PREGAME_SPARKLE_KEY` as it is. Installed copies check the DMG with the key they have before opening it (`SUVerifyUpdateBeforeExtraction`), so they install it. Sparkle's other way to rotate, falling back to the code signature, needs a Developer ID team, which a self-signed app doesn't have. Before tagging the bridge, add the **old** public key as the environment variable (not a secret) `PREGAME_INSTALLED_PUBLIC_KEY` of the `release` environment: `make-appcast.sh` then checks the signature against that key rather than the app's, and signs the DMG itself, because `generate_appcast` won't sign with a key the app doesn't carry. Rehearse the bridge first with the end-to-end update test in [updates.md](updates.md).
3. Leave the bridge as the latest release for a few weeks, so that copies check for updates and pick it up. Each appcast lists only the latest release, so a copy that hasn't installed the bridge by the time the next release comes out can't update; its Mix Host has to download the new DMG by hand.
4. Replace `PREGAME_SPARKLE_KEY` in the `release` environment with the new key, and delete `PREGAME_INSTALLED_PUBLIC_KEY`. Every later release is signed with the new key.

Don't change the signing certificate in the same release. Sparkle accepts a change of one or the other, as long as the remaining one still checks out.

If the old key leaked, an attacker can sign a DMG with it, but still has to get it into the appcast of the latest release on this repository. Rotate anyway, and check the repository's access and recent releases.

## Rotating the signing certificate

Avoid it. macOS identifies the app by its designated requirement, which includes the certificate's hash ([signing.md](signing.md)). With a new certificate macOS sees a different app: Mix Hosts are asked again for the folders they had granted, and the app's container may need their consent. Rotate only if the private key leaked.

1. Create the new certificate (`scripts/make-signing-identity.sh` with a new name, set as `PREGAME_SIGNING_IDENTITY`) and back it up.
2. Replace `PREGAME_SIGNING_P12` and `PREGAME_SIGNING_P12_PASSPHRASE` in the `release` environment, and if the name changed, add `PREGAME_SIGNING_IDENTITY: <new name>` to the release job's `env` in `release.yml`.
3. Keep the same update key for this release. Sparkle installs an update whose code signature changed as long as its EdDSA signature checks out with the key the installed copy trusts.
4. Say in the release notes that macOS will ask for folder access once more.

## Updating pinned sources

- **TagLib:** change `TAGLIB_VERSION` and `TAGLIB_SHA256` in `scripts/build-taglib.sh`. Take the checksum from the tarball you downloaded and checked yourself (or Homebrew's `taglib` formula, which uses the same file).
- **ONNX Runtime:** the checksums in `scripts/fetch-vendor.sh` (see the comments there).
- **Demucs model:** the weights are an asset of the release `model-htdemucs-1`, which is a prerelease, so it's never marked latest. A new export gets a new release (`model-htdemucs-2`), and its URL and checksums go in `scripts/fetch-vendor.sh` along with the new `Models/htdemucs.onnx`.
