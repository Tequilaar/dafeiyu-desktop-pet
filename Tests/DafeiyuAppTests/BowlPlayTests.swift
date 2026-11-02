import Foundation
import AppKit
import Testing
import DafeiyuCore
@testable import Dafeiyu

// 0.1.13: snatching a held bowl, bowl-hit reactions, the accidental kick and repeated-steal anger.
@Suite(.serialized) @MainActor struct BowlPlayTests {
    func controller() -> DesktopController {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "bowl-play-" + UUID().uuidString)
        model.preferences.bowlQuotaSource = "off"; model.preferences.wave = false
        model.preferences.hideInFullscreen = false; model.preferences.respectReduceMotion = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        let visible = NSScreen.screens[0].visibleFrame
        model.preferences.positionX = visible.midX; model.preferences.positionY = visible.minY + 200
        return DesktopController(model: model, assets: AssetStore())
    }
    func close(_ d: DesktopController) { d.stop(); d.panel.close(); d.bowlPanel.close() }
    func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    /// Steps the frame loop with synthetic timestamps (no real time passes).
    func frames(_ d: DesktopController, _ count: Int, until stop: () -> Bool = { false }) {
        var t = ProcessInfo.processInfo.systemUptime
        for _ in 0..<count { t += 1.0 / 60; d.scene.onFrame?(t); if stop() { return } }
    }

    @Test func heldBowlInsideHerReachIsSnatchedInsteadOfRunningInPlace() async throws {
        let d = controller(); defer { close(d) }
        let grab = NSPoint(x: d.bowlPanel.frame.midX, y: d.bowlPanel.frame.midY)
        d.mouseDown(.bowl, event: event(.leftMouseDown, grab))
        let away = NSPoint(x: grab.x + 260, y: grab.y)
        d.mouseDragged(.bowl, event: event(.leftMouseDragged, away))
        #expect(d.model.status == "把饭盆还给我嘛")
        try await Task.sleep(nanoseconds: 700_000_000)
        // Keep holding the bowl still; she runs over and takes it out of the pointer's hand.
        frames(d, 400) { d.model.status == "抱紧饭盆" }
        #expect(d.model.status == "抱紧饭盆")
        let held = d.bowlPanel.frame
        d.mouseDragged(.bowl, event: event(.leftMouseDragged, NSPoint(x: away.x + 300, y: away.y)))
        d.mouseUp(.bowl, event: event(.leftMouseUp, NSPoint(x: away.x + 300, y: away.y)))
        #expect(d.bowlPanel.frame == held)
    }
    @Test func bowlFallingOnHerHeadMakesHerFlinchThenChase() async throws {
        let d = controller(); defer { close(d) }
        d.exerciseThrow(from: Vector(0, 300), velocity: Vector(0, -900), hitCooldown: 0)
        frames(d, 60) { d.scene.faceReaction == 3 }
        #expect(d.scene.faceReaction == 3)                 // eyes squeezed shut
        try await Task.sleep(nanoseconds: 1_000_000_000)   // the flinch lasts 0.9 s of real time
        frames(d, 2)
        #expect(d.scene.faceReaction == 0); #expect(d.model.status == "把饭盆还给我嘛")
    }
    @Test func slowBowlIntoHerBodyIsCaught() throws {
        let d = controller(); defer { close(d) }
        d.exerciseThrow(from: Vector(-170, 110), velocity: Vector(420, 60), hitCooldown: 0)
        frames(d, 60) { d.model.status == "抱紧饭盆" }
        #expect(d.model.status == "抱紧饭盆")
    }
    @Test func bowlSkiddingIntoHerFeetMakesHerHop() async throws {
        let d = controller(); defer { close(d) }
        let floor = d.characterFrame.minY
        d.exerciseThrow(from: Vector(-150, 20), velocity: Vector(900, 0), hitCooldown: 0)
        frames(d, 40) { d.scene.faceReaction == 2 }
        #expect(d.scene.faceReaction == 2)
        // The hop runs on real time; sample through it instead of betting on one sleep under load.
        var highest = floor
        for _ in 0..<14 { try await Task.sleep(nanoseconds: 50_000_000); frames(d, 1); highest = max(highest, d.characterFrame.minY) }
        #expect(highest > floor + 10)
    }
    @Test func sheSometimesKicksTheBowlAwayWhileRunningButOnlyOnce() throws {
        for (roll, expected) in [(0.0, "糟糕，踢飞了"), (0.99, "抱紧饭盆")] {
            let d = controller(); defer { close(d) }
            d.random = { roll }; d.model.preferences.bowlHits = false
            d.exerciseThrow(from: Vector(260, 0), velocity: Vector(30, -10), hitCooldown: 0)
            frames(d, 600) { d.model.status == expected }
            #expect(d.model.status == expected)
        }
    }
    @Test func thirdStealWithinNinetySecondsMakesHerAngryAndFaster() throws {
        func distance(steals: Int) -> Double {
            let d = controller(); defer { close(d) }
            var start = 0.0
            for round in 0..<steals {
                d.resetPosition()
                let grab = NSPoint(x: d.bowlPanel.frame.midX, y: d.bowlPanel.frame.midY)
                d.mouseDown(.bowl, event: event(.leftMouseDown, grab))
                d.mouseDragged(.bowl, event: event(.leftMouseDragged, NSPoint(x: grab.x - 600, y: grab.y)))
                if round < steals - 1 { d.mouseUp(.bowl, event: event(.leftMouseUp, NSPoint(x: grab.x - 600, y: grab.y))) }
                start = d.characterFrame.midX
            }
            frames(d, 60)
            return start - d.characterFrame.midX
        }
        let calm = distance(steals: 1), cross = distance(steals: 3)
        #expect(calm > 50); #expect(cross > calm * 1.2)
    }
}
