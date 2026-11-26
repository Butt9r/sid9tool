# sid9tool

[繁體中文](README.md) | [简体中文](README.zh-Hans.md) | [English](README.en.md)

> PC-free sideloading tool — pairing, signing, and installation all on-device, with LiveContainer-style container management built in.

## ✨ Features

- **PC-free installation flow** — follows the [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) flow; the first-run onboarding guides you through:
  1. Import and trust the RPPairing file
  2. Import `.p12` + `.mobileprovision` (expiry checked automatically)
  3. Sign & install (free account 3-slot quota, JIT-less container launch)
- **App management** — container and installed-app management, IPA import / URL install, 3-app slot quota, reorderable container list
- **Featured feed** — remote JSON feed with a local cache fallback (`featured-fallback.json`)
- **Settings** — pairing, certificates, JIT-less / container settings, VPN / tunnel, storage cleanup, language switch, About
- **Localization** — Traditional Chinese (`zh-Hant`) by default; switch in-app to **English (`en`)** or **Simplified Chinese (`zh-Hans`)**. Technical terms such as `IPA`, `Bundle ID`, `Entitlements`, `Log`, `JIT`, `VPN` stay in English in all locales

## 📱 UI Structure

4 primary bottom tabs:

| Tab | Description |
| --- | --- |
| Home (首頁) | Actionable status cards & quick setup status |
| App | Container & sideloaded-app management, IPA import / URL install |
| Featured (精選) | Remote JSON feed (local cache fallback) |
| Settings (設定) | Pairing, certificates, container settings, VPN / tunnel, storage, language, About |

## ⚙️ Requirements

| Item | Version |
| --- | --- |
| iOS | 16.0+ |
| Swift | 5.10 |
| Orientation | Portrait only |
| Languages | `zh-Hant` (default), `en`, `zh-Hans` |

## 🛠 Local Build

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Generate the Xcode project
xcodegen generate

# 3. Build (unsigned)
xcodebuild build \
  -project sid9tool.xcodeproj \
  -scheme sid9tool \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

## ☁️ GitHub Actions Build

Push to `main` or trigger the `build-ipa` workflow manually:

1. `xcodegen generate` to create the project
2. `xcodebuild` builds Release (unsigned)
3. Packages an **unsigned `.ipa`** and uploads it as artifact `sid9tool-unsigned`

After downloading the artifact, sign it with your own certificate and install it on your device.

## 📁 Project Structure

```
sid9tool/
├── src/sid9tool/
│   ├── App/              # Sid9toolApp entry point
│   ├── Models/           # AppModels
│   ├── Resources/        # featured-fallback.json
│   ├── Services/         # ContainerManager, SigningEngine, SlotManager,
│   │                     # PairingService, CertificateService, TunnelService,
│   │                     # FeaturedFeedService, LocalizationService…
│   └── Views/            # Home, App, Featured, Settings, Onboarding
├── .github/workflows/    # build-ipa.yml
├── project.yml           # XcodeGen config
└── featured.json         # Featured feed sample
```

## 🙏 Acknowledgements

- [LiveContainer](https://github.com/MrKai77/LiveContainer) — container / runtime management UI style
- [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) — PC-free sideloading flow reference
- Primary developer: [Butt9r](https://github.com/Butt9r)

## ⚠️ Disclaimer

This project is for learning and research purposes only. Please comply with Apple's Terms of Service and applicable local laws, and only install apps you trust. The developer is not responsible for any consequences of use.

## 📄 License

MIT License (see the license terms; please keep the acknowledgements above)