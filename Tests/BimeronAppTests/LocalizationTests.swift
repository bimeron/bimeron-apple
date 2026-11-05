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
                "Core validates saved configurations. Live connections are not checked.",
                "Core validation is unavailable", "Core validation cancelled", "Core validation timed out",
                "Core rejected the configuration", "Profile changed; reopen it before saving"] {
        #expect(Localization.text(key, language: "en") == key)
        #expect(Localization.text(key, language: "ru") != key)
    }
    #expect(Localization.text("Unknown key", language: "ru") == "Unknown key")
}

@Test @MainActor func integrationSettingsRemainIsolatedAndAreRemovedAfterUse() throws {
    var first: IsolatedAppSettings? = try IsolatedAppSettings()
    let suite = try #require(first?.suite)
    let defaults = try #require(first?.defaults)
    let second = try IsolatedAppSettings()
    let model = AppModel(coreCLI: nil, defaults: defaults, preferredLanguages: ["en"])
    model.language = "ru"
    model.theme = "dark"
    #expect(second.defaults.string(forKey: "language") == nil)
    #expect(second.defaults.string(forKey: "theme") == nil)
    first = nil
    #expect(defaults.persistentDomain(forName: suite) == nil)
}

@Test func compactStatusHasEnglishAndRussianCopy() {
    #expect(Localization.text("Not connected", language: "en") == "Not connected")
    #expect(Localization.text("Not connected", language: "ru") == "Не подключено")
    #expect(Localization.text("Select a profile and press Start.", language: "ru") == "Выберите профиль и нажмите «Запустить».")
}

@Test @MainActor func everyConnectionAndLauncherErrorHasRussianTranslation() throws {
    let codes = ["invalid_configuration", "ikev2_requires_foreground_user_session", "session_stop_failed",
                 "cleanup_failed", "session_start_failed", "session_already_running", "stale_instance",
                 "stale_session", "daemon_shutting_down", "future_error"]
    var keys = codes.compactMap { CoreConnection.errorKey(actionError: $0) }
    for failure in [CoreLauncher.Failure.cancelled, .failed, .timeout, .incompatible] {
        keys.append(try #require(CoreConnection.errorKey(launchError: failure)))
    }
    keys.append("Bimeron needs administrator approval to install and start its development Core.")
    #expect(keys.count == codes.count + 5)
    for key in keys {
        let english = Localization.text(key, language: "en")
        let russian = Localization.text(key, language: "ru")
        #expect(english == key)
        #expect(russian != english, "Missing Russian translation: \(key)")
    }
}

@Test func aboutShowsBundledCoreIdentityAndLocalizedRunningState() throws {
    let json = """
    {"version":"0.1.0-ba22-dev","revision":"6b0d97a4ac96a903153a57d544751401b98d6909",
     "sha256":"unused","detach_sha256":"unused","production_shipping":false,
     "provenance":"local-development-untrusted"}
    """
    let manifest = try JSONDecoder().decode(BundledCoreManifest.self, from: Data(json.utf8))
    #expect(manifest.displayIdentity == "Core 0.1.0-ba22-dev (6b0d97a4)")
    #expect(Localization.text("Core running", language: "ru") == "Core запущен")
    #expect(Localization.text("Core not running", language: "ru") == "Core не запущен")
    for key in ["Core running", "Core not running", "Bundled Core information unavailable"] {
        #expect(Localization.text(key, language: "en") == key)
        #expect(Localization.text(key, language: "ru") != key)
    }
}
