import Foundation

public enum ProfileError: Error, Equatable, Sendable {
    case invalidUTF8
    case tooLarge
    case syntax(Int)
    case duplicate(String)
    case missing(String)
    case invalid(String)
    case unreadableKey
}
