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

}
