import Foundation

public struct StoredProfile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var document: ConfigDocument

    public init(id: UUID = UUID(), document: ConfigDocument) {
        self.id = id
        self.document = document
    }
}
