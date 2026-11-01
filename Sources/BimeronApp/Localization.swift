import Foundation

enum Localization {
    static func text(_ key: String, language: String) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
