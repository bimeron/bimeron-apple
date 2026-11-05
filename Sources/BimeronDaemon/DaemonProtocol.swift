import Foundation

public struct DaemonSession: Codable, Equatable, Sendable {
    public let id: String
    public let active: Bool
    public let profile_id: String?
}

public struct DaemonStatus: Codable, Equatable, Sendable {
    public let State: String
    public let Session: DaemonSession?
    public var cleanupConfirmed: Bool { State == "disconnected" && Session?.active != true }
}

/// Ownership is captured with status; individual byte fields are independently atomic.
public struct DaemonStatisticsSnapshot: Decodable, Sendable {
    public struct Counters: Decodable, Sendable {
        public let bytes_up: Int64
        public let bytes_down: Int64
        public let unavailable: Bool?
    }
    public let status: DaemonStatus
    public let counters: Counters?
}

public struct DaemonResponse: Decodable, Sendable {
    public let version: Int
    public let id: String
    public let instance: String
    public let status: DaemonStatus
    public let session_bound_stats: Bool?
    public let stats_snapshot: DaemonStatisticsSnapshot?
    public let daemon_session_guards: Bool?
    public let error: String?
}

public struct DaemonRequest: Encodable, Sendable {
    public let version = 1
    public let id: String
    public let command: String
    public let instance: String?
    public let session: String?
    public let config: String?

    public init(command: String, instance: String? = nil, session: String? = nil, config: String? = nil) {
        id = UUID().uuidString
        self.command = command
        self.instance = instance
        self.session = session
        self.config = config
    }
}

public enum DaemonError: Error { case invalidProtocol, oversized, unavailable, untrustedPeer, timeout }

public enum DaemonProtocol {
    public static let requestLimit = 16 * 1024
    public static let responseLimit = 256 * 1024

    public static func encode(_ request: DaemonRequest) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(10)
        guard data.count <= requestLimit else { throw DaemonError.oversized }
        return data
    }

    public static func decode(_ data: Data, request: DaemonRequest) throws -> DaemonResponse {
        guard data.count <= responseLimit else { throw DaemonError.oversized }
        guard data.last == 10, !data.dropLast().contains(10) else { throw DaemonError.invalidProtocol }
        try rejectDuplicateKeys(data)
        let response = try JSONDecoder().decode(DaemonResponse.self, from: data)
        guard response.version == 1, response.id == request.id, !response.instance.isEmpty else {
            throw DaemonError.invalidProtocol
        }
        return response
    }
    static func authorizeMutation(_ request: DaemonRequest, hello: DaemonResponse) throws {
        guard hello.error == nil, hello.daemon_session_guards == true,
              request.instance == hello.instance,
              request.command != "stop" || (request.session != nil && request.session == hello.status.Session?.id
                  && hello.status.Session?.active == true),
              request.command != "start" || hello.status.cleanupConfirmed else {
            throw DaemonError.invalidProtocol
        }
    }

    // JSONDecoder accepts duplicate keys; reject them, including escaped and casing aliases.
    private static func rejectDuplicateKeys(_ data: Data) throws {
        let bytes = Array(data)
        var objects: [Set<String>] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: objects.append([])
            case 125:
                guard !objects.isEmpty else { throw DaemonError.invalidProtocol }
                objects.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count && bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { throw DaemonError.invalidProtocol }
                var next = index + 1
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] == 58 {
                    guard !objects.isEmpty else { throw DaemonError.invalidProtocol }
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...index]))
                    guard objects[objects.count - 1].insert(key.lowercased()).inserted else { throw DaemonError.invalidProtocol }
                }
            default: break
            }
            index += 1
        }
    }

}
