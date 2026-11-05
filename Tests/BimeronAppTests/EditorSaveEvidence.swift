import Foundation
import Testing
@testable import BimeronCoreCLI

// Test-only bounded aggregation; observations never carry process text or file names.
final class EditorSaveEvidence: @unchecked Sendable {
    enum Stage: String { case dirname, stat, cmp, cp, done }
    private let lock = NSLock()
    private let stage: URL
    private var active = true
    private var transitions: [(stage: Stage, elapsed: Duration)] = []
    private var milestones: [CoreCLI.Observation] = []
    private var firstPoll: CoreCLI.Observation?
    private var lastPoll: CoreCLI.Observation?
    private var previousPoll: Duration?
    private var maxGap: Duration = .zero

    init(stage: URL) { self.stage = stage }

    static func decodeStage(_ bytes: Data) -> Stage? {
        guard bytes.count < 64 else { return nil }
        return Stage(rawValue: String(decoding: bytes, as: UTF8.self))
    }

    func record(_ event: CoreCLI.Observation) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        if case .poll(let elapsed, _, _, _) = event {
            if firstPoll == nil { firstPoll = event }
            lastPoll = event
            if let previousPoll { maxGap = max(maxGap, elapsed - previousPoll) }
            previousPoll = elapsed
            if transitions.count < 6, let file = try? FileHandle(forReadingFrom: stage) {
                defer { try? file.close() }
                if let bytes = try? file.read(upToCount: 64),
                   let value = Self.decodeStage(bytes), transitions.last?.stage != value {
                    transitions.append((value, elapsed))
                }
            }
        } else if milestones.count < 6 {
            milestones.append(event)
        }
    }

    func finish() -> String {
        lock.lock()
        defer { lock.unlock() }
        active = false
        return "editorSaveEvidence milestones=\(milestones) firstPoll=\(String(describing: firstPoll)) lastPoll=\(String(describing: lastPoll)) maxGap=\(maxGap) stages=\(transitions.map { "\($0.stage.rawValue)@\($0.elapsed)" })"
    }
}

@Test func editorSaveEvidenceIsBoundedAndExcludesUnknownStageText() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let stage = root.appending(path: "secret-path")
    try Data("password-secret".utf8).write(to: stage)
    let early = EditorSaveEvidence(stage: stage)
    early.record(.poll(.milliseconds(1), running: true, stdoutEOF: false, stderrEOF: false))
    early.record(.exitObserved(.milliseconds(2)))
    let late = EditorSaveEvidence(stage: stage)
    for n in 0..<1000 {
        late.record(.poll(.milliseconds(n * 3), running: true, stdoutEOF: false, stderrEOF: false))
    }
    late.record(.deadline(.seconds(2), cancelled: false, timedOut: true))
    late.record(.exitObserved(.seconds(3)))
    try Data("done".utf8).write(to: stage)
    early.record(.poll(.milliseconds(4), running: false, stdoutEOF: true, stderrEOF: true))
    let earlySummary = early.finish()
    let lateSummary = late.finish()
    #expect(earlySummary.contains("done@0.004 seconds"))
    #expect(!earlySummary.contains("deadline"))
    #expect(lateSummary.contains("timedOut: true"))
    #expect(earlySummary.contains("exitObserved"))
    #expect(lateSummary.contains("exitObserved"))
    #expect(lateSummary.count < 1000)
    #expect(!lateSummary.contains("secret"))
    #expect(!lateSummary.contains(root.path))
    #expect(EditorSaveEvidence.decodeStage(Data(repeating: 65, count: 64)) == nil)
    #expect(EditorSaveEvidence.decodeStage(Data("done".utf8)) == .done)
    late.record(.launchBegin(.zero))
    #expect(late.finish() == lateSummary)
}
