import Foundation
import Testing
@testable import DafeiyuCore

struct ChartSamplingTests {
    @Test func largeHistoryKeepsSpikesAndEndpointsWithinDisplayBudget() {
        var points = (0..<10_000).map { UsagePoint(time: Date(timeIntervalSince1970: Double($0)), used: 40, reset: nil) }
        points[1234].used = 99; points[4567].used = 2
        let sampled = QuotaHistory.chartPoints(points)
        #expect(sampled.count <= 600)
        #expect(sampled.first == points.first && sampled.last == points.last)
        #expect(sampled.contains(points[1234]) && sampled.contains(points[4567]))
        #expect(zip(sampled, sampled.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect(points.count == 10_000)
    }
    @Test func smallHistoriesRemainExact() {
        let points = (0..<10).map { UsagePoint(time: Date(timeIntervalSince1970: Double($0)), used: Double($0), reset: nil) }
        #expect(QuotaHistory.chartPoints(points) == points)
        #expect(QuotaHistory.chartPoints([]).isEmpty)
        #expect(QuotaHistory.chartPoints(points, limit: 0).count <= 4)
    }
}
