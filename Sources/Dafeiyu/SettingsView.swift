import SwiftUI
import UniformTypeIdentifiers
import DafeiyuCore

// The Command Line Tools SDK includes the original property wrapper but not
// the new SwiftUI State macro plugin. A type alias selects the wrapper explicitly.
private typealias StoredState<Value> = SwiftUI.State<Value>

private enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance, interaction, speech, animation, quota, performance, general
    var id: String { rawValue }
    var title: String { switch self { case .appearance: return "外观与位置"; case .interaction: return "陪伴与互动"; case .speech: return "气泡与台词"; case .animation: return "动画与剧情"; case .quota: return "额度与提醒"; case .performance: return "性能与省电"; case .general: return "通用" } }
    var icon: String { switch self { case .appearance: return "paintpalette"; case .interaction: return "hand.wave"; case .speech: return "text.bubble"; case .animation: return "sparkles"; case .quota: return "chart.bar"; case .performance: return "leaf"; case .general: return "gearshape" } }
    var keywords: String { switch self {
    case .appearance: return "大小 缩放 显示器 桌面 全屏 颜色 位置"
    case .interaction: return "鼠标 跳向 快捷键 追逐 速度 时长 生气 眼泪 恢复 抢盆 扔盆 护食 拖动 跳跃 摸头 窗口 喂饭 投喂 瞌睡 睡觉 作息 早安 休息 番茄钟 心情 AI 干活 走动 散步 爬墙 程序坞 图标 辅助功能"
    case .speech: return "语言 台词 语气 风格 自定义 擦脸 软萌 俏皮 嘴硬 简洁 文本 气泡"
    case .animation: return "偷吃 白饭 炸盆 高度 时间 持续 间隔 弹跳 特效 预览"
    case .quota: return "Claude Codex 账号 额度 饭票 刷新 余额 通知 庆祝 饭盆 米量 周期 菜单栏"
    case .performance: return "内存 GPU 帧率 节能 电量 减少运动"
    case .general: return "启动 登录 快捷键 导入 导出 恢复 版本"
    } }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var quota: QuotaStore
    let portrait: NSImage?
    let requestNotifications: () -> Void
    @StoredState private var selected: SettingsPane? = .appearance
    @StoredState private var query = ""
    @StoredState private var confirmReset = false
    @StoredState private var speechCue: SpeechCue = .wipeRequest
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if let portrait { Image(nsImage: portrait).resizable().scaledToFit().frame(width: 40, height: 48) }
                    VStack(alignment: .leading, spacing: 3) { Text("大肥鱼").font(.headline); Text("你的桌面小伙伴").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, 20)
                TextField("搜索设置", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                List(selection: $selected) {
                    ForEach(SettingsPane.allCases.filter { query.isEmpty || ($0.title + $0.keywords).localizedCaseInsensitiveContains(query) }) { pane in
                        Label(pane.title, systemImage: pane.icon).tag(pane).padding(.vertical, 5)
                    }
                }.listStyle(.sidebar)
                Text("独立版 · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")").font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 16)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((selected ?? .appearance).title).font(.title2.weight(.semibold))
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复本页") { model.resetPage((selected ?? .appearance).rawValue) }.controlSize(.small)
                }.padding(24)
                Divider()
                Form {
                    switch selected ?? .appearance {
                    case .appearance: appearance
                    case .interaction: interaction
                    case .speech: speechSettings
                    case .animation: animation
                    case .quota: quotaSettings
                    case .performance: performance
                    case .general: general
                    }
                    if let notice = model.notice {
                        Section { HStack { Text(notice).font(.callout); Spacer(); Button("知道了") { model.notice = nil } } }
                    }
                }.formStyle(.grouped)
            }.frame(minWidth: 470, idealWidth: 560)
        }
        .frame(minWidth: 740, minHeight: 620)
        .tint(model.preferences.accent == "fish" ? Color(red: 0.25, green: 0.46, blue: 0.77) : .accentColor)
        .onAppear { selected = SettingsPane(rawValue: model.preferences.lastPane) ?? .appearance }
        .onChange(of: selected) { _, pane in model.preferences.lastPane = pane?.rawValue ?? "appearance" }
        .onChange(of: query) { _, value in if !value.isEmpty, let match = SettingsPane.allCases.first(where: { ($0.title + $0.keywords).localizedCaseInsensitiveContains(value) }) { selected = match } }
        .alert("恢复所有设置？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) { model.resetAll() }
        } message: { Text("恢复外观、互动和额度显示偏好。账号连接与登录启动状态保持不变。") }
    }
    private var subtitle: String {
        switch selected ?? .appearance {
        case .appearance: return "在你的桌面上，找到舒服的位置。"
        case .interaction: return "想安静一点，还是一起闹腾？"
        case .speech: return "让小鱼用你喜欢的语气说话。"
        case .animation: return "饭慢慢吃，盆可以飞高一点。"
        case .quota: return "看清饭票，也留意什么时候补饭。"
        case .performance: return "陪伴久一点，负担轻一点。"
        case .general: return "让大肥鱼适应你的习惯。"
        }
    }
    private func bind<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: key] }, set: {
            var updated = model.preferences
            updated[keyPath: key] = $0
            if [\Preferences.chaseSpeed, \Preferences.emotionStrength, \Preferences.ambientMin, \Preferences.ambientMax].contains(where: { $0 == key }) {
                updated.companionStyle = .custom
            }
            if key == \Preferences.ambientMin || key == \Preferences.ambientMax {
                updated.ambientMax = max(updated.ambientMin, updated.ambientMax)
            }
            model.preferences = updated
        })
    }
    private func switchRow(_ title: String, _ key: WritableKeyPath<Preferences, Bool>) -> some View { Toggle(title, isOn: bind(key)) }
    private func slider(_ title: String, _ key: WritableKeyPath<Preferences, Double>, range: ClosedRange<Double>, unit: String = "秒", step: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title); Spacer(); Text(unit == "%" ? "\(Int(model.preferences[keyPath: key] * 100))%" : "\(model.preferences[keyPath: key], specifier: step < 1 ? "%.1f" : "%.0f") \(unit)").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: bind(key), in: range, step: step)
        }.padding(.vertical, 3)
    }
    private var appearance: some View {
        Group {
            Section("外观") {
                slider("角色大小", \.scale, range: 0.75...1.5, unit: "%", step: 0.05)
                Picker("界面", selection: bind(\.appearance)) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Picker("强调色", selection: bind(\.accent)) { Text("大肥鱼蓝").tag("fish"); Text("跟随系统").tag("system") }
            }
            Section("桌面与位置") {
                Picker("显示器", selection: bind(\.displayID)) {
                    Text("主显示器").tag(UInt32(0))
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        Text(screen.localizedName).tag(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0)
                    }
                }
                switchRow("在所有桌面显示", \.allSpaces)
                switchRow("全屏应用时隐藏", \.hideInFullscreen)
                switchRow("仅在桌面层显示", \.desktopOnly)
                Button("移回屏幕角落") { model.onResetPosition?() }
            }
        }
    }
    private var interaction: some View {
        Group {
            Section("陪伴风格") {
                Picker("风格", selection: Binding(get: { model.preferences.companionStyle }, set: { model.preferences.applyStyle($0) })) { ForEach(CompanionStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
                Text("风格会一起调整主动剧情间隔、追逐速度和情绪强度。性能模式独立设置。").font(.caption).foregroundStyle(.secondary)
                Toggle("现在安静陪伴", isOn: $model.quiet)
            }
            Section("鼠标与饭盆") {
                switchRow("视线跟随鼠标", \.gaze); switchRow("靠近时挥手", \.wave)
                Button("预览 32 向注视") { model.onGazePreview?() }.disabled(!model.preferences.gaze)
                switchRow("触摸时回应", \.touch); switchRow("允许拖动角色", \.draggable)
                switchRow("拖动时播放跑步", \.runWhileDragging).disabled(!model.preferences.draggable)
                switchRow("可以抢走饭盆", \.steal); switchRow("可以扔饭盆", \.throwing)
                switchRow("拿回饭盆后护食", \.guarding); switchRow("平时也跟着鼠标", \.following)
                switchRow("饭盆砸到身上会有反应", \.bowlHits).disabled(!model.preferences.throwing)
                switchRow("追逐时偶尔踢飞饭盆", \.kickBowl).disabled(!model.preferences.steal)
                switchRow("可以摸头（在头上来回划）", \.petting)
                switchRow("拖到窗口顶边时站在窗口上", \.perchOnWindows)
                switchRow("松手时窗口顶边在头顶附近就挂在边上", \.hangOnWindows)
                switchRow("站在窗口上一会儿后坐下晃腿", \.sitOnWindows).disabled(!model.preferences.perchOnWindows)
                switchRow("把文字或文件拖进饭盆喂她", \.feeding)
            }
            Section("日常陪伴") {
                Picker("你离开后打瞌睡", selection: bind(\.napMinutes)) { Text("关闭").tag(0); Text("2 分钟后").tag(2); Text("5 分钟后").tag(5); Text("10 分钟后").tag(10) }
                switchRow("按作息问候、深夜提醒早睡", \.dailyRhythm)
                Picker("连续使用后提醒休息", selection: bind(\.breakMinutes)) { Text("关闭").tag(0); Text("25 分钟").tag(25); Text("45 分钟").tag(45); Text("60 分钟").tag(60) }
                switchRow("饭盆额度影响心情", \.quotaMood)
                switchRow("陪你等 Codex／Claude 干活", \.aiCompanion)
                switchRow("启用跳向鼠标快捷键", \.jumpShortcut)
                Text("在通用设置中更改按键；无需点击其他应用窗口。").font(.caption).foregroundStyle(.secondary)
            }
            Section("自主走动") {
                Picker("自己在桌面上走走", selection: bind(\.wanderLevel)) { Text("关闭").tag(0); Text("偶尔").tag(1); Text("适中").tag(2); Text("经常").tag(3) }
                switchRow("窗口挨着屏幕底部时爬上去", \.climbWindows).disabled(model.preferences.wanderLevel == 0)
                switchRow("去看看程序坞里的图标", \.dockPeek).disabled(model.preferences.wanderLevel == 0)
                DockAccessRow()
                Text("你停下键盘和鼠标 8 秒后才会出发；全屏、安静陪伴或暂停时不走动。只读窗口位置和程序坞图标的位置与名称，不读窗口标题和内容。").font(.caption).foregroundStyle(.secondary)
            }
            Section("追逐与心情") {
                slider("追逐速度", \.chaseSpeed, range: 0.5...1.8, unit: "倍", step: 0.1)
                slider("最长追逐时间", \.chaseDuration, range: 5...30)
                switchRow("生气的表情", \.anger); switchRow("委屈时掉眼泪", \.tears)
                slider("情绪强度", \.emotionStrength, range: 0...1, unit: "%", step: 0.05)
                slider("心情恢复时间", \.recoveryDuration, range: 3...30)
            }
        }
    }
    private var speechSettings: some View {
        Group {
            Section("说话风格") {
                switchRow("显示互动气泡", \.speechEnabled)
                Picker("语气", selection: bind(\.speechStyle)) {
                    ForEach(SpeechStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(!model.preferences.speechEnabled)
                Text("预设台词会轮换。切换语气不会改变互动频率或性能模式。").font(.caption).foregroundStyle(.secondary)
            }
            Section(model.preferences.speechStyle == .custom ? "自定义台词" : "看看它会怎么说") {
                Picker("场景", selection: $speechCue) {
                    ForEach(SpeechCue.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if model.preferences.speechStyle == .custom {
                    TextField(SpeechStyle.soft.lines(for: speechCue)[0], text: Binding(
                        get: { model.preferences.customSpeech[speechCue.rawValue] ?? "" },
                        set: { model.preferences.customSpeech[speechCue.rawValue] = String($0.prefix(BubbleText.limit)) }
                    ), axis: .vertical).lineLimit(2...3)
                    Text("每个场景最多 28 个字。留空使用软萌台词；切换风格会保留你写的内容。").font(.caption).foregroundStyle(.secondary)
                }
                Text(model.preferences.speechEnabled ? model.preferences.speech(for: speechCue) : "气泡已关闭")
                    .font(.body).foregroundStyle(Color(red: 0.12, green: 0.2, blue: 0.32))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.94, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 12))
                Button("让大肥鱼说一句") { model.onSpeechPreview?(speechCue) }.disabled(!model.preferences.speechEnabled)
            }
        }
    }
    var animation: some View {
        Group {
            Section("自动小剧情") {
                switchRow("偷吃白饭", \.eating); switchRow("讨白饭", \.begging); switchRow("炸饭盆", \.explosion)
                slider("最短间隔", \.ambientMin, range: 15...600, step: 5)
                // A 600...600 stepped Slider traps inside SwiftUI. Keep a real
                // interval; the setting binding enforces max >= min atomically.
                slider("最长间隔", \.ambientMax, range: 15...600, step: 5)
                    .disabled(model.preferences.ambientMin >= 600)
                Text("每轮从开启的剧情中轮换，避免连续重复。").font(.caption).foregroundStyle(.secondary)
            }
            Section("节奏与饭盆") {
                slider("偷吃持续时间", \.eatingDuration, range: 3...12, step: 0.5).disabled(!model.preferences.eating)
                slider("炸盆持续时间", \.explosionDuration, range: 3...7, step: 0.5).disabled(!model.preferences.explosion)
                slider("飞行高度", \.explosionHeight, range: 0.15...0.8, unit: "%", step: 0.05).disabled(!model.preferences.explosion)
                Text("高度按角色上方可用空间计算。").font(.caption).foregroundStyle(.secondary)
                slider("落地弹跳", \.bounce, range: 0...0.7, unit: "%", step: 0.05)
                slider("特效强度", \.effects, range: 0...1, unit: "%", step: 0.05)
            }
            Section("预览一次") {
                HStack { ForEach(Story.allCases, id: \.self) { story in Button(story.title) { model.onPreview?(story) } } }
                Text("直接由桌面上的大肥鱼演示，关闭窗口不留下第二套动画。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var quotaSettings: some View {
        Group {
            Section("饭盆里的额度") {
                Picker("米量显示", selection: bind(\.bowlQuotaSource)) {
                    Text("Codex 剩余额度").tag("codex"); Text("Claude 剩余额度").tag("claude"); Text("关闭（普通饭盆）").tag("off")
                }
                Picker("额度周期", selection: bind(\.bowlQuotaWindow)) {
                    Text("自动：优先短周期").tag("automatic"); Text("五小时／短周期").tag("short"); Text("七天／长周期").tag("long")
                }.disabled(model.preferences.bowlQuotaSource == "off")
                switchRow("饭盆下方显示百分比", \.bowlQuotaLabel).disabled(model.preferences.bowlQuotaSource == "off")
                switchRow("菜单栏显示剩余额度", \.menuBarQuota).disabled(model.preferences.bowlQuotaSource == "off")
                let state = quota.providers[model.preferences.bowlQuotaSource]
                if let reading = BowlQuotaReading.make(preferences: model.preferences, snapshot: state?.snapshot, loading: state?.loading == true, failed: state?.error != nil) {
                    Text(reading.detail).font(.callout).foregroundStyle(reading.stale ? .orange : .secondary)
                }
                Text("剩余越多，米越满。自动模式优先使用短周期，未提供时显示长周期；没有数据时显示“—”，不会当成 0%。剧情结束后恢复额度显示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("饭票来源") {
                switchRow("显示 Claude", \.claudeEnabled); switchRow("显示 Codex", \.codexEnabled)
                LabeledContent("Codex 来源", value: "本机 Codex 登录")
                LabeledContent("Claude 来源", value: "本机 Claude 登录")
                Text("直接读取两家服务的额度。登录由各自的应用管理；大肥鱼不保存密码或令牌。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(["claude", "codex"], id: \.self) { id in
                    HStack {
                        Text(id == "claude" ? "Claude" : "Codex"); Spacer()
                        Text(quota.providers[id]?.loading == true ? "正在更新" : quota.providers[id]?.error != nil ? "需要检查连接" : quota.providers[id]?.snapshot != nil ? "已获取" : "尚未读取")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("立即刷新") { quota.refresh() }.disabled(quota.isRefreshing)
            }
            Section("显示与刷新") {
                switchRow("显示短周期额度", \.showShortWindow); switchRow("显示长周期额度", \.showLongWindow)
                switchRow("隐藏账号身份", \.hideIdentity)
                Picker("后台刷新", selection: bind(\.refreshMinutes)) { Text("仅手动").tag(0); Text("每 2 分钟").tag(2); Text("每 5 分钟").tag(5); Text("每 15 分钟").tag(15) }
                switchRow("打开卡片时更新过期数据", \.refreshOnOpen)
            }
            Section("提醒与庆祝") {
                switchRow("低额度时提醒", \.lowQuotaReminder).onChange(of: model.preferences.lowQuotaReminder) { _, enabled in if enabled { requestNotifications() } }
                slider("低额度阈值", \.lowQuotaThreshold, range: 5...50, unit: "% 剩余", step: 5).disabled(!model.preferences.lowQuotaReminder)
                switchRow("额度恢复时提醒", \.resetReminder).onChange(of: model.preferences.resetReminder) { _, enabled in if enabled { requestNotifications() } }
                switchRow("额度重置时米慢慢变满，她很惊喜", \.resetSurprise)
                switchRow("额度恢复时庆祝", \.celebration)
                slider("庆祝持续时间", \.celebrationDuration, range: 2...6, step: 0.5).disabled(!model.preferences.celebration)
            }
        }
    }
    private var performance: some View {
        Group {
            Section("性能模式") {
                Picker("模式", selection: bind(\.performance)) { ForEach(PerformanceMode.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text("均衡与流畅模式在转头、眨眼和互动时最高 60 fps，节能模式最高 30 fps。画面静止后暂停绘制。").font(.caption).foregroundStyle(.secondary)
                Picker("互动帧率上限", selection: bind(\.frameLimit)) { Text("30 fps").tag(30); Text("60 fps").tag(60) }.disabled(model.preferences.performance == .economy)
                switchRow("低电量模式下自动节能", \.automaticEnergySaving)
                switchRow("跟随系统的减少运动设置", \.respectReduceMotion)
            }
            Section("资源使用") {
                Text("目标：待机约 200～300 MB，普通互动峰值低于 400 MB，结束后回落。额度查询辅助进程同样计入。").font(.callout)
                Text("锁屏、休眠和隐藏时暂停动画；临时图集在使用后逐步释放。").font(.caption).foregroundStyle(.secondary)
                if !model.diagnostics.isEmpty { Text(model.diagnostics).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
        }
    }
    private func shortcut(_ title: String, enabled: WritableKeyPath<Preferences, Bool>, key: WritableKeyPath<Preferences, String>) -> some View {
        HStack {
            Toggle(title, isOn: bind(enabled)); Spacer(); Text("⌃⌥⌘").foregroundStyle(.secondary)
            Picker("按键", selection: bind(key)) { ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) } }
                .labelsHidden().frame(width: 70).disabled(!model.preferences[keyPath: enabled])
        }
    }
    private var general: some View {
        Group {
            Section("启动与快捷键") {
                Toggle("登录时启动", isOn: Binding(get: { model.preferences.launchAtLogin }, set: { model.setLogin($0) }))
                shortcut("显示或隐藏", enabled: \.shortcutVisibility, key: \.visibilityKey)
                shortcut("安静陪伴", enabled: \.shortcutQuiet, key: \.quietKey)
                shortcut("暂停或继续", enabled: \.shortcutPause, key: \.pauseKey)
                shortcut("跳向鼠标", enabled: \.jumpShortcut, key: \.jumpKey)
                Text("快捷键只在大肥鱼运行时注册；若已被其他应用占用，会显示提示。").font(.caption).foregroundStyle(.secondary)
            }
            Section("你的偏好") {
                HStack {
                    Button("导入设置…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { model.importPreferences(from: url) }
                    }
                    Button("导出设置…") {
                        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "大肥鱼设置.json"
                        if panel.runModal() == .OK, let url = panel.url { model.exportPreferences(to: url) }
                    }
                    Spacer(); Button("恢复全部默认…") { confirmReset = true }
                }
                Text("导出只包含偏好，不包含账号、额度历史或登录信息。").font(.caption).foregroundStyle(.secondary)
            }
            Section("关于大肥鱼") {
                LabeledContent("版本", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版") · 独立原生版")
                LabeledContent("动画", value: "原有角色素材 · SpriteKit")
                LabeledContent("额度", value: "Claude／Codex 直接接入")
                Button("退出大肥鱼") { NSApp.terminate(nil) }
            }
        }
    }
}

/// Accessibility status for Dock icons, with a button that shows macOS's own prompt and one that opens
/// the Accessibility list for when the prompt does not appear. The status rechecks itself every 2 s.
private struct DockAccessRow: View {
    @StoredState private var trusted = DockIcons.trusted
    private let recheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trusted ? "辅助功能权限：已开启" : "辅助功能权限：未开启（看图标需要）").foregroundStyle(trusted ? Color.secondary : Color.orange)
                Spacer()
                if !trusted {
                    Button("请求权限…") { DockIcons.requestAccess() }
                    Button("打开系统设置…") { DockIcons.openSettings() }
                }
            }
            if !trusted {
                Text("点“请求权限”没有弹窗：说明列表里还有旧的“大肥鱼”。在系统设置里选中它点“−”删掉，再点“请求权限”。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { trusted = DockIcons.trusted }
        .onReceive(recheck) { _ in trusted = DockIcons.trusted }
    }
}
