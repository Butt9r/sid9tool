# sid9tool

[繁體中文](README.md) | [简体中文](README.zh-Hans.md) | [English](README.en.md)

> 免电脑 Side-loading 工具：一机完成 Pairing、签章与安装，并内置 LiveContainer 风格的容器管理。

## ✨ 功能特色

- **免电脑安装流程** — 参考 [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) 的流程，第一次启动即引导完成设置：
  1. 导入 RPPairing 文件并信任
  2. 导入 `.p12` + `.mobileprovision`（自动检查到期日）
  3. 签章并安装（免费账号 3 个 slot 配额，JIT-less 容器启动）
- **App 管理** — 容器与已安装 App 管理、IPA 导入 / URL 安装、3 个 App slot 配额、容器列表可重新排序
- **精选 Feed** — 远程 JSON feed，附本机缓存 fallback（`featured-fallback.json`）
- **设置** — Pairing、证书、JIT-less / 容器设置、VPN / Tunnel、存储空间清理、语言切换、关于
- **多语言** — 默认繁体中文（`zh-Hant`），可在 App 内切换 **English（en）** 与 **简体中文（zh-Hans）**；`IPA`、`Bundle ID`、`Entitlements`、`Log`、`JIT`、`VPN` 等技术术语在所有语言中保留英文

## 📱 界面结构

4 个底部分页：

| 分页 | 说明 |
| --- | --- |
| 首页 | 可操作状态卡片与快速设置状态 |
| App | 容器与 side-load App 管理、IPA 导入 / URL 安装 |
| 精选 | 远程 JSON feed（本机缓存 fallback） |
| 设置 | Pairing、证书、容器设置、VPN / Tunnel、存储、语言、关于 |

## ⚙️ 环境需求

| 项目 | 版本 |
| --- | --- |
| iOS | 16.0+ |
| Swift | 5.10 |
| 界面 | 仅竖向（Portrait） |
| 语言 | `zh-Hant`（默认）、`en`、`zh-Hans` |

## 🛠 本机构建

```bash
# 1. 安装 XcodeGen
brew install xcodegen

# 2. 生成 Xcode project
xcodegen generate

# 3. 构建（不签章）
xcodebuild build \
  -project sid9tool.xcodeproj \
  -scheme sid9tool \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

## ☁️ GitHub Actions 构建

推送到 `main` 或手动触发 `build-ipa` workflow：

1. `xcodegen generate` 生成 project
2. `xcodebuild` 构建 Release（不签章）
3. 打包为 **unsigned `.ipa`** 并上传 artifact（`sid9tool-unsigned`）

下载 artifact 后，请使用你自己的证书签章并安装到设备。

## 📁 项目结构

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
└── featured.json         # 精选 feed 示例
```

## 🙏 致谢

- [LiveContainer](https://github.com/MrKai77/LiveContainer) — 容器 / 运行时管理界面风格
- [FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller) — 免电脑 Side-loading 安装流程参考
- 主要开发：[Butt9r](https://github.com/Butt9r)

## ⚠️ 免责声明

本项目仅供学习与研究使用，请遵守 Apple 服务条款与当地法律，并仅安装你信任的 App。开发者不对任何使用后果负责。

## 📄 License

MIT License（详见授权条款；请保留上方致谢说明）