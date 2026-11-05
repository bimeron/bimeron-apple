import Foundation
import XCTest
@testable import BimeronDaemon

final class DaemonSocketTransportTests: XCTestCase {
    func testFragmentedStatisticsFrameUsesStrictProtocolDecoding() throws {
        let request = DaemonRequest(command: "stats_snapshot")
        let bytes = frame(request)
        var buffer = DaemonSocketResponseBuffer()
        XCTAssertNil(try buffer.append(bytes.dropLast(), request: request))
        let result = try XCTUnwrap(buffer.append(bytes.suffix(1), request: request))
        let response = try DaemonProtocol.decode(result, request: request)
        XCTAssertEqual(response.stats_snapshot?.counters?.bytes_up, 12)
        XCTAssertEqual(response.stats_snapshot?.counters?.bytes_down, 34)
    }

    func testRejectsOverflowBeforeGrowingBuffer() throws {
        let request = DaemonRequest(command: "hello")
        var buffer = DaemonSocketResponseBuffer()
        let prefix = Array(repeating: UInt8(32), count: DaemonProtocol.responseLimit - 1)
        XCTAssertNil(try buffer.append(prefix[...], request: request))
        XCTAssertThrowsError(try buffer.append([32, 10][...], request: request)) {
            guard case DaemonError.oversized = $0 else { return XCTFail("Expected oversized, got \($0)") }
        }
        XCTAssertEqual(buffer.data.count, prefix.count)
    }

    func testAcceptsFrameExactlyAtLimitAndRejectsUnterminatedLimit() throws {
        let request = DaemonRequest(command: "hello")
        var bytes = frame(request)
        bytes.insert(contentsOf: repeatElement(UInt8(32), count: DaemonProtocol.responseLimit - bytes.count), at: bytes.count - 1)
        var buffer = DaemonSocketResponseBuffer()
        XCTAssertEqual(try buffer.append(bytes[...], request: request)?.count, DaemonProtocol.responseLimit)
        var unterminated = DaemonSocketResponseBuffer()
        XCTAssertThrowsError(try unterminated.append(Array(repeating: UInt8(32), count: DaemonProtocol.responseLimit)[...], request: request))
    }

    func testRejectsMalformedDuplicateUncorrelatedAndMultipleFrames() {
        let request = DaemonRequest(command: "stats_snapshot")
        let valid = String(decoding: frame(request), as: UTF8.self)
        for value in ["not JSON\n", valid + valid, valid + "x",
                      valid.replacingOccurrences(of: request.id, with: "foreign"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"Version\":1"),
                      valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")] {
            var buffer = DaemonSocketResponseBuffer()
            XCTAssertThrowsError(try buffer.append(Array(value.utf8)[...], request: request))
        }
    }

    func testDeadlineExpiresAtOriginalInstant() throws {
        let origin = ContinuousClock.now
        let deadline = DaemonSocketDeadline(timeout: .seconds(5), now: origin)
        XCTAssertNoThrow(try deadline.check(now: origin.advanced(by: .seconds(4))))
        XCTAssertThrowsError(try deadline.check(now: origin.advanced(by: .seconds(5)))) {
            guard case DaemonError.timeout = $0 else { return XCTFail("Expected timeout, got \($0)") }
        }
        XCTAssertThrowsError(try deadline.check(now: origin.advanced(by: .seconds(6))))
    }

    func testCancelledDeadlineCheck() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try DaemonSocketDeadline(timeout: .seconds(5)).check()
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testExpiredMutationDeadlineFailsBeforeOpeningSocket() async {
        do {
            _ = try await DaemonSocketTransport().framedExchange(DaemonRequest(command: "start"), timeout: .zero)
            XCTFail("Expected timeout")
        } catch DaemonError.timeout {
        } catch {
            XCTFail("Expected timeout, got \(error)")
        }
    }

    private func frame(_ request: DaemonRequest) -> [UInt8] {
        Array("{\"version\":1,\"id\":\"\(request.id)\",\"instance\":\"one\",\"status\":{\"State\":\"connected\"},\"stats_snapshot\":{\"status\":{\"State\":\"connected\"},\"counters\":{\"bytes_up\":12,\"bytes_down\":34}}}\n".utf8)
    }
}
