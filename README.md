# sid9tool

[繁體中文](README.md) | [简体中文](README.zh-Hans.md) | [English](README.en.md)

> 免電腦 Side-loading 工具：一機完成 Pairing、簽章與安裝，並內建 LiveContainer 風格的容器管理。

## ✨ 功能特色

- **免電腦安裝流程** — 参考 [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) 的流程，第一次啟動即引導完成設定：
  1. 匯入 RPPairing 檔案並信任
  2. 匯入 `.p12` + `.mobileprovision`（自動檢查到期日）
  3. 簽章並安裝（免費帳號 3 個 slot 配額，JIT-less 容器啟動）
- **App 管理** — 容器與已安裝 App 管理、IPA 匯入 / URL 安裝、3 個 App slot 配額、容器清單可重新排序
- **精選 Feed** — 遠端 JSON feed，附本機快取 fallback（`featured-fallback.json`）
- **設定** — Pairing、憑證、JIT-less / 容器設定、VPN / Tunnel、儲存空間清理、語言切換、關於
- **多語言** — 預設繁體中文（`zh-Hant`），可於 App 內切換 **English（en）** 與 **简体中文（zh-Hans）**；`IPA`、`Bundle ID`、`Entitlements`、`Log`、`JIT`、`VPN` 等技術術語於所有語言中保留英文

## 📱 介面結構

4 個底部分頁：

| 分頁 | 說明 |
| --- | --- |
| 首頁 | 可操作狀態卡片與快速設定狀態 |
| App | 容器與 side-load App 管理、IPA 匯入 / URL 安裝 |
| 精選 | 遠端 JSON feed（本機快取 fallback） |
| 設定 | Pairing、憑證、容器設定、VPN / Tunnel、儲存、語言、關於 |

## ⚙️ 環境需求

| 項目 | 版本 |
| --- | --- |
| iOS | 16.0+ |
| Swift | 5.10 |
| 介面 | 僅直式（Portrait） |
| 語言 | `zh-Hant`（預設）、`en`、`zh-Hans` |

## 🛠 本機建置

```powershell
# 1. 安裝 XcodeGen
brew install xcodegen

# 2. 產生 Xcode project
xcodegen generate

# 3. 建置（不簽章）
xcodebuild build \
  -project sid9tool.xcodeproj \
  -scheme sid9tool \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

## ☁️ GitHub Actions 建置

推送至 `main` 或手動觸發 `build-ipa` workflow：

1. `xcodegen generate` 產生 project
2. `xcodebuild` 建置 Release（不簽章）
3. 打包為 **unsigned `.ipa`** 並上傳 artifact（`sid9tool-unsigned`）

下載 artifact 後，請自行使用你的憑證簽章並安裝到裝置。

## 📁 專案結構

```
sid9tool/
├── src/sid9tool/
│   ├── App/              # Sid9toolApp 入口
│   ├── Models/           # AppModels
│   ├── Resources/        # featured-fallback.json
│   ├── Services/         # ContainerManager、SigningEngine、SlotManager、
│   │                     # PairingService、CertificateService、TunnelService、
│   │                     # FeaturedFeedService、LocalizationService…
│   └── Views/            # Home、App、Featured、Settings、Onboarding
├── .github/workflows/    # build-ipa.yml
├── project.yml           # XcodeGen 配置
└── featured.json         # 精選 feed 範例
```

## 🙏 致敬

- [LiveContainer](https://github.com/MrKai77/LiveContainer) — 容器 / 运行时管理介面風格
- [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) — 免電腦 Side-loading 安裝流程参考
- 主要開發：[Butt9r](https://github.com/Butt9r)

## ⚠️ 免責聲明

本專案僅供學習與研究使用，請遵守 Apple 服務條款與當地法律，並僅安裝您信任的 App。開發者不對任何使用後果負責。

## 📄 License

MIT License（詳見授權條款；請保留上方致敬說明）