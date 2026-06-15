# HiddenBarIcons

A tiny macOS menu-bar app that fixes the **notch problem**: when your menu bar
overflows, macOS hides the icons that would fall under the MacBook notch and you
can no longer reach them. HiddenBarIcons adds (ironically) one more menu-bar icon
— click it and your hidden icons are revealed.

> Status-bar-only app (no Dock icon). macOS 14 (Sonoma) and later. Universal
> (Apple Silicon + Intel). Auto-updates via [Sparkle](https://sparkle-project.org).

## How it works

HiddenBarIcons places **two** status items in your menu bar:

- a **separator** ` | ` — drag the icons you want to hide to its **left**;
- an **arrow** — **left-click** it (or press **⌘⌥B**) to collapse/expand.

When collapsed, the separator stretches to push everything on its left off-screen
(behind the notch / off the edge); expanding brings them back. **Right-click** (or
**⌃-click**) the arrow for the menu: Preferences, Check for Updates, Hide/Show
Notch (on notched Macs), the list of currently-hidden apps (with Accessibility
granted), and Quit.

### Features

- One-click collapse/expand of your menu-bar icons, plus a global **⌘⌥B** hotkey.
- **Auto-collapse** after a configurable delay.
- **Full-expand mode** — temporarily shows a Dock icon and an empty menu bar to
  free up the whole bar.
- **Hidden-apps list** — using the Accessibility API, lists the menu-bar items
  currently hidden so you can click one to open it (optionally right-click it).
- **Hide/Show Notch** — switches the built-in display to a notchless 16:10 mode.
- **Hold ⌘** to peek the separator when "hide separator when expanded" is on.

## Building

The Xcode project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated
`HiddenBarIcons.xcodeproj` **is committed**, so a plain clone builds in Xcode or
from the command line with no extra tooling.

```sh
# Open in Xcode and run, or build from the CLI:
xcodebuild build -project HiddenBarIcons.xcodeproj -scheme HiddenBarIcons -configuration Debug
```

If you change `project.yml`, regenerate the project:

```sh
brew install xcodegen
xcodegen generate
```

Regenerate the app icon / menu-bar glyphs (writes into `Assets.xcassets`):

```sh
swift scripts/generate-icon.swift
```

## Releasing

Releases are fully automated by [`.github/workflows/release.yml`](.github/workflows/release.yml).
Push a semver tag and CI builds a universal binary, code-signs it with Developer
ID, notarizes + staples the `.app` and `.dmg`, signs the DMG for Sparkle, creates
a GitHub Release with the DMG, and commits the updated `appcast.xml` to `main`:

```sh
git tag v0.1.0
git push origin v0.1.0
```

> Without signing secrets configured the workflow still runs end-to-end and
> ships an ad-hoc-signed DMG (Gatekeeper will warn) — handy for a first smoke test.

### One-time signing setup

The workflow consumes these GitHub Actions secrets:

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | base64 of your Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_P12_PASSWORD` | the `.p12` export passphrase |
| `MACOS_KEYCHAIN_PASSWORD` | random throwaway (auto-generated) |
| `MACOS_NOTARY_KEY_ID` | App Store Connect API **Key ID** |
| `MACOS_NOTARY_ISSUER_ID` | App Store Connect **Issuer ID** |
| `MACOS_NOTARY_KEY_P8_BASE64` | base64 of the App Store Connect `.p8` key |
| `SPARKLE_PRIVATE_KEY` | base64 of your Sparkle Ed25519 private seed |
| `HOMEBREW_TAP_TOKEN` | *(optional)* PAT to auto-update a Homebrew cask |

Populate them — see [`docs/release-setup.md`](docs/release-setup.md):

- [`scripts/bootstrap-release-secrets.sh`](scripts/bootstrap-release-secrets.sh)
  walks you through every artifact and pushes them with `gh`.

> The `SUPublicEDKey` in [`HiddenBarIcons/Resources/Info.plist`](HiddenBarIcons/Resources/Info.plist)
> **must** match the `SPARKLE_PRIVATE_KEY` secret, or installed apps will reject
> updates. Back up the private key — it cannot be recovered.

## Credits

HiddenBarIcons is an independent reimplementation inspired by
[Barly](https://github.com/domzilla/Barly). It does not depend on or include
Barly's code or assets. MIT-licensed — see [LICENSE](LICENSE).
