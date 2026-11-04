#!/usr/bin/env python3
"""Offline sequential synthetic benchmark; compiler and output artifacts live in a temp directory."""
import json
import pathlib
import platform
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent

def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

def main():
    before = {"vm_stat": command("/usr/bin/vm_stat"),
              "sysctl": command("/usr/sbin/sysctl", "hw.memsize", "kern.memorystatus_vm_pressure_level")}
    runs = []
    with tempfile.TemporaryDirectory(prefix="staging-memory-") as tmp:
        root = pathlib.Path(tmp)
        executable = root / "memory"
        compile_command = ["/usr/bin/swiftc", "-O", "-module-cache-path", str(root / "module-cache"),
                           str(HERE / "memory.swift"), "-o", str(executable)]
        compile_output = command(*compile_command)
        for repetition in range(3):
            for mode in ("semantics", "owned", "cow", "release", "chunked"):
                run = json.loads(command(str(executable), mode, str(root / f"{repetition}-{mode}.bin")))
                run["repetition"] = repetition + 1
                runs.append(run)
    maximum_archive = 268435456
    maximum_payload = 276824064
    result = {
        "scope": "Local synthetic memory/staging experiment, no parser or real release; no production claims.",
        "platform": platform.platform(), "swift_version": command("/usr/bin/swiftc", "--version"),
        "proposal_revision_read": "b12d285", "before": before,
        "after": {"vm_stat": command("/usr/bin/vm_stat"),
                  "sysctl": command("/usr/sbin/sysctl", "hw.memsize", "kern.memorystatus_vm_pressure_level")},
        "reproduce": "python3 research/staging-memory/run-memory.py",
        "compile_command_template": "/usr/bin/swiftc -O -module-cache-path <temp>/module-cache research/staging-memory/memory.swift -o <temp>/memory",
        "run_command_template": "<temp>/memory <semantics|owned|cow|release|chunked> <temp>/<unique-output>.bin",
        "compile_output": compile_output,
        "fixture_assumptions_bytes": {"archive": 8 * 1048576, "decoded": [12 * 1048576, 262144, 262144]},
        "maximum_arithmetic_only_bytes": {
            "archive": maximum_archive, "decoded": maximum_payload,
            "archive_plus_decoded": maximum_archive + maximum_payload,
            "archive_plus_decoded_and_owned_payload_copy": maximum_archive + 2 * maximum_payload,
            "cow_unique_storage_without_mutation": maximum_archive + maximum_payload,
            "after_archive_release_retained_payload": maximum_payload,
            "chunked_write_retaining_archive_and_decoded": maximum_archive + maximum_payload,
            "hypothetical_streaming_archive_plus_64KiB_output": maximum_archive + 65536},
        "caveats": [
            "Full 520 MiB and duplicate maximum scenarios were not allocated: unsafe under observed host memory pressure. Maximum RSS cannot be empirically validated safely here.",
            "96 MiB cap covers modeled synthetic live buffers, not Swift runtime/compiler, allocator metadata, kernel cache, or total process RSS; fixture maximum is only 33 MiB.",
            "Current RSS is MACH_TASK_BASIC_INFO resident_size; process peak RSS is Darwin getrusage ru_maxrss in bytes. Neither is physical footprint; physical footprint was not measured.",
            "Logical retained byte counts describe unique expected synthetic storage, not observed allocations. Data COW assignment is not an ownership guarantee for external mutable storage.",
            "Release may leave allocator pages resident. Compression, scheduling, allocator behavior, cache and sampling affect RSS/time; phases can miss transients, process peak includes all earlier phases.",
            "Initial buffers are touched byte-by-byte; owned staging copies additionally mutate one byte per host page to force private writable pages (synthetic contents intentionally differ). Timings include generation, sampling and buffered writes; no fsync, durability, parser, inflater, hashing or real release performance is measured.",
            "Chunked mode retains all decoded buffers and only avoids staging copies. Hypothetical streaming arithmetic requires a different validated inflater design and does not describe this implementation.",
            "No scaled small-fixture RSS is presented as measured maximum. Owned archive ingress copy and source coexistence are not included; an extra archive buffer would add 268435456 bytes at maximum.",
            "External mutable NSData test uses an explicit bytesNoCopy view; it does not generalize all NSData bridging implementations."
        ], "runs": runs}
    for mode in ("owned", "cow", "release", "chunked"):
        subset = [r for r in runs if r["mode"] == mode]
        result.setdefault("observed_ranges", {})[mode] = {
            "process_peak_rss_bytes": [min(r["phases"][-1]["process_peak_rss_bytes"] for r in subset), max(r["phases"][-1]["process_peak_rss_bytes"] for r in subset)],
            "total_elapsed_ms": [min(r["phases"][-1]["elapsed_ms"] for r in subset), max(r["phases"][-1]["elapsed_ms"] for r in subset)]}
    (HERE / "memory-results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["observed_ranges"], indent=2))

if __name__ == "__main__":
    main()
