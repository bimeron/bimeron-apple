import Foundation
import Darwin

// Synthetic buffers only. No archive parsing, decompression, or executable payload.
let mib = 1_048_576
let archiveSize = 8 * mib
let sizes = [12 * mib, mib / 4, mib / 4]
let cap = 96 * mib
let mode = CommandLine.arguments[1]
precondition(["owned", "cow", "release", "chunked", "semantics"].contains(mode))
let modeledMaximum = archiveSize + sizes.reduce(0, +) * (mode == "owned" ? 2 : 1) + (mode == "chunked" ? 65536 : 0)
precondition(modeledMaximum <= cap)
let start = DispatchTime.now().uptimeNanoseconds
var phases = [[String: Any]]()
func sample(_ name: String, _ retained: Int, _ copied: Int = 0) {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    var usage = rusage()
    precondition(getrusage(RUSAGE_SELF, &usage) == 0)
    phases.append(["phase": name, "rss_bytes": info.resident_size,
                   "process_peak_rss_bytes": usage.ru_maxrss, "logical_retained_bytes": retained,
                   "explicit_copied_bytes_cumulative": copied,
                   "elapsed_ms": Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6])
}
func buffer(_ size: Int) -> Data {
    var data = Data(count: size)
    data.withUnsafeMutableBytes { (p: UnsafeMutableRawBufferPointer) in
        // Write every byte, including every page, rather than relying on demand-zero pages.
        for i in 0..<size { p[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 17) }
    }
    return data
}
func owned(_ data: Data) -> Data {
    data.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
}
sample("baseline", 0)
var checks = [String: Bool]()
if mode == "semantics" {
    var original = buffer(65536)
    let retained = original
    let copied = owned(original)
    original[0] = 222
    checks["swift_value_mutation_preserves_retained"] = retained[0] == 17
    checks["explicit_copy_preserves_bytes"] = copied[0] == 17
    let external = NSMutableData(length: 65536)!
    memset(external.mutableBytes, 41, external.length)
    let borrowed = Data(bytesNoCopy: external.mutableBytes, count: external.length, deallocator: .none)
    let snapshot = owned(borrowed)
    memset(external.mutableBytes, 99, external.length)
    checks["no_copy_external_mutation_visible"] = borrowed[0] == 99
    checks["owned_snapshot_survives_external_mutation"] = snapshot[0] == 41
    withExtendedLifetime((external, borrowed, snapshot, retained, copied, original)) {
        sample("semantics_checked", 6 * 65536, 2 * 65536)
    }
    precondition(checks.values.allSatisfy { $0 })
} else {
    var archive: Data? = buffer(archiveSize)
    sample("archive_touched", archiveSize)
    var decoded = sizes.map(buffer)
    let payload = sizes.reduce(0, +)
    sample("three_decoded_touched", archiveSize + payload)
    var staged = [Data]()
    if mode == "owned" {
        staged = decoded.map(owned)
        // Force private writable pages even if the allocator uses VM copy optimizations.
        // Synthetic staging bytes intentionally differ at these offsets; no integrity claim.
        for index in staged.indices {
            staged[index].withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                for offset in stride(from: 0, to: raw.count, by: Int(getpagesize())) {
                    raw[offset] ^= 1
                }
            }
        }
        sample("explicit_owned_copies", archiveSize + payload * 2, payload)
    } else if mode == "cow" {
        staged = decoded
        sample("cow_retained_no_mutation", archiveSize + payload)
    } else if mode == "release" {
        archive = nil
        sample("archive_released", payload)
    }
    let fd = open(CommandLine.arguments[2], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    precondition(fd >= 0)
    var written = 0
    // Raw slices passed directly to write; no subdata allocation or second staging buffer.
    for data in staged.isEmpty ? decoded : staged {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), min(65536, raw.count - offset))
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                offset += n
                written += n
            }
        }
    }
    precondition(close(fd) == 0 && written == payload)
    withExtendedLifetime((archive, decoded, staged)) {
        sample("chunked_write_complete", (archive == nil ? 0 : archiveSize) + payload * (mode == "owned" ? 2 : 1), mode == "owned" ? payload : 0)
    }
    decoded.removeAll()
    staged.removeAll()
    archive = nil
    sample("all_released", 0, mode == "owned" ? payload : 0)
    checks["written_exact_payload"] = written == payload
}
let output: [String: Any] = ["mode": mode, "phases": phases, "checks": checks,
    "synthetic_live_allocation_upper_bound_bytes": modeledMaximum, "hard_cap_bytes": cap]
let json = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
print(String(decoding: json, as: UTF8.self))
