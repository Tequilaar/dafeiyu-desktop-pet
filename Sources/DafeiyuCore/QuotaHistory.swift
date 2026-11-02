import Foundation

public struct UsagePoint: Codable, Identifiable, Equatable {
    public var time: Date
    public var used: Double
    public var reset: Date?
    public var id: Date { time }
}
public struct UsageForecast: Equatable {
    public var hourlyRate: Double?
    public var exhaustsAt: Date?
    public var enoughUntilReset: Bool?
    public var sampleCount: Int
    public var message: String
}
public struct QuotaHistory: Codable {
    public var series: [String: [UsagePoint]] = [:]
    public init() {}
    public static func key(provider: String, account: String?, window: QuotaWindow) -> String {
        "\(provider)|\(account ?? "default")|\(window.durationMinutes ?? 0)|\(window.id)"
    }
    public mutating func record(_ snapshot: QuotaSnapshot) {
        for window in snapshot.windows {
            let key = Self.key(provider: snapshot.provider, account: snapshot.account, window: window)
            var points = series[key] ?? []
            // Coalesce manual refresh spam; retain at most 30 days and 10,000 points per window.
            if let last = points.last, snapshot.fetchedAt.timeIntervalSince(last.time) < 60 {
                points.removeLast()
            }
            points.append(.init(time: snapshot.fetchedAt, used: window.usedPercent, reset: window.resetsAt))
            series[key] = Array(points.filter { snapshot.fetchedAt.timeIntervalSince($0.time) <= 30 * 86400 }.suffix(10_000))
        }
        // Old accounts do not keep an unbounded history dictionary alive.
        series = series.filter { $0.value.last.map { snapshot.fetchedAt.timeIntervalSince($0.time) <= 30 * 86400 } ?? false }
    }
    public func points(for snapshot: QuotaSnapshot, window: QuotaWindow) -> [UsagePoint] {
        series[Self.key(provider: snapshot.provider, account: snapshot.account, window: window)] ?? []
    }
    /// Bound chart work without changing the history or forecast inputs. Keep
    /// each bucket's endpoints and extrema so short consumption spikes survive.
    public static func chartPoints(_ points: [UsagePoint], limit: Int = 600) -> [UsagePoint] {
        let limit = max(4, limit)
        guard points.count > limit else { return points }
        let bucketSize = Int(ceil(Double(points.count) / Double(limit / 4)))
        var selected: [UsagePoint] = []
        selected.reserveCapacity(limit)
        for start in stride(from: 0, to: points.count, by: bucketSize) {
            let end = min(points.count, start + bucketSize)
            var minimum = start, maximum = start
            for i in start..<end {
                if points[i].used < points[minimum].used { minimum = i }
                if points[i].used > points[maximum].used { maximum = i }
            }
            for index in Set([start, end - 1, minimum, maximum]).sorted() { selected.append(points[index]) }
        }
        return selected
    }
    public static func forecast(_ points: [UsagePoint], remaining: Double, reset: Date?, now: Date = Date()) -> UsageForecast {
        let sameWindow = points.filter { $0.reset == reset && now.timeIntervalSince($0.time) <= 24 * 3600 }
        guard let last = sameWindow.last, now.timeIntervalSince(last.time) <= 20 * 60 else {
            return .init(sampleCount: sameWindow.count, message: "需要新的额度记录")
        }
        // An observed decrease can mean a rollover or service correction: never bridge across it.
        var clean: [UsagePoint] = []
        for point in sameWindow { if let previous = clean.last, point.used < previous.used { clean.removeAll() }; clean.append(point) }
        guard clean.count >= 3, let first = clean.first, last.time.timeIntervalSince(first.time) >= 30 * 60 else {
            return .init(sampleCount: clean.count, message: "记录满 30 分钟且至少 3 次后估算")
        }
        let rate = (last.used - first.used) / (last.time.timeIntervalSince(first.time) / 3600)
        guard rate > 0.01 else { return .init(hourlyRate: 0, sampleCount: clean.count, message: "这段时间暂无明显消耗，暂不推算用完时间") }
        let exhaustion = last.time.addingTimeInterval(max(0, remaining) / rate * 3600)
        return .init(hourlyRate: rate, exhaustsAt: exhaustion, enoughUntilReset: reset.map { exhaustion >= $0 }, sampleCount: clean.count, message: "按最近记录的平均消耗速度估算")
    }
}

public enum QuotaTimeText {
    public static func exact(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"; return formatter.string(from: date)
    }
    public static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "等待来源确认重置" }
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        return "还剩 " + (days > 0 ? "\(days)天 " : "") + (hours > 0 || days > 0 ? "\(hours)小时 " : "") + "\(mins)分钟"
    }
}
