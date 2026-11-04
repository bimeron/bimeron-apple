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
    for key in ["Profiles", "Settings", "Error", "Profile added", "Russian", "Protocol",
                "Paste an access link", "Supported protocols", "Show access key", "Choose file…",
                "SSH identity file", "SSH known_hosts file", "Enable ShadowTLS wrapper", "Plugin options",
                "CA certificate file", "CONNECT-UDP path", "SSH private key file (optional)", "No file selected", "File path", "Use default", "SSH known_hosts file (optional)",
                "Only basic checks are available. Core validation and connections are not integrated."] {
        #expect(Localization.text(key, language: "en") == key)
        #expect(Localization.text(key, language: "ru") != key)
    }
    #expect(Localization.text("Unknown key", language: "ru") == "Unknown key")
}
