import Foundation

public enum ProfileInput {
    public static func normalized(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, let first = value.first, ["\"", "'"].contains(first), value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    public static func fileURL(_ input: String) -> URL? {
        let value = normalized(input)
        if let url = URL(string: value), url.isFileURL { return url }
        guard !value.contains("://"), value.hasPrefix("/") || value.hasPrefix("~") || value.lowercased().hasSuffix(".conf") else { return nil }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }
}
