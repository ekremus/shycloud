#!/usr/bin/env swift
// Measures how long iCloud takes to answer the synchronous call that Chromium/CEF apps
// (GeForce NOW, Steam, ...) make at launch: FileManager.ubiquityIdentityToken, an XPC call to `bird`.
// A frozen bird never answers, so those apps hang. While ShyCloud is paused this must stay under 3 s.
//
// Usage: swift scripts/ubiquity-probe.swift [timeoutSeconds]   (default 3)
// Prints the latency, or "HANG" and exits 1 when there is no answer within the timeout.

import Foundation

let arguments = CommandLine.arguments.dropFirst()
let timeout: Double
if let text = arguments.first {
    guard let value = Double(text), value.isFinite, value > 0 else {
        FileHandle.standardError.write(Data("usage: swift scripts/ubiquity-probe.swift [timeoutSeconds]\n".utf8))
        exit(2)
    }
    timeout = value
} else {
    timeout = 3
}

let answered = DispatchSemaphore(value: 0)
let start = DispatchTime.now()
DispatchQueue.global(qos: .userInitiated).async {
    _ = FileManager.default.ubiquityIdentityToken
    answered.signal()
}

if answered.wait(timeout: .now() + timeout) == .timedOut {
    print(String(format: "HANG: no answer within %.1f s", timeout))
    exit(1)
}
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
print(String(format: "%.3f s", elapsed))
