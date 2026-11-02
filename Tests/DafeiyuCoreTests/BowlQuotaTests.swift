import Foundation
import Testing
@testable import DafeiyuCore

@Suite struct BowlQuotaTests {
    let now = Date(timeIntervalSince1970: 100_000)
    func snapshot(_ provider: String = "codex", windows: [QuotaWindow]? = nil) -> QuotaSnapshot {
        .init(provider: provider, account: nil, windows: windows ?? [
            .init(id: "primary", usedPercent: 80, durationMinutes: 300, resetsAt: now.addingTimeInterval(3600)),
            .init(id: "secondary", usedPercent: 35, durationMinutes: 10080, resetsAt: now.addingTimeInterval(86400))
        ], fetchedAt: now, source: "fixture")
    }
    @Test func selectionUsesRemainingQuotaAndActualWindowRatherThanSlotName() {
        var p = Preferences()
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now)?.fraction == 0.2)
        p.bowlQuotaWindow = "long"
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now)?.fraction == 0.65)
        let weeklyOnly = snapshot(windows: [.init(id: "primary", usedPercent: 60, durationMinutes: 10080, resetsAt: nil)])
        p.bowlQuotaWindow = "automatic"
        let auto = BowlQuotaReading.make(preferences: p, snapshot: weeklyOnly, now: now)
        #expect(auto?.fraction == 0.4); #expect(auto?.detail.contains("七天") == true)
        p.bowlQuotaWindow = "short"
        #expect(BowlQuotaReading.make(preferences: p, snapshot: weeklyOnly, now: now)?.fraction == nil)
    }
    @Test func absentDisabledExpiredAndExhaustedRemainDistinct() {
        var p = Preferences()
        #expect(BowlQuotaReading.make(preferences: p, snapshot: nil, now: now)?.label == "Codex —")
        let zero = snapshot(windows: [.init(id: "primary", usedPercent: 100, durationMinutes: 300, resetsAt: nil)])
        #expect(BowlQuotaReading.make(preferences: p, snapshot: zero, now: now)?.label == "Codex 0%")
        #expect(BowlQuotaReading.make(preferences: p, snapshot: zero, now: now)?.fraction == 0)
        let expired = snapshot(windows: [.init(id: "primary", usedPercent: 60, durationMinutes: 300, resetsAt: now)])
        #expect(BowlQuotaReading.make(preferences: p, snapshot: expired, now: now)?.fraction == nil)
        p.codexEnabled = false
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now)?.fraction == nil)
        p.bowlQuotaSource = "off"
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now) == nil)
    }
    @Test func staleDataIsMarkedAndProviderSwitchNeverReusesWrongAccount() {
        var p = Preferences()
        let stale = BowlQuotaReading.make(preferences: p, snapshot: snapshot(), failed: true, now: now)
        #expect(stale?.fraction == 0.2); #expect(stale?.stale == true); #expect(stale?.label.contains("旧") == true)
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now.addingTimeInterval(1800))?.stale == true)
        p.bowlQuotaSource = "claude"
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot(), now: now)?.fraction == nil)
        #expect(BowlQuotaReading.make(preferences: p, snapshot: snapshot("claude"), now: now)?.label == "Claude 20%")
    }
    @Test func oldSettingsGainDefaultsAndInvalidChoicesNormalize() throws {
        let p = try Preferences.decodeMigrating(Data(#"{"scale":1.25}"#.utf8))
        #expect(p.runWhileDragging); #expect(p.bowlQuotaSource == "codex"); #expect(p.bowlQuotaWindow == "automatic")
        #expect(p.bowlQuotaLabel); #expect(p.scale == 1.25)
        let invalid = try Preferences.decodeMigrating(Data(#"{"bowlQuotaSource":"missing","bowlQuotaWindow":"missing"}"#.utf8))
        #expect(invalid.bowlQuotaSource == "codex"); #expect(invalid.bowlQuotaWindow == "automatic")
    }
}
