import Foundation
import Testing
@testable import DafeiyuCore

@Suite struct CoreTests {
    @Test func pointerOverBodyAlwaysLooksForward() {
        var gaze = GazeSelector()
        #expect(gaze.update(dx: 0, dy: -100) == 16)
        #expect(gaze.update(dx: 0, dy: -100, overBody: true) == 0)
        #expect(gaze.update(dx: 150, dy: 0) == 8)
    }
    @Test func quotaCountdownPreservesDaysHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(QuotaTimeText.remaining(until: now.addingTimeInterval(90061), now: now) == "还剩 1天 1小时 2分钟")
        #expect(QuotaTimeText.remaining(until: now.addingTimeInterval(-1), now: now) == "等待来源确认重置")
    }
    @Test func forecastRequiresEnoughFreshHistoryAndDoesNotBridgeReset() {
        let now = Date(timeIntervalSince1970: 100_000), reset = Date(timeIntervalSince1970: 120_000)
        let points = [UsagePoint(time: now.addingTimeInterval(-3600), used: 10, reset: reset), UsagePoint(time: now.addingTimeInterval(-1800), used: 20, reset: reset), UsagePoint(time: now, used: 30, reset: reset)]
        let f = QuotaHistory.forecast(points, remaining: 70, reset: reset, now: now)
        #expect(f.hourlyRate == 20); #expect(f.exhaustsAt == now.addingTimeInterval(12600)); #expect(f.enoughUntilReset == false)
        #expect(QuotaHistory.forecast(Array(points.suffix(2)), remaining: 70, reset: reset, now: now).exhaustsAt == nil)
        #expect(QuotaHistory.forecast(points, remaining: 70, reset: reset, now: now.addingTimeInterval(3600)).exhaustsAt == nil)
        #expect(QuotaHistory.forecast(points, remaining: 70, reset: reset.addingTimeInterval(86400), now: now).exhaustsAt == nil)
        let corrected = points + [UsagePoint(time: now.addingTimeInterval(1), used: 2, reset: reset)]
        #expect(QuotaHistory.forecast(corrected, remaining: 98, reset: reset, now: now.addingTimeInterval(1)).exhaustsAt == nil)
    }
    @Test func directProvidersPreserveActualWindowLengths() throws {
        let codex = Data(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":75,"windowDurationMins":10080,"resetsAt":1793603007},"secondary":null}},"rateLimits":{"primary":{"usedPercent":3,"windowDurationMins":300}}}"#.utf8)
        let parsed = try QuotaParser.parseCodex(codex)
        #expect(parsed.windows.count == 1); #expect(parsed.windows[0].isLong)
        #expect(parsed.windows[0].remaining == 25)
        let claude = Data(#"{"five_hour":{"utilization":0,"resets_at":"2026-10-28T01:50:00.256919+00:00"},"seven_day":{"utilization":42,"resets_at":null}}"#.utf8)
        let c = try QuotaParser.parseClaude(claude)
        #expect(c.windows.count == 2); #expect(c.windows[0].remaining == 100)
        #expect(c.windows[0].resetsAt != nil); #expect(c.windows[1].remaining == 58)
    }
    @Test func testPreferencesMigrateAndBoundImportedValues() throws {
        let p = try Preferences.decodeMigrating(Data(#"{"scale":99,"ambientMin":180,"ambientMax":20,"chaseDuration":-3}"#.utf8))
        #expect((p.scale) == (1.5)); #expect((p.ambientMin) == (180)); #expect((p.ambientMax) == (180))
        #expect((p.chaseDuration) == (5)); #expect(p.gaze)
    }
    @Test func testFutureSettingsAreNotSilentlyApplied() {
        #expect(throws: (any Error).self) { try Preferences.decodeMigrating(Data(#"{"schemaVersion":9}"#.utf8)) }
        #expect(throws: (any Error).self) { try Preferences.decodeMigrating(Data("[]".utf8)) }
    }
    @Test func testPortableSettingsDoNotAutoEnableLoginOrCopyCoordinates() throws {
        var p = Preferences(); p.launchAtLogin = true; p.positionX = 500; p.positionY = 300; p.displayID = 42
        let exported = try Preferences.decodeMigrating(p.exportData())
        #expect(!(exported.launchAtLogin)); #expect((exported.positionX) == nil); #expect((exported.displayID) == (0))
    }
    @Test func testStyleDoesNotChangeEnergyMode() {
        var p = Preferences(); p.performance = .economy; p.applyStyle(.lively)
        #expect((p.performance) == (.economy)); #expect((p.ambientMin) == (20))
    }
    @Test func testUnknownQuotaIsDifferentFromExhausted() throws {
        let data = Data(#"[{"provider":"codex","usage":{"primary":{"usedPercent":100,"windowMinutes":300},"secondary":null}}]"#.utf8)
        let snapshot = try QuotaParser.parse(data, provider: "codex")
        #expect((snapshot.windows.count) == (1)); #expect((snapshot.windows[0].remaining) == (0))
        #expect(throws: (any Error).self) { try QuotaParser.parse(Data(#"[{"provider":"codex","usage":{"primary":null}}]"#.utf8), provider: "codex") }
    }
    @Test func testQuotaPreservesWindowAndAccountIdentity() throws {
        let data = Data(#"[{"provider":"claude","usage":{"identity":{"accountEmail":"fixture@example.invalid"},"primary":{"usedPercent":23.5,"windowMinutes":300,"resetsAt":"2026-10-28T12:00:00Z"},"secondary":{"usedPercent":50,"windowMinutes":10080}}},{"provider":"codex","error":{"message":"unavailable"}}]"#.utf8)
        let snapshot = try QuotaParser.parse(data, provider: "claude")
        #expect((snapshot.windows[0].remaining) == (76.5)); #expect((snapshot.windows[1].title) == ("七天"))
        #expect((snapshot.account) == ("fixture@example.invalid")); #expect((snapshot.windows[0].resetsAt) != nil)
        #expect(throws: (any Error).self) { try QuotaParser.parse(data, provider: "codex") }
    }
    @Test func testOutOfRangeQuotaNotInventedAsZero() {
        #expect(throws: (any Error).self) { try QuotaParser.parse(Data(#"{"primary":{"usedPercent":-1}}"#.utf8), provider: "codex") }
    }
    @Test func testResetNeedsNewObservedBoundaryAndIsDeduplicatedPerAccount() throws {
        var receipts = QuotaReceipts()
        let old = Date(timeIntervalSince1970: 1000)
        var a = QuotaSnapshot(provider: "codex", account: "a", windows: [.init(id: "primary", usedPercent: 90, durationMinutes: 300, resetsAt: old)], fetchedAt: old.addingTimeInterval(-10), source: "fixture")
        let first = receipts.observe(a, threshold: 20)
        #expect(!(first.reset)); #expect(first.low)
        #expect(!(receipts.observe(a, threshold: 20).low))
        a.fetchedAt = old.addingTimeInterval(30)
        #expect(!(receipts.observe(a, threshold: 20).reset))
        a.windows[0].resetsAt = old.addingTimeInterval(18000); a.windows[0].usedPercent = 2
        #expect(receipts.observe(a, threshold: 20).reset)
        #expect(!(receipts.observe(a, threshold: 20).reset))
        a.account = "b"
        #expect(!(receipts.observe(a, threshold: 20).reset))
    }
    @Test func testThrowSamplingDoesNotUseTheWholeDragOrKeepStaleSpeed() {
        var sample = ThrowSampler()
        sample.add(time: 0, position: .init(0, 0)); sample.add(time: 1, position: .init(100, 0)); sample.add(time: 1.1, position: .init(150, 0))
        #expect(abs((sample.velocity().x) - (500)) <= 0.001)
        sample.add(time: 1.4, position: .init(150, 0)); #expect((sample.velocity().length) == (0))
    }
    @Test func testThrownBowlStaysInsideScreenAndSettles() {
        let bounds = MotionBounds(minX: 0, minY: 0, maxX: 500, maxY: 600)
        var bowl = BowlMotion(position: .init(250, 300), velocity: .init(5000, 3000))
        #expect((bowl.velocity.length) <= (1600.001))
        for _ in 0..<1800 {
            bowl.step(dt: 1.0 / 60, bounds: bounds, bounce: 0.35)
            #expect((0...500).contains(bowl.position.x)); #expect((0...600).contains(bowl.position.y))
        }
        #expect(bowl.settled); #expect((bowl.position.y) == (0))
    }
    @Test func testGazeWrapsAcrossNorthWithoutWrongLongTurn() {
        var gaze = GazeSelector()
        #expect((gaze.update(dx: -1, dy: 100)) == (0))
        #expect((gaze.update(dx: 1, dy: 100)) == (0))
        #expect((gaze.update(dx: 100, dy: 0)) == (8))
    }
    @Test func gazeHasThirtyTwoReachableDirectionsAndStableBoundaries() {
        var gaze = GazeSelector()
        for i in 0..<32 {
            let angle = Double(i) / 32 * 2 * Double.pi
            #expect(gaze.update(dx: sin(angle) * 300, dy: cos(angle) * 300) == i)
        }
        _ = gaze.update(dx: 0, dy: 100)
        for offset in [0.49,0.51,0.60,0.49,0.51] {
            let angle = offset / 32 * 2 * Double.pi
            #expect(gaze.update(dx: sin(angle) * 300, dy: cos(angle) * 300) == 0)
        }
        #expect(gaze.update(dx: .nan, dy: 100) == 0)
        #expect(gaze.update(dx: 1, dy: 1) == 0)
    }
    @Test func gazeFollowingCrossesSeamAndComesToRest() {
        var gaze = GazeFollower(); gaze.aim(at: 31, immediately: true); gaze.aim(at: 0)
        for _ in 0..<30 {
            gaze.advance(dt: 1.0 / 30)
            #expect(gaze.position >= 31 || gaze.position < 1)
        }
        #expect(gaze.direction == 0); #expect(!gaze.isTurning)
        gaze.aim(at: 16); gaze.advance(dt: 1.0 / 30)
        #expect(gaze.direction > 0 && gaze.direction < 16)
        for _ in 0..<30 { gaze.advance(dt: 1.0 / 30) }
        #expect(gaze.direction == 16); #expect(!gaze.isTurning)
        gaze.aim(at: 0, immediately: true)
        #expect(gaze.direction == 0); #expect(!gaze.isTurning)
    }
    @Test func gazeFollowingIsTimeBasedAndBoundsLongFrameGaps() {
        var a = GazeFollower(), b = GazeFollower(); a.aim(at: 8); b.aim(at: 8)
        for _ in 0..<9 { a.advance(dt: 1.0 / 30) }
        for _ in 0..<18 { b.advance(dt: 1.0 / 60) }
        #expect(abs(a.position - b.position) < 0.15)
        var gap = GazeFollower(); gap.aim(at: 16); gap.advance(dt: 100)
        #expect(gap.position < 3)
        let prior = gap.position; gap.advance(dt: .nan); gap.advance(dt: -1)
        #expect(gap.position == prior)
    }
    @Test func speechStylesCoverEveryCueAndKeepCustomTextPortable() throws {
        var p = Preferences()
        for style in SpeechStyle.allCases {
            p.speechStyle = style
            for cue in SpeechCue.allCases {
                #expect(!p.speech(for: cue).isEmpty)
                #expect(p.speech(for: cue).count <= BubbleText.limit)
            }
        }
        p.customSpeech["wipeRequest"] = "  小鱼洗脸\n今天也要亮晶晶  "
        p.customSpeech["unknown"] = "不应保留"
        p.normalize()
        #expect(p.speech(for: .wipeRequest) == "小鱼洗脸 今天也要亮晶晶")
        #expect(p.customSpeech["unknown"] == nil)
        let loaded = try Preferences.decodeMigrating(p.exportData())
        #expect(loaded.speech(for: .wipeRequest) == p.speech(for: .wipeRequest))
        p.speechStyle = .concise
        #expect(p.customSpeech["wipeRequest"] != nil)
        p.speechEnabled = false; #expect(p.speech(for: .wipeRequest).isEmpty)
        #expect(try Preferences.decodeMigrating(Data("{}".utf8)).speechStyle == .soft)
        #expect(BubbleText.clean(String(repeating: "鱼", count: 100)).count == BubbleText.limit)
    }
    @Test func testStoryBagNeverRepeatsAcrossBagBoundary() {
        var bag = StoryBag(); var previous: Story?
        for _ in 0..<100 {
            let next = bag.next(enabled: Story.allCases)
            #expect((previous) != (next)); previous = next
        }
        #expect((bag.next(enabled: [])) == nil)
        #expect((bag.next(enabled: [.eating])) == (.eating))
    }
}
