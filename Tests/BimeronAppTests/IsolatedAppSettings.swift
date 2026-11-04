import Foundation
import Testing

final class IsolatedAppSettings {
    let suite = "BimeronIntegrationTests-" + UUID().uuidString
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit { defaults.removePersistentDomain(forName: suite) }
}
