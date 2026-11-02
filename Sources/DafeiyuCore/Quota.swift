import Foundation

public struct QuotaWindow: Identifiable, Codable, Equatable {
    public var id: String
    public var usedPercent: Double
    public var durationMinutes: Int?
    public var resetsAt: Date?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var title: String {
        guard let minutes = durationMinutes else { return id == "primary" ? "当前窗口" : "较长窗口" }
        if minutes == 300 { return "五小时" }; if minutes == 10080 { return "七天" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
    public var isLong: Bool { (durationMinutes ?? (id == "secondary" ? 10080 : 300)) > 1440 }
}
public struct QuotaSnapshot: Codable, Equatable {
    public var provider: String
    public var account: String?
    public var windows: [QuotaWindow]
    public var fetchedAt: Date
    public var source: String
}
public enum QuotaFailure: LocalizedError {
    case unavailable(String), invalid
    public var errorDescription: String? {
        switch self { case .unavailable(let detail): return detail; case .invalid: return "额度数据格式暂不支持。" }
    }
}
public enum QuotaParser {
    public static func parse(_ data: Data, provider: String, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try JSONSerialization.jsonObject(with: data)
        let entries = (root as? [[String: Any]]) ?? (root as? [String: Any]).map { [$0] } ?? []
        guard let entry = entries.first(where: { ($0["provider"] as? String) == provider }) ?? entries.first(where: { $0["provider"] == nil }) else { throw QuotaFailure.invalid }
        if entry["error"] != nil { throw QuotaFailure.unavailable("暂时无法读取，请检查本机账号连接。") }
        let usage = entry["usage"] as? [String: Any] ?? entry
        var windows: [QuotaWindow] = []
        for key in ["primary", "secondary", "tertiary"] {
            guard let value = usage[key] as? [String: Any], let used = value["usedPercent"] as? Double, used.isFinite, used >= 0, used <= 100 else { continue }
            windows.append(.init(id: key, usedPercent: used,
                                 durationMinutes: (value["windowMinutes"] ?? value["windowDurationMins"]) as? Int,
                                 resetsAt: parseDate(value["resetsAt"])))
        }
        guard !windows.isEmpty else { throw QuotaFailure.unavailable("来源尚未提供可显示的额度窗口。") }
        let identity = usage["identity"] as? [String: Any] ?? entry["identity"] as? [String: Any]
        let account = identity?["accountEmail"] as? String ?? usage["accountEmail"] as? String
        return .init(provider: provider, account: account, windows: windows,
                     fetchedAt: parseDate(usage["updatedAt"]) ?? now, source: entry["source"] as? String ?? "直接接入")
    }
    public static func parseCodex(_ data: Data, account: String? = nil) throws -> QuotaSnapshot {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaFailure.invalid }
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        // Prefer the actual Codex bucket; never relabel a different service as Codex.
        guard var bucket = buckets?["codex"] ?? (result["rateLimits"] as? [String: Any]) else { throw QuotaFailure.invalid }
        if let account { bucket["accountEmail"] = account }
        return try parse(JSONSerialization.data(withJSONObject: ["provider": "codex", "source": "Codex app-server", "usage": bucket]), provider: "codex")
    }
    public static func parseClaude(_ data: Data, account: String? = nil) throws -> QuotaSnapshot {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaFailure.invalid }
        var usage: [String: Any] = [:]
        for (remote, local, minutes) in [("five_hour", "primary", 300), ("seven_day", "secondary", 10080)] {
            guard let value = result[remote] as? [String: Any] else { continue }
            var window: [String: Any] = ["windowMinutes": minutes]
            window["usedPercent"] = value["utilization"]; window["resetsAt"] = value["resets_at"]
            usage[local] = window
        }
        if let account { usage["accountEmail"] = account }
        return try parse(JSONSerialization.data(withJSONObject: ["provider": "claude", "source": "Claude OAuth", "usage": usage]), provider: "claude")
    }
    public static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? Double { return Date(timeIntervalSince1970: number) }
        guard let string = value as? String else { return nil }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: string) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: string)
    }
}

public struct QuotaReceipts: Codable {
    public var boundaries: [String: Date] = [:]
    public var lowEpisodes: Set<String> = []
    public init() {}
    public mutating func observe(_ snapshot: QuotaSnapshot, threshold: Double) -> (reset: Bool, low: Bool) {
        var reset = false, low = false
        for window in snapshot.windows {
            let key = "\(snapshot.provider)|\(snapshot.account ?? "default")|\(window.id)"
            if let boundary = window.resetsAt {
                if let previous = boundaries[key], boundary > previous.addingTimeInterval(60), snapshot.fetchedAt >= previous { reset = true; lowEpisodes.remove(key) }
                boundaries[key] = boundary
            }
            if window.remaining < threshold {
                if !lowEpisodes.contains(key) { low = true; lowEpisodes.insert(key) }
            } else { lowEpisodes.remove(key) }
        }
        return (reset, low)
    }
}
