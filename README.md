<div align="center">

<img src="App/Assets.xcassets/Logo.imageset/logo.png" width="128" alt="Spectra Signer icon">

# Spectra Signer

Sign and install iOS apps right on your iPhone or iPad — no computer needed.

</div>

## Features

- **Library**: import `.ipa` / `.tipa` files from Files, a URL, or any app's share sheet. Unsigned and signed apps are kept separately.
- **On-device signing**: sign with your own `.p12` certificate and `.mobileprovision` profile, or ad-hoc.
- **One-tap install**: signed apps install through a local HTTPS server on the device (the same `itms-services` mechanism enterprise apps use).
- **Signing options**: change the name, bundle ID, version, minimum iOS version and icon; enable File Sharing; strip device restrictions, app extensions or the Watch app.
- **Dylib injection**: add `.dylib` tweaks, with optional weak loading.
- **Sources**: add AltStore-compatible sources, browse and search their apps, view screenshots, version history and news, and download straight into your library.
- **Certificates**: manage multiple certificates, see team, expiry, devices and entitlements, and pick a default.
- **Appearance**: spectrum accent colours plus light, dark and system themes.
- **Links**: `spectrasigner://source?url=…` adds a source; `spectrasigner://install?url=…` downloads an IPA.

## Install

Download `SpectraSigner.ipa` from the latest [GitHub Actions build](../../actions/workflows/build.yml) or [release](../../releases), then sideload it once with any signer (AltStore, Sideloadly, etc.). After that, Spectra Signer can sign and install other apps itself.

## Building

Builds run on GitHub Actions (`.github/workflows/build.yml`) on every push. Tag a commit `v1.2.3` to publish a release.

To build locally on a Mac with Xcode 16 or newer:

```sh
brew install xcodegen
xcodegen generate
open SpectraSigner.xcodeproj
```

## Installing apps

iOS installs an app from an `itms-services://` link only if the install manifest comes over HTTPS
with a publicly trusted certificate. A server on the phone can't have one, because a shared
certificate for localhost is revoked as soon as its private key is published. So the manifest comes
from `spectra-manifest/`, a small Vercel function, while the signed .ipa itself is served over plain
HTTP from 127.0.0.1 on the phone and never uploaded. The manifest service only receives the app's
name, bundle ID and version.

To run your own copy, deploy it with `cd spectra-manifest && vercel deploy --prod` and enter its URL
in Settings → Installation.

## Project layout

| Path | What's there |
| --- | --- |
| `App/` | SwiftUI app: views, stores (library, certificates, sources, downloads) and services (import, signing, install server) |
| `Packages/ZSignKit/` | Swift package wrapping the [zsign](https://github.com/zhlynn/zsign) signing engine (MIT) with an Objective-C++ bridge |
| `Support/Info.plist` | File types, URL scheme and background modes |
| `spectra-manifest/` | Vercel function that serves install manifests over HTTPS (see below) |
| `scripts/` | App-icon generator, and `share-ipa.bat` to share the latest build over a Cloudflare tunnel |

## Credits

- [zsign](https://github.com/zhlynn/zsign) by zhlynn: Mach-O code signing (MIT, see `Packages/ZSignKit/LICENSE-zsign`)
- [OpenSSL](https://github.com/krzyzanowskim/OpenSSL) Swift package by Marcin Krzyżanowski
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) by Thomas Zoechling

## License

MIT. See [LICENSE](LICENSE).
