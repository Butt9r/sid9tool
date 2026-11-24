import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHant = "zh-Hant"
    case en = "en"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }
}

/// Runtime language switching (zh-Hant default / en / zh-Hans).
/// Technical terms such as IPA, Bundle ID, Entitlements, JIT, VPN stay in English in all locales.
final class LocalizationService: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "sid9tool.language")
            // Force SwiftUI view refresh.
            objectWillChange.send()
        }
    }

    static let storageKey = "sid9tool.language"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        self.language = saved.flatMap { AppLanguage(rawValue: $0) } ?? .zhHant
    }

    /// Resolve a localized string for the active language.
    func t(_ zhHant: String, _ en: String, _ zhHans: String) -> String {
        switch language {
        case .zhHant: return zhHant
        case .en: return en
        case .zhHans: return zhHans
        }
    }
}