#!/usr/bin/env bash
set -euo pipefail

MAX_MS="${TASKLIGHT_UI_REFRESH_MAX_MS:-500}"
SWIFT_FILE="$(mktemp "${TMPDIR:-/tmp}/tasklight-ui-refresh-XXXXXX.swift")"
trap 'rm -f "$SWIFT_FILE"' EXIT INT TERM

cat >"$SWIFT_FILE" <<'SWIFT'
import Dispatch
import Foundation
import Darwin

let maxMilliseconds = Double(CommandLine.arguments.dropFirst().first ?? "500") ?? 500
let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent("tasklight-ui-latency-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: stateDir) }
try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
let stateURL = stateDir.appendingPathComponent("state.json")

func atomicWrite(_ text: String, to url: URL) throws {
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    try text.write(to: tmp, atomically: false, encoding: .utf8)
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    } else {
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}

let initial = #"{"schema_version":3,"global_status":"idle","lamp_status":"idle","generated_at":"2026-06-11T00:00:00Z","updated_at":"2026-06-11T00:00:00Z","counts":{},"tasks":[],"invalid_tasks":[]}"#
try atomicWrite(initial, to: stateURL)

let descriptor = open(stateDir.path, O_EVTONLY)
guard descriptor >= 0 else {
    fputs("failed to open state dir\n", stderr)
    exit(2)
}

let queue = DispatchQueue(label: "tasklight.ui.refresh.latency")
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: descriptor,
    eventMask: [.write, .rename, .delete, .extend, .attrib],
    queue: queue
)
let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var observed: DispatchTime?

source.setEventHandler {
    lock.lock()
    if observed == nil {
        observed = DispatchTime.now()
        semaphore.signal()
    }
    lock.unlock()
}
source.setCancelHandler {
    close(descriptor)
}
source.resume()

let updated = #"{"schema_version":3,"global_status":"running","lamp_status":"running","generated_at":"2026-06-11T00:00:00Z","updated_at":"2026-06-11T00:00:01Z","counts":{"running":1},"tasks":[],"invalid_tasks":[]}"#
let started = DispatchTime.now()
try atomicWrite(updated, to: stateURL)

if semaphore.wait(timeout: .now() + 2) == .timedOut {
    source.cancel()
    fputs("ui_refresh_latency_ms=timeout\n", stderr)
    exit(1)
}

lock.lock()
let ended = observed ?? DispatchTime.now()
lock.unlock()
source.cancel()

let milliseconds = Double(ended.uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
print(String(format: "ui_refresh_latency_ms=%.2f", milliseconds))
if milliseconds > maxMilliseconds {
    fputs("expected ui refresh latency <= \(maxMilliseconds) ms\n", stderr)
    exit(1)
}
print("smoke_ui_refresh_latency: ok")
SWIFT

swift "$SWIFT_FILE" "$MAX_MS"
