import Foundation
import XCTest
@testable import BimeronDaemon

final class DaemonProtocolTests: XCTestCase {
    func testRejectsMalformedMaliciousOversizedAndMismatchedResponses() throws {
        let request = DaemonRequest(command: "hello")
        let valid = "{\"version\":1,\"id\":\"\(request.id)\",\"instance\":\"one\",\"status\":{\"State\":\"disconnected\"}}\n"
        XCTAssertEqual(try DaemonProtocol.decode(Data(valid.utf8), request: request).instance, "one")
        for value in ["not JSON\n", String(valid.dropLast()), valid + valid,
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"Version\":2"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"\\u0076ersion\":2"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":2"),
                      valid.replacingOccurrences(of: request.id, with: "foreign"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
                      valid.replacingOccurrences(of: "\"one\"", with: "\"\"")] {
            XCTAssertThrowsError(try DaemonProtocol.decode(Data(value.utf8), request: request))
        }
        XCTAssertThrowsError(try DaemonProtocol.decode(Data(repeating: 32, count: DaemonProtocol.responseLimit + 1), request: request))
        XCTAssertThrowsError(try DaemonProtocol.encode(DaemonRequest(command: "start", config: String(repeating: "x", count: 17000))))
    }
    func testGuardHandshakeCannotDowngradeOrCrossInstances() throws {
        let request = DaemonRequest(command: "start", instance: "one", config: "/A")
        func hello(_ guards: Bool, instance: String = "one") throws -> DaemonResponse {
            let json = "{\"version\":1,\"id\":\"test\",\"instance\":\"\(instance)\",\"daemon_session_guards\":\(guards),\"status\":{\"State\":\"disconnected\"}}"
            return try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
        }
        XCTAssertNoThrow(try DaemonProtocol.authorizeMutation(request, hello: hello(true)))
        XCTAssertThrowsError(try DaemonProtocol.authorizeMutation(request, hello: hello(false)))
        XCTAssertThrowsError(try DaemonProtocol.authorizeMutation(request, hello: hello(true, instance: "two")))
        XCTAssertThrowsError(try DaemonProtocol.authorizeMutation(DaemonRequest(command: "start", config: "/A"), hello: hello(true)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: DaemonProtocol.encode(request)) as? [String: Any])
        XCTAssertEqual(object["instance"] as? String, "one")
        XCTAssertNil(object["session"])
    }

    func testSessionBoundSnapshotUsesExistingStrictFraming() throws {
        let request = DaemonRequest(command: "stats_snapshot")
        let valid = """
        {"version":1,"id":"\(request.id)","instance":"one","session_bound_stats":true,"status":{"State":"failed"},"stats_snapshot":{"status":{"State":"connected","Attempt":2,"Session":{"id":"epoch","active":true}},"counters":{"bytes_up":17,"bytes_down":29}}}
        """ + "\n"
        let response = try DaemonProtocol.decode(Data(valid.utf8), request: request)
        XCTAssertEqual(response.session_bound_stats, true)
        XCTAssertEqual(response.stats_snapshot?.status.Session?.id, "epoch")
        XCTAssertEqual(response.stats_snapshot?.counters?.bytes_up, 17)
        for value in [valid + valid, String(valid.dropLast()),
                      valid.replacingOccurrences(of: "\"bytes_up\":17", with: "\"bytes_up\":17,\"Bytes_Up\":18"),
                      valid.replacingOccurrences(of: "\"bytes_up\":17", with: "\"bytes_up\":9223372036854775808"),
                      valid.replacingOccurrences(of: "\"bytes_down\":29", with: "\"bytes_down\":1.5")] {
            XCTAssertThrowsError(try DaemonProtocol.decode(Data(value.utf8), request: request))
        }
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: DaemonProtocol.encode(request)) as? [String: Any])
        XCTAssertNil(fields["instance"])
        XCTAssertNil(fields["session"])
        XCTAssertNil(fields["config"])
    }

}
