import AppKit
import Combine
import ServiceManagement
import DafeiyuCore

@MainActor final class AppModel: ObservableObject {
    @Published var preferences: Preferences { didSet { if !loading { changed() } } }
    @Published var quiet = false
    @Published var paused = false
    @Published var hidden = false
    @Published var status = "在这里陪你"
    @Published var notice: String?
    @Published var diagnostics = ""
    var onPreferences: (() -> Void)?
    var onPreview: ((Story) -> Void)?
    var onSpeechPreview: ((SpeechCue) -> Void)?
    var onGazePreview: (() -> Void)?
    var onResetPosition: (() -> Void)?
    var onVisibility: (() -> Void)?
    private var loading = false
    private var pendingSave: DispatchWorkItem?
    let directory: URL
    let settingsURL: URL
    init(isolated: Bool = false, testDirectory: String? = nil) {
        if isolated {
            directory = URL(fileURLWithPath: testDirectory ?? ProcessInfo.processInfo.environment["DAFEIYU_TEST_HOME"] ?? NSTemporaryDirectory() + "dafeiyu-smoke-data")
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dafeiyu")
        }
        settingsURL = directory.appendingPathComponent("preferences.json")
        preferences = (try? Data(contentsOf: settingsURL)).flatMap { try? Preferences.decodeMigrating($0) } ?? Preferences()
    }
    private func changed() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        onPreferences?()
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: settingsURL, options: .atomic)
        } catch { notice = "设置暂时没有保存成功：\(error.localizedDescription)" }
    }
    func importPreferences(from url: URL) {
        do {
            var imported = try Preferences.decodeMigrating(Data(contentsOf: url))
            imported.launchAtLogin = preferences.launchAtLogin
            preferences = imported; save(); notice = "设置已导入。"
        } catch { notice = error.localizedDescription }
    }
    func exportPreferences(to url: URL) {
        do { try preferences.exportData().write(to: url, options: .atomic) }
        catch { notice = error.localizedDescription }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.launchAtLogin = enabled
            if SMAppService.mainApp.status == .requiresApproval { notice = "请在系统设置的登录项中允许大肥鱼启动。" }
        } catch { notice = "登录项未改变：\(error.localizedDescription)" }
    }
    func resetPage(_ page: String) {
        let keys: [String: [String]] = [
            "appearance": ["scale", "appearance", "accent", "displayID", "allSpaces", "hideInFullscreen", "desktopOnly"],
            "interaction": ["gaze", "wave", "touch", "draggable", "runWhileDragging", "steal", "throwing", "guarding", "bowlHits", "kickBowl", "petting", "perchOnWindows", "hangOnWindows", "sitOnWindows", "wanderLevel", "climbWindows", "dockPeek", "feeding", "napMinutes", "dailyRhythm", "breakMinutes", "quotaMood", "aiCompanion", "following", "jumpShortcut", "companionStyle", "chaseSpeed", "chaseDuration", "anger", "tears", "emotionStrength", "recoveryDuration"],
            "speech": ["speechEnabled", "speechStyle", "customSpeech"],
            "animation": ["eating", "begging", "explosion", "ambientMin", "ambientMax", "eatingDuration", "explosionDuration", "explosionHeight", "bounce", "effects"],
            "quota": ["claudeEnabled", "codexEnabled", "showShortWindow", "showLongWindow", "hideIdentity", "refreshMinutes", "refreshOnOpen", "bowlQuotaSource", "bowlQuotaWindow", "bowlQuotaLabel", "menuBarQuota", "lowQuotaReminder", "lowQuotaThreshold", "resetReminder", "resetSurprise", "celebration", "celebrationDuration"],
            "performance": ["performance", "frameLimit", "automaticEnergySaving", "respectReduceMotion"],
            "general": ["shortcutVisibility", "shortcutQuiet", "shortcutPause", "visibilityKey", "quietKey", "pauseKey", "jumpKey", "jumpShortcut"]
        ]
        do {
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
            var current = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
            for key in keys[page] ?? [] { current[key] = defaults[key] }
            preferences = try Preferences.decodeMigrating(JSONSerialization.data(withJSONObject: current))
        } catch { notice = "这页设置暂时无法恢复。" }
    }
    func resetAll() {
        let launch = preferences.launchAtLogin
        var defaults = Preferences(); defaults.launchAtLogin = launch
        preferences = defaults
    }
}
