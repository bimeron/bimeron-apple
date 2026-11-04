import Foundation

/// Each creation variant owns its complete document and generated parameter values.
public struct ProtocolDrafts: Sendable {
    public private(set) var hasEdits = false
    public private(set) var selected: EditorProtocol = .ss
    private var documents: [EditorProtocol: ConfigDocument] = [:]
    private var parameters: [EditorProtocol: [String: String]] = [:]

    public init() {}

    public func value(_ key: String) -> String {
        parameters[selected]?[key] ?? (selected == .vmess ? ["VMessSecurity": "auto", "VMessNetwork": "tcp", "VMessTLS": "tls"][key] : nil) ?? ""
    }

    public mutating func recordEdits() { hasEdits = true }

    public mutating func select(_ target: EditorProtocol, current: ConfigDocument) throws -> ConfigDocument {
        if current.formEditingIssue != nil { throw ProfileError.invalid("AccessKey") }
        try checkParameterSource(current)
        documents[selected] = current
        var next = try documents[target] ?? target.document(name: current.name, values: [:])
        next.set("Profile", "Name", current.name)
        selected = target
        return next
    }

    /// Parameter bindings are safe only while Raw still contains their generated source.
    public func checkParameterSource(_ current: ConfigDocument) throws {
        guard selected.generated else { return }
        let expected = try generatedDocument(name: current.name)
        guard !current.isExplicit, current.source == expected.source, current.accessKey == expected.accessKey else {
            throw ProfileError.invalid("GeneratedAccessKey")
        }
    }

    /// Raw saves are authoritative; form saves must represent the latest parameter values.
    public func checkSave(_ current: ConfigDocument, raw: Bool) throws {
        if !raw { try checkParameterSource(current) }
        try current.validateLocally()
    }

    public func restoringGeneratedSource(in current: ConfigDocument) throws -> ConfigDocument {
        let generated = try generatedDocument(name: current.name)
        var restored = current
        try restored.restoreGeneratedSource(generated.source, value: generated.accessKey)
        return restored
    }

    public mutating func set(_ key: String, value: String, name: String) throws -> ConfigDocument {
        hasEdits = true
        parameters[selected, default: [:]][key] = value
        return try generatedDocument(name: name)
    }

    public func generatedDocument(name: String) throws -> ConfigDocument {
        try selected.document(name: name, values: parameters[selected] ?? [:])
    }
}
