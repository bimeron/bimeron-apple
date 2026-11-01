import Foundation
import Testing
@testable import BimeronApp

@Test @MainActor func languageSelectionAndPersistence() throws {
    let suite = "BimeronLocalizationTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    for languages in [["en-US"], ["de-DE", "ru-RU"], []] {
        #expect(AppModel(defaults: defaults, preferredLanguages: languages).language == "en")
    }
    let model = AppModel(defaults: defaults, preferredLanguages: ["ru-RU", "en-US"])
    #expect(model.language == "ru")
    #expect(model.t("Profiles") != "Profiles")

    model.language = "en"
    #expect(defaults.string(forKey: "language") == "en")
    #expect(AppModel(defaults: defaults, preferredLanguages: ["ru-RU"]).language == "en")
    #expect(model.t("Profiles") == "Profiles")

    model.language = "ru"
    #expect(AppModel(defaults: defaults, preferredLanguages: ["en-US"]).language == "ru")
    defaults.set("unsupported", forKey: "language")
    #expect(AppModel(defaults: defaults, preferredLanguages: ["en-US"]).language == "en")
}

@Test func translationResourcesResolve() {
    for key in ["Profiles", "Settings", "Error", "Profile added", "Russian"] {
        #expect(Localization.text(key, language: "en") == key)
        #expect(Localization.text(key, language: "ru") != key)
    }
    #expect(Localization.text("Unknown key", language: "ru") == "Unknown key")
}
