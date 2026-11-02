import Testing
@testable import DafeiyuCore

struct FrameTimingTests {
    @Test func measuresActualCadenceAndIgnoresIdleGaps() {
        var timing = FrameTiming()
        for i in 0...300 { timing.record(Double(i) / 60) }
        #expect(abs(timing.framesPerSecond - 60) < 0.01)
        #expect(abs(timing.p95Milliseconds - 1000 / 60) < 0.01)
        #expect(timing.sampleCount == 240)
        timing.resumeAfterIdle(); timing.record(30)
        #expect(abs(timing.framesPerSecond - 60) < 0.01)
        for i in 1...300 { timing.record(30 + Double(i) / 30) }
        #expect(abs(timing.framesPerSecond - 30) < 0.01)
        timing.record(40.5)
        #expect(timing.framesPerSecond < 29, "A real half-second stall must not be discarded")
    }
}
