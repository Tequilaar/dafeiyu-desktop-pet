import Foundation

/// Bounded active-frame timings. Idle gaps are not counted as dropped frames.
public struct FrameTiming {
    private var samples: [Double] = []
    private var next = 0
    private var previous: Double?
    public init() {}
    public mutating func resumeAfterIdle() { previous = nil }
    public mutating func record(_ timestamp: Double) {
        defer { previous = timestamp }
        guard timestamp.isFinite, let previous else { return }
        let dt = timestamp - previous
        guard dt > 0 else { return }
        if samples.count < 240 { samples.append(dt) }
        else { samples[next] = dt; next = (next + 1) % 240 }
    }
    public var framesPerSecond: Double { samples.isEmpty ? 0 : Double(samples.count) / samples.reduce(0, +) }
    public var p95Milliseconds: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.sorted()[min(samples.count - 1, Int(Double(samples.count) * 0.95))] * 1000
    }
    public var sampleCount: Int { samples.count }
}
