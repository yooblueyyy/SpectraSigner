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
sh scripts/fetch-server-cert.sh   # certificate for the on-device install server
xcodegen generate
open SpectraSigner.xcodeproj
```

## Project layout

| Path | What's there |
| --- | --- |
| `App/` | SwiftUI app: views, stores (library, certificates, sources, downloads) and services (import, signing, install server) |
| `Packages/ZSignKit/` | Swift package wrapping the [zsign](https://github.com/zhlynn/zsign) signing engine (MIT) with an Objective-C++ bridge |
| `Support/Info.plist` | File types, URL scheme and background modes |
| `scripts/` | Install-server certificate fetcher and the app-icon generator |

## Credits

- [zsign](https://github.com/zhlynn/zsign) by zhlynn: Mach-O code signing (MIT, see `Packages/ZSignKit/LICENSE-zsign`)
- [OpenSSL](https://github.com/krzyzanowskim/OpenSSL) Swift package by Marcin Krzyżanowski
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) by Thomas Zoechling
- [backloop.dev](https://backloop.dev): trusted HTTPS for localhost

## License

MIT. See [LICENSE](LICENSE).
