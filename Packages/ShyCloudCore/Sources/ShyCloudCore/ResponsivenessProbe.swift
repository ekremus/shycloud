import Dispatch
import Foundation

/// Asks iCloud something trivial to prove apps are not hanging on it. Injected so tests never make real calls.
@MainActor
public protocol ResponsivenessProbe: AnyObject {
    /// Starts one call off the main thread. `answered` runs on the main actor when the call returns,
    /// which is never if iCloud hangs (the caller owns the timeout).
    func ping(answered: @escaping @MainActor @Sendable () -> Void)
}

/// Calls `FileManager.ubiquityIdentityToken`, the synchronous XPC call to `bird` that
/// Chromium/CEF apps make at launch (see `scripts/ubiquity-probe.swift`).
@MainActor
public final class UbiquityProbe: ResponsivenessProbe {
    public init() {}

    public func ping(answered: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            _ = FileManager.default.ubiquityIdentityToken
            DispatchQueue.main.async {
                MainActor.assumeIsolated { answered() }
            }
        }
    }
}
