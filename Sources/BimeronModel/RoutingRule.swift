import Foundation

public struct RoutingRule: Identifiable, Equatable, Sendable {
    public let id: Int
    public var enabled: Bool
    public var type: String
    public var destination: String
    public var action: String

    public init(id: Int, enabled: Bool = true, type: String = "Domain", destination: String = "example.com", action: String = "proxy") {
        self.id = id
        self.enabled = enabled
        self.type = type
        self.destination = destination
        self.action = action
    }
}
