import Foundation

/// Each creation variant owns its complete document and generated parameter values.
public struct ProtocolDrafts: Sendable {
    public private(set) var selected: EditorProtocol = .ss
    private var documents: [EditorProtocol: ConfigDocument] = [:]
    private var parameters: [EditorProtocol: [String: String]] = [:]

    public init() {}

    public func value(_ key: String) -> String { parameters[selected]?[key] ?? "" }

    public mutating func select(_ target: EditorProtocol, current: ConfigDocument) throws -> ConfigDocument {
        if current.formEditingIssue != nil { throw ProfileError.invalid("AccessKey") }
        documents[selected] = current
        var next = try documents[target] ?? target.document(name: current.name, values: [:])
        next.set("Profile", "Name", current.name)
        selected = target
        return next
    }

    public mutating func set(_ key: String, value: String, name: String) throws -> ConfigDocument {
        parameters[selected, default: [:]][key] = value
        return try generatedDocument(name: name)
    }

    public func generatedDocument(name: String) throws -> ConfigDocument {
        try selected.document(name: name, values: parameters[selected] ?? [:])
    }
}
