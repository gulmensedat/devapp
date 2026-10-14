import Foundation
import Observation

/// Arayüz dili. "system" Mac'in dil tercihini izler (Türkçe değilse İngilizce).
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, tr, en

    var id: String { rawValue }

    /// Dil seçicide her dil kendi adıyla görünür.
    var title: String {
        switch self {
        case .system: return L("Sistem", "System")
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }
}

/// Dil durumu. `L(_:_:)` her çağrıda `isEnglish`'i okuduğu için SwiftUI gövdeleri dil değişince
/// kendiliğinden yeniden çizilir (Observation erişimi izler).
@Observable
final class LanguageStore {
    static let shared = LanguageStore()
    static let defaultsKey = "appLanguage"

    private(set) var language: AppLanguage
    private(set) var isEnglish: Bool

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = saved
        isEnglish = Self.resolveEnglish(saved)
    }

    /// Uygulamadan: seçimi kaydeder ve arayüzü günceller.
    func update(_ newValue: AppLanguage) {
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
        apply(newValue)
    }

    /// Widget'tan: uygulamanın yazdığı çözümlenmiş dili ("tr" / "en") uygular, kaydetmez.
    func applyResolved(_ code: String?) {
        guard let code, let lang = AppLanguage(rawValue: code), lang != .system else { return }
        apply(lang)
    }

    /// Widget'a yazılan çözümlenmiş dil kodu
    var resolvedCode: String { isEnglish ? "en" : "tr" }

    private func apply(_ lang: AppLanguage) {
        if language != lang { language = lang }
        let en = Self.resolveEnglish(lang)
        if isEnglish != en { isEnglish = en }
    }

    private static func resolveEnglish(_ lang: AppLanguage) -> Bool {
        switch lang {
        case .tr: return false
        case .en: return true
        case .system:
            let first = Locale.preferredLanguages.first ?? "en"
            return !first.lowercased().hasPrefix("tr")
        }
    }
}

/// Arayüz metni: `L("Kaydet", "Save")`. Tüm görünen metinler bu fonksiyondan geçer.
func L(_ tr: String, _ en: String) -> String {
    LanguageStore.shared.isEnglish ? en : tr
}
