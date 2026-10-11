import Foundation
import Testing
@testable import ShyCloudCore

@MainActor
struct BreatherTests {
    final class Recorder {
        var log: [String] = []
    }

    func make() -> (Breather, FakeClock, FakeTimer, Recorder) {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let timer = clock.makeTimer(leeway: Breather.timerLeeway)
        let recorder = Recorder()
        let breather = Breather(
            timer: timer,
            release: { recorder.log.append("release") },
            restop: { recorder.log.append("restop") }
        )
        return (breather, clock, timer, recorder)
    }

    @Test func constantsMatchTheMeasuredDesign() {
        #expect(Breather.breathInterval == 2.0)
        #expect(Breather.breathDuration == 0.2)
        #expect(Breather.timerLeeway > 0 && Breather.timerLeeway <= 0.05)
    }

    @Test func releasesEveryIntervalForTheBreathDuration() {
        let (breather, clock, _, recorder) = make()
        breather.start()
        #expect(breather.isRunning)
        #expect(recorder.log.isEmpty)
        clock.advance(by: 1.79)
        #expect(recorder.log.isEmpty)
        clock.advance(by: 0.02) // 1.81 s: frozen for interval - duration, then released
        #expect(recorder.log == ["release"])
        #expect(breather.isReleased)
        clock.advance(by: 0.18) // 1.99 s: still breathing
        #expect(recorder.log == ["release"])
        clock.advance(by: 0.02) // 2.01 s: stopped again
        #expect(recorder.log == ["release", "restop"])
        #expect(!breather.isReleased)
    }

    @Test func cycleRepeatsEveryTwoSeconds() {
        let (breather, clock, _, recorder) = make()
        breather.start()
        clock.advance(by: 10.05)
        #expect(recorder.log == Array(repeating: ["release", "restop"], count: 5).flatMap { $0 })
    }

    @Test func startIsIdempotentAndDoesNotResetTheCycle() {
        let (breather, clock, _, recorder) = make()
        breather.start()
        clock.advance(by: 1.0)
        breather.start() // e.g. every 30 s tick re-applies
        clock.advance(by: 0.81)
        #expect(recorder.log == ["release"])
    }

    @Test func stopCancelsPendingRelease() {
        let (breather, clock, timer, recorder) = make()
        breather.start()
        clock.advance(by: 1.0)
        breather.stop()
        #expect(!breather.isRunning)
        #expect(timer.deadline == nil)
        clock.advance(by: 10)
        #expect(recorder.log.isEmpty)
    }

    @Test func stopMidBreathNeverRestops() {
        let (breather, clock, _, recorder) = make()
        breather.start()
        clock.advance(by: 1.9)
        #expect(breather.isReleased)
        breather.stop()
        #expect(!breather.isReleased)
        clock.advance(by: 10)
        #expect(recorder.log == ["release"])
    }

    @Test func restartBeginsAFreshCycle() {
        let (breather, clock, _, recorder) = make()
        breather.start()
        clock.advance(by: 1.0)
        breather.stop()
        breather.start()
        clock.advance(by: 1.0)
        #expect(recorder.log.isEmpty) // fresh 1.8 s freeze, not the old one
        clock.advance(by: 0.81)
        #expect(recorder.log == ["release"])
    }

    @Test func usesSmallLeeway() {
        let (_, _, timer, _) = make()
        #expect(timer.leeway == Breather.timerLeeway)
    }
}

@MainActor
struct DispatchOneShotTimerTests {
    @Test func firesOnceOnMain() async {
        let timer = DispatchOneShotTimer(leeway: 0.001)
        var fired = 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            timer.schedule(after: 0.01) {
                fired += 1
                continuation.resume()
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired == 1)
    }

    @Test func cancelAndRescheduleReplacePendingFire() async {
        let timer = DispatchOneShotTimer(leeway: 0.001)
        var log: [String] = []
        timer.schedule(after: 0.01) { log.append("first") }
        timer.cancel()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            timer.schedule(after: 0.02) { log.append("old") }
            timer.schedule(after: 0.03) {
                log.append("new")
                continuation.resume()
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(log == ["new"])
    }
}
