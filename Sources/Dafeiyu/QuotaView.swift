import SwiftUI
import Charts
import DafeiyuCore

private typealias CardState<Value> = SwiftUI.State<Value>

struct QuotaCard: View {
    @CardState private var showTrends = false
    @CardState private var trendLong = true
    @ObservedObject var model: AppModel
    @ObservedObject var quota: QuotaStore
    let portrait: NSImage?
    var openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let portrait { Image(nsImage: portrait).resizable().scaledToFit().frame(width: 46, height: 50) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("大肥鱼的小饭票").font(.headline)
                    Text("看看今天还剩多少饭").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { quota.refresh() } label: {
                    if quota.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(.borderless).disabled(quota.isRefreshing).help("刷新额度")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showTrends {
                        Picker("趋势窗口", selection: $trendLong) { Text("短周期").tag(false); Text("长周期").tag(true) }.pickerStyle(.segmented)
                    }
                    if model.preferences.claudeEnabled { provider("claude", title: "Claude", symbol: "sun.max") }
                    if model.preferences.codexEnabled { provider("codex", title: "Codex", symbol: "chevron.left.forwardslash.chevron.right") }
                    if !model.preferences.claudeEnabled && !model.preferences.codexEnabled {
                        Text("在设置中选择要显示的服务。").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(360, max(180, (NSScreen.main?.visibleFrame.height ?? 800) - 260)))
            Button(showTrends ? "收起消耗趋势" : "消耗趋势与预估") { showTrends.toggle() }.font(.caption)
            Divider()
            HStack {
                Button { model.quiet.toggle() } label: { Label(model.quiet ? "恢复陪伴" : "安静陪伴", systemImage: model.quiet ? "sparkles" : "moon") }
                Button { model.paused.toggle() } label: { Image(systemName: model.paused ? "play" : "pause") }.help(model.paused ? "继续互动" : "暂停互动")
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }.help("设置")
            }.controlSize(.small)
        }
        .padding(20).frame(width: 390).tint(Color(red: 0.25, green: 0.46, blue: 0.77))
    }
    @ViewBuilder private func provider(_ id: String, title: String, symbol: String) -> some View {
        let state = quota.providers[id] ?? ProviderStatus()
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                Spacer()
                if state.loading { ProgressView().controlSize(.mini) }
                if state.error != nil, state.snapshot != nil { Text("历史数据").font(.caption2).foregroundStyle(.orange) }
            }
            if let snapshot = state.snapshot {
                if !model.preferences.hideIdentity, let account = snapshot.account { Text(account).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                ForEach(snapshot.windows.filter { $0.isLong ? model.preferences.showLongWindow : model.preferences.showShortWindow }) { window in
                    VStack(spacing: 4) {
                        HStack {
                            Text(window.title)
                            Spacer()
                            Text("剩余 \(Int(window.remaining.rounded()))%").monospacedDigit()
                        }.font(.caption)
                        ProgressView(value: window.remaining, total: 100).tint(window.remaining < 20 ? .orange : .accentColor)
                        if let reset = window.resetsAt {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(QuotaTimeText.exact(reset)) 重置")
                                    Text(QuotaTimeText.remaining(until: reset, now: context.date))
                                }.font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if showTrends { trend(snapshot) }
                Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(state.loading ? "正在查看饭票…" : "暂未获取额度").font(.caption).foregroundStyle(.secondary)
            }
            if let error = state.error { Text(error).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private func trend(_ snapshot: QuotaSnapshot) -> some View {
        let window = snapshot.windows.first(where: { $0.isLong == trendLong })
        if let window {
            let points = quota.history.points(for: snapshot, window: window)
            let recent = points.filter { $0.reset == window.resetsAt }
            let forecast = QuotaHistory.forecast(points, remaining: window.remaining, reset: window.resetsAt)
            if recent.count >= 2 {
                Chart(QuotaHistory.chartPoints(recent)) { point in
                    LineMark(x: .value("时间", point.time), y: .value("已用", point.used)).interpolationMethod(.stepEnd)
                    PointMark(x: .value("时间", point.time), y: .value("已用", point.used)).symbolSize(10)
                }.chartYScale(domain: 0...100).frame(height: 74)
                Text("\(window.title)已用比例 · 只记录大肥鱼实际读取的结果").font(.caption2).foregroundStyle(.secondary)
            }
            if let rate = forecast.hourlyRate, rate > 0, let date = forecast.exhaustsAt {
                Text("约每小时消耗 \(rate, specifier: "%.1f")% · 预计 \(QuotaTimeText.exact(date)) 用完").font(.caption2)
                Text(forecast.enoughUntilReset == true ? "按当前速度，预计能用到下次重置" : "按当前速度，可能在重置前用完").font(.caption2).foregroundStyle(forecast.enoughUntilReset == true ? Color.secondary : Color.orange)
            }
            if let reset = window.resetsAt, reset > Date() {
                let allowance = window.remaining / max(0.01, reset.timeIntervalSinceNow / 3600)
                Text("用到重置前，平均每小时可消耗约 \(allowance, specifier: "%.1f")%").font(.caption2).foregroundStyle(.secondary)
            }
            Text(forecast.message + "；后续用量变化会影响结果。").font(.caption2).foregroundStyle(.secondary)
        } else { Text("来源尚未提供这个周期的额度。").font(.caption2).foregroundStyle(.secondary) }
    }

}
