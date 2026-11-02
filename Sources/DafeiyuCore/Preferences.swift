import Foundation

public enum PerformanceMode: String, Codable, CaseIterable {
    case economy, balanced, smooth
    public var title: String { switch self { case .economy: return "节能"; case .balanced: return "均衡"; case .smooth: return "流畅" } }
}
public enum CompanionStyle: String, Codable, CaseIterable {
    case quiet, natural, lively, custom
    public var title: String { switch self { case .quiet: return "安静"; case .natural: return "自然"; case .lively: return "活泼"; case .custom: return "自定义" } }
}
public enum Story: String, Codable, CaseIterable {
    case eating, begging, explosion
    public var title: String { switch self { case .eating: return "偷吃白饭"; case .begging: return "讨白饭"; case .explosion: return "炸饭盆" } }
}

public struct Preferences: Codable, Equatable {
    public var schemaVersion = 1
    public var scale = 1.0
    public var appearance = "system"
    public var accent = "fish"
    public var displayID: UInt32 = 0
    public var allSpaces = false
    public var hideInFullscreen = true
    public var desktopOnly = false
    public var gaze = true
    public var wave = true
    public var touch = true
    public var draggable = true
    public var runWhileDragging = true
    public var steal = true
    public var throwing = true
    public var guarding = true
    public var bowlHits = true
    public var kickBowl = true
    public var petting = true
    public var perchOnWindows = true
    public var hangOnWindows = true
    public var sitOnWindows = true
    /// 0 off, 1 occasionally, 2 normal, 3 often.
    public var wanderLevel = 2
    public var climbWindows = true
    public var dockPeek = true
    public var feeding = true
    public var napMinutes = 5
    public var dailyRhythm = true
    public var breakMinutes = 0
    public var quotaMood = true
    public var aiCompanion = true
    public var menuBarQuota = true
    public var following = false
    public var jumpShortcut = true
    public var jumpKey = "J"
    public var companionStyle: CompanionStyle = .natural
    public var speechEnabled = true
    public var speechStyle: SpeechStyle = .soft
    public var customSpeech: [String: String] = [:]
    public var chaseSpeed = 1.0
    public var chaseDuration = 12.0
    public var anger = true
    public var tears = true
    public var emotionStrength = 0.35
    public var recoveryDuration = 10.0
    public var eating = true
    public var begging = true
    public var explosion = true
    public var ambientMin = 45.0
    public var ambientMax = 90.0
    public var eatingDuration = 6.0
    public var explosionDuration = 4.5
    public var explosionHeight = 0.45
    public var bounce = 0.35
    public var effects = 0.35
    public var claudeEnabled = true
    public var codexEnabled = true
    public var showShortWindow = true
    public var showLongWindow = true
    public var hideIdentity = true
    public var refreshMinutes = 5
    public var refreshOnOpen = true
    public var bowlQuotaSource = "codex"
    public var bowlQuotaWindow = "automatic"
    public var bowlQuotaLabel = true
    public var lowQuotaReminder = false
    public var lowQuotaThreshold = 20.0
    public var resetReminder = false
    public var resetSurprise = true
    public var celebration = false
    public var celebrationDuration = 3.0
    public var performance: PerformanceMode = .balanced
    public var frameLimit = 60
    public var automaticEnergySaving = true
    public var respectReduceMotion = true
    public var launchAtLogin = false
    public var shortcutVisibility = true
    public var shortcutQuiet = true
    public var shortcutPause = true
    public var visibilityKey = "F"
    public var quietKey = "M"
    public var pauseKey = "P"
    public var lastPane = "appearance"
    public var positionX: Double?
    public var positionY: Double?
    public init() {}

