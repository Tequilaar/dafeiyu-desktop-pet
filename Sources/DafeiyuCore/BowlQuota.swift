import Foundation

public struct BowlQuotaReading: Equatable {
    public let fraction: Double?
    public let label: String
    public let detail: String
    public let stale: Bool

    public static func make(preferences p: Preferences, snapshot: QuotaSnapshot?, loading: Bool = false,
                            failed: Bool = false, now: Date = Date()) -> BowlQuotaReading? {
        let source = p.bowlQuotaSource
        guard source != "off" else { return nil }
        let name = source == "claude" ? "Claude" : "Codex"
        func unknown(_ reason: String) -> Self {
            .init(fraction: nil, label: name + " —", detail: name + "：" + reason, stale: false)
        }
        guard source == "claude" ? p.claudeEnabled : p.codexEnabled else { return unknown("额度读取已关闭") }
        guard let snapshot, snapshot.provider == source else { return unknown(loading ? "正在读取额度" : "尚未获取额度") }
        let windows = snapshot.windows.filter { $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }
        let short = windows.filter { !$0.isLong }.sorted { ($0.durationMinutes ?? 300) < ($1.durationMinutes ?? 300) }
        let long = windows.filter(\.isLong).sorted { ($0.durationMinutes ?? 10080) < ($1.durationMinutes ?? 10080) }
        let window: QuotaWindow?
        switch p.bowlQuotaWindow {
        case "short": window = short.first
        case "long": window = long.first
        default: window = short.first ?? long.first
        }
        guard let window else {
            return unknown(p.bowlQuotaWindow == "short" ? "来源未提供短周期额度" : p.bowlQuotaWindow == "long" ? "来源未提供长周期额度" : "来源未提供额度窗口")
        }
        // Never invent a full bowl when a previously observed reset time passes.
        if let reset = window.resetsAt, reset <= now { return unknown(window.title + "已到重置时间，等待更新") }
        let stale = failed || now.timeIntervalSince(snapshot.fetchedAt) > max(900, Double(p.refreshMinutes * 120))
        let amount = window.remaining
        let percent = amount > 0 && amount < 1 ? "<1%" : "\(Int(amount.rounded()))%"
        return .init(fraction: amount / 100, label: name + " " + percent + (stale ? " ·旧" : ""),
                     detail: name + " · " + window.title + " · 剩余 " + percent + (stale ? "（上次读取，待更新）" : ""), stale: stale)
    }
}
