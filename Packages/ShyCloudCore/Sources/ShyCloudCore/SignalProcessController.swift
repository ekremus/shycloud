import Darwin
import Dispatch

/// SIGSTOP/SIGCONT engine. Idempotent: safe to call pause/resume every tick.
@MainActor
public final class SignalProcessController: ProcessControlling {
    public var onPausedProcessExit: (@MainActor () -> Void)?

    private let inspector: any ProcessInspecting
    private let signaler: any Signaling
    private let watchExits: Bool
    private var paused: Set<ProcessIdentity> = []
    private var exitSources: [ProcessIdentity: any DispatchSourceProcess] = [:]

    public init(
        inspector: any ProcessInspecting = DarwinProcessInspector(),
        signaler: any Signaling = DarwinSignaler(),
        watchExits: Bool = true
    ) {
        self.inspector = inspector
        self.signaler = signaler
        self.watchExits = watchExits
    }

    public func pause(_ targets: [PauseTarget]) {
        for target in PauseTarget.pauseOrder where targets.contains(target) {
            for id in inspector.processes(for: target) {
                // Re-verify identity immediately before signalling (pid reuse).
                guard inspector.target(of: id) == target else { continue }
                if signaler.send(SIGSTOP, to: id.pid) {
                    paused.insert(id)
                    watchExit(of: id)
                }
            }
        }
    }

    public func resume(_ targets: [PauseTarget]) {
        for target in PauseTarget.resumeOrder where targets.contains(target) {
            // Tracked ids (even if a scan misses them) plus freshly listed ones.
            var candidates = Set(inspector.processes(for: target))
            for id in paused where inspector.target(of: id) == target {
                candidates.insert(id)
            }
            for id in candidates.sorted(by: { $0.pid < $1.pid }) {
                // Re-verify identity immediately before signalling (pid reuse).
                guard inspector.target(of: id) == target else { continue }
                if signaler.send(SIGCONT, to: id.pid) {
                    paused.remove(id)
                }
            }
        }
        // Drop tracked ids whose process is really gone.
        paused = paused.filter { id in
            inspector.target(of: id) != nil || inspector.isStopped(id)
        }
        for (id, source) in exitSources where !paused.contains(id) {
            source.cancel()
            exitSources[id] = nil
        }
    }

    public func pausedProcesses() -> [ProcessIdentity] {
        paused.filter { inspector.isStopped($0) }.sorted { $0.pid < $1.pid }
    }

    func processDidExit(_ id: ProcessIdentity) {
        exitSources[id]?.cancel()
        exitSources[id] = nil
        guard paused.remove(id) != nil else { return }
        onPausedProcessExit?()
    }

    private func watchExit(of id: ProcessIdentity) {
        guard watchExits, exitSources[id] == nil else { return }
        let source = DispatchSource.makeProcessSource(identifier: id.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.processDidExit(id)
            }
        }
        exitSources[id] = source
        source.resume()
    }
}