    public var stories: [Story] {
        Story.allCases.filter { switch $0 { case .eating: return eating; case .begging: return begging; case .explosion: return explosion } }
    }
    public mutating func normalize() {
        customSpeech = customSpeech.filter { SpeechCue(rawValue: $0.key) != nil }.mapValues(BubbleText.clean)
        scale = bounded(scale, 0.75, 1.5, fallback: 1)
        chaseSpeed = bounded(chaseSpeed, 0.5, 1.8, fallback: 1)
        chaseDuration = bounded(chaseDuration, 5, 30, fallback: 12)
        emotionStrength = bounded(emotionStrength, 0, 1, fallback: 0.35)
        recoveryDuration = bounded(recoveryDuration, 3, 30, fallback: 10)
        ambientMin = bounded(ambientMin, 15, 600, fallback: 45)
        ambientMax = max(ambientMin, bounded(ambientMax, 15, 600, fallback: 90))
        eatingDuration = bounded(eatingDuration, 3, 12, fallback: 6)
        explosionDuration = bounded(explosionDuration, 3, 7, fallback: 4.5)
        explosionHeight = bounded(explosionHeight, 0.15, 0.8, fallback: 0.45)
        bounce = bounded(bounce, 0, 0.7, fallback: 0.35)
        effects = bounded(effects, 0, 1, fallback: 0.35)
        lowQuotaThreshold = bounded(lowQuotaThreshold, 5, 50, fallback: 20)
        celebrationDuration = bounded(celebrationDuration, 2, 6, fallback: 3)
        if ![0, 2, 5, 15].contains(refreshMinutes) { refreshMinutes = 5 }
        if ![30, 60].contains(frameLimit) { frameLimit = 60 }
        if ![0, 2, 5, 10].contains(napMinutes) { napMinutes = 5 }
        if !(0...3).contains(wanderLevel) { wanderLevel = 2 }
        if ![0, 25, 45, 60].contains(breakMinutes) { breakMinutes = 0 }
        if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
        if !["off", "codex", "claude"].contains(bowlQuotaSource) { bowlQuotaSource = "codex" }
        if !["automatic", "short", "long"].contains(bowlQuotaWindow) { bowlQuotaWindow = "automatic" }
        for key in [\Preferences.visibilityKey, \Preferences.quietKey, \Preferences.pauseKey, \Preferences.jumpKey] {
            if self[keyPath: key].count != 1 || !"ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(self[keyPath: key]) {
                self[keyPath: key] = Preferences()[keyPath: key]
            }
        }
        if positionX?.isFinite == false { positionX = nil }
        if positionY?.isFinite == false { positionY = nil }
    }
    public mutating func applyStyle(_ style: CompanionStyle) {
        companionStyle = style
        switch style {
        case .quiet: ambientMin = 180; ambientMax = 300; chaseSpeed = 0.7; emotionStrength = 0.2
        case .natural: ambientMin = 45; ambientMax = 90; chaseSpeed = 1; emotionStrength = 0.35
        case .lively: ambientMin = 20; ambientMax = 45; chaseSpeed = 1.3; emotionStrength = 0.65
        case .custom: break
        }
    }
    public static func decodeMigrating(_ data: Data) throws -> Preferences {
        let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let incoming else { throw PreferencesError.invalidFile }
        if let version = incoming["schemaVersion"] as? Int, version > 1 { throw PreferencesError.newerVersion }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
        let merged = defaults.merging(incoming) { _, new in new }
        var result = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: merged))
        result.normalize()
        return result
    }
    public func exportData() throws -> Data {
        var portable = self
        portable.launchAtLogin = false
        portable.positionX = nil; portable.positionY = nil; portable.displayID = 0
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(portable)
    }
}
public enum PreferencesError: LocalizedError {
    case invalidFile, newerVersion
    public var errorDescription: String? { self == .newerVersion ? "这份设置来自更新版本，请先更新大肥鱼。" : "无法识别这份设置文件。" }
}
private func bounded(_ x: Double, _ low: Double, _ high: Double, fallback: Double) -> Double {
    x.isFinite ? min(high, max(low, x)) : fallback
}
