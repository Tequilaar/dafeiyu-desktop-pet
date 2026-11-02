import Foundation
import CoreGraphics
import Testing
@testable import DafeiyuCore

struct CompanionTests {
    @Test func pettingNeedsFourRealStrokesOverTheHead() {
        var d = PettingDetector(), t = 0.0
        for x in [0.0, 1, 0, 1, 0, 1, 0, 1, 0] { t += 0.1; let fired = d.add(time: t, x: x, overHead: true); #expect(!fired) }   // jitter only
        var fired = false
        for x in [0.0, 20, 0, 20, 0, 20] { t += 0.1; fired = d.add(time: t, x: 100 + x, overHead: true) || fired }
        #expect(fired)
        var away = PettingDetector(); t = 0
        for (i, x) in [0.0, 20, 0, 20, 0, 20].enumerated() { t += 0.1; let fired = away.add(time: t, x: x, overHead: i != 3); #expect(!fired) }
    }
    @Test func breakClockCountsActiveUseAndResetsAfterAPause() {
        var c = BreakClock()
        for _ in 0..<(24 * 60) { let due = c.tick(elapsed: 1, idle: 3, intervalMinutes: 25); #expect(!due) }
        var due = false
        for _ in 0..<61 { due = c.tick(elapsed: 1, idle: 3, intervalMinutes: 25) || due }
        #expect(due); #expect(c.activeSeconds < 5)
        for _ in 0..<600 { _ = c.tick(elapsed: 1, idle: 3, intervalMinutes: 25) }
        _ = c.tick(elapsed: 1, idle: 400, intervalMinutes: 25); #expect(c.activeSeconds == 0)
        let off = c.tick(elapsed: 1, idle: 0, intervalMinutes: 0); #expect(!off)
    }
    @Test func agentActivityStartsAfterSustainedWorkAndFinishesAfterQuiet() {
        var a = AgentActivity(), events: [AgentActivity.Event] = []
        for t in stride(from: 0.0, through: 80, by: 10) { if let e = a.sample(time: t, cpuPercent: 40) { events.append(e) } }
        for t in stride(from: 90.0, through: 130, by: 10) { if let e = a.sample(time: t, cpuPercent: 1) { events.append(e) } }
        #expect(events == [.started, .finished])
        var short = AgentActivity(); events = []
        for t in stride(from: 0.0, through: 30, by: 10) { if let e = short.sample(time: t, cpuPercent: 40) { events.append(e) } }
        for t in stride(from: 40.0, through: 80, by: 10) { if let e = short.sample(time: t, cpuPercent: 0) { events.append(e) } }
        #expect(events == [.started])   // 30 s of work is too short to announce
    }
    @Test func dayParts() {
        #expect(DayPart(hour: 23) == .lateNight); #expect(DayPart(hour: 3) == .lateNight)
        #expect(DayPart(hour: 7) == .morning); #expect(DayPart(hour: 14) == .day)
    }
    @Test func windowLedges() {
        let windows: [WindowLedge.Window] = [(1, CGRect(x: 100, y: 400, width: 600, height: 300)), (2, CGRect(x: 0, y: 100, width: 900, height: 200))]
        #expect(WindowLedge.under(feetX: 300, feetY: 712, windows: windows)?.id == 1)
        #expect(WindowLedge.under(feetX: 300, feetY: 760, windows: windows) == nil)
        #expect(WindowLedge.under(feetX: 110, feetY: 700, windows: windows) == nil)   // too close to the corner
        #expect(WindowLedge.landing(feetX: 300, fromY: 690, toY: 250, windows: windows)?.id == 2)
        #expect(WindowLedge.landing(feetX: 850, fromY: 900, toY: 0, windows: windows)?.id == 2)
        #expect(WindowLedge.grip(feetX: 300, feetY: 520, reach: 120...250, windows: windows)?.id == 1)   // edge 180 above her feet
        #expect(WindowLedge.grip(feetX: 300, feetY: 640, reach: 120...250, windows: windows) == nil)     // edge at her knees
    }
    @Test func refillNeedsASharpRiseOnTheSameBowl() {
        var r = RefillDetector()
        #expect(r.update(key: "codex|automatic", fraction: 0.06) == nil)     // first reading
        #expect(r.update(key: "codex|automatic", fraction: nil) == nil)      // loading keeps the last level
        #expect(r.update(key: "codex|automatic", fraction: 1) == 0.06)
        #expect(r.update(key: "codex|automatic", fraction: 0.9) == nil)
        #expect(r.update(key: "codex|automatic", fraction: 0.95) == nil)     // small rise
        #expect(r.update(key: "claude|automatic", fraction: 0.2) == nil)
        #expect(r.update(key: "codex|automatic", fraction: 0.9) == nil)      // switching the bowl source is not a reset
    }
    @Test func compactMenuBarText() throws {
        let p = Preferences()
        func reading(_ used: Double) throws -> BowlQuotaReading? {
            BowlQuotaReading.make(preferences: p, snapshot: try QuotaParser.parse(Data("{\"primary\":{\"usedPercent\":\(used),\"windowMinutes\":300}}".utf8), provider: "codex"))
        }
        #expect(try reading(92)?.compact == "8%")
        #expect(try reading(99.5)?.compact == "<1%")
        #expect(BowlQuotaReading.make(preferences: p, snapshot: nil)?.compact == "—")
    }
}

struct WanderPlannerTests {
    let windows: [WindowLedge.Window] = [(1, CGRect(x: 600, y: 20, width: 500, height: 400)), (2, CGRect(x: 100, y: 500, width: 300, height: 200))]
    func sequence(_ values: [Double]) -> () -> Double { var i = 0; return { defer { i += 1 }; return values[min(i, values.count - 1)] } }
    @Test func looksAtADockIconFromBelowIt() {
        let plan = WanderPlanner.plan(feetX: 300, surface: 100...1500, onFloor: true, floorY: 4, windows: windows,
                                      icons: [("Safari", CGRect(x: 1640, y: 400, width: 50, height: 50))], allowClimb: true, standOff: 54, random: sequence([0.1, 0]))
        #expect(plan.target == .icon("Safari")); #expect(plan.stopX == 1500); #expect(plan.lookAt == CGPoint(x: 1665, y: 425))
    }
    @Test func climbsOnlyWindowsThatReachTheFloor() {
        // Window 1 reaches the floor: she walks to its left side and climbs it.
        let climb = WanderPlanner.plan(feetX: 300, surface: 100...1500, onFloor: true, floorY: 4, windows: windows, icons: [],
                                       allowClimb: true, standOff: 54, random: sequence([0.5, 0, 0.1]))
        #expect(climb.climb == .init(windowID: 1, wallX: 600, top: 420, facingRight: true)); #expect(climb.stopX == 546)
        // Window 2 floats: she only walks over and looks at it.
        let look = WanderPlanner.plan(feetX: 300, surface: 100...1500, onFloor: true, floorY: 4, windows: windows, icons: [],
                                      allowClimb: true, standOff: 54, random: sequence([0.5, 0.9, 0.1]))
        #expect(look.climb == nil); #expect(look.target == .window(2)); #expect(look.lookAt == CGPoint(x: 250, y: 600))
        // On a window top she never climbs, and never leaves the ledge.
        let ledge = WanderPlanner.plan(feetX: 700, surface: 624...1076, onFloor: false, floorY: 4, windows: windows, icons: [],
                                       allowClimb: true, standOff: 54, random: sequence([0.5, 0, 0.1]))
        #expect(ledge.climb == nil); #expect((624...1076).contains(ledge.stopX))
    }
    @Test func strollsWithinTheSurfaceWhenNothingIsAround() {
        let plan = WanderPlanner.plan(feetX: 300, surface: 100...1100, onFloor: true, floorY: 4, windows: [], icons: [],
                                      allowClimb: true, standOff: 54, random: sequence([0.9, 1]))
        #expect(plan.target == .stroll); #expect(plan.stopX == 950)
    }
}
